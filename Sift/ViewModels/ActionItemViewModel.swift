import Foundation
import Observation

@MainActor
@Observable
final class ActionItemViewModel {
    private(set) var items: [ActionItem] = []
    /// `true` until the in-flight `load()` finishes when the caller requests a visible loading state.
    private(set) var isLoading = true
    /// Action IDs with a completion patch in flight (avoids racing toggles).
    private(set) var completionSyncInFlightIDs: Set<UUID> = []

    private var service: SupabaseService { .shared }
    private var contentUpdateTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Load

    func load(for day: Date = Date(), showLoadingState: Bool = true) async {
        if showLoadingState { isLoading = true }
        defer { if showLoadingState { isLoading = false } }

        guard let userID = service.currentUser?.id else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        // PostgREST filter values must not include extra `.` segments (e.g. fractional seconds) or `gte` / `or` parsing breaks.
        let filterFormatter = ISO8601DateFormatter()
        filterFormatter.formatOptions = [.withInternetDateTime]

        let now = Date()
        let nowISO = filterFormatter.string(from: now)
        let expiryOrClause = "expires_at.is.null,expires_at.gt.\(nowISO)"

        let active: [ActionItem]
        do {
            active = try await service.client
                .from("action_items")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("completed", value: false)
                .or(expiryOrClause)
                .order("created_at")
                .execute()
                .value
        } catch {
            print("Failed to load active action items: \(error)")
            return
        }

        var completed: [ActionItem] = []
        do {
            let startISO = filterFormatter.string(from: startOfDay)
            let endISO = filterFormatter.string(from: startOfNextDay)
            completed = try await service.client
                .from("action_items")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("completed", value: true)
                .gte("completed_at", value: startISO)
                .lt("completed_at", value: endISO)
                .order("completed_at")
                .execute()
                .value
        } catch {
            // e.g. `completed_at` missing in DB — still show active items
            print("Failed to load completed action items for day (active list still shown): \(error)")
        }

        items = active + completed

        // Carry-forward logic only applies when viewing today
        if calendar.isDate(day, inSameDayAs: now) {
            let startOfToday = calendar.startOfDay(for: now)
            for index in items.indices {
                let row = items[index]
                guard !row.completed,
                      row.createdAt < startOfToday,
                      !row.carriedForward
                else { continue }

                var updated = row
                updated.carriedForward = true
                items[index] = updated
                let id = row.id
                Task {
                    do {
                        try await service.client
                            .from("action_items")
                            .update(CarriedForwardUpdate(carriedForward: true))
                            .eq("id", value: id.uuidString)
                            .execute()
                    } catch {
                        print("Failed to update carried_forward: \(error)")
                    }
                }
            }
        }
    }

    // MARK: Create

    @discardableResult
    func create() async -> ActionItem? {
        guard let userID = service.currentUser?.id else { return nil }
        guard let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date()) else { return nil }
        let item = ActionItem(
            id: UUID(),
            userID: userID,
            entryID: nil,
            content: "",
            completed: false,
            rangeStart: nil,
            rangeEnd: nil,
            createdAt: Date(),
            carriedForward: false,
            expiresAt: expiresAt
        )
        items.append(item)
        do {
            try await service.client
                .from("action_items")
                .insert(item)
                .execute()
        } catch {
            items.removeAll { $0.id == item.id }
            print("Failed to create action item: \(error)")
            return nil
        }
        return item
    }

    /// Inserts a new active item immediately after `anchor` in display order (`created_at`),
    /// using midpoint timestamps when needed so it sorts between neighbors.
    @discardableResult
    func create(after anchor: ActionItem, content: String) async -> ActionItem? {
        guard let userID = service.currentUser?.id else { return nil }
        guard let anchorRow = items.first(where: { $0.id == anchor.id }),
              !anchorRow.completed
        else { return nil }

        let active = activeItems
        guard let idx = active.firstIndex(where: { $0.id == anchor.id }) else { return nil }

        let newCreatedAt: Date
        if idx + 1 < active.count {
            let t0 = active[idx].createdAt.timeIntervalSinceReferenceDate
            let t1 = active[idx + 1].createdAt.timeIntervalSinceReferenceDate
            var mid = (t0 + t1) / 2
            if mid <= t0 { mid = t0 + 0.001 }
            if mid >= t1, t1 > t0 { mid = t1 - 0.001 }
            if mid <= t0 { mid = t0 + 0.001 }
            newCreatedAt = Date(timeIntervalSinceReferenceDate: mid)
        } else {
            newCreatedAt = Date()
        }

        guard let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date()) else { return nil }
        let item = ActionItem(
            id: UUID(),
            userID: userID,
            entryID: nil,
            content: content,
            completed: false,
            rangeStart: nil,
            rangeEnd: nil,
            createdAt: newCreatedAt,
            carriedForward: false,
            expiresAt: expiresAt
        )

        items.append(item)
        items.sort { $0.createdAt < $1.createdAt }

        do {
            try await service.client
                .from("action_items")
                .insert(item)
                .execute()
        } catch {
            items.removeAll { $0.id == item.id }
            print("Failed to create action item: \(error)")
            return nil
        }
        return item
    }

    // MARK: Complete / Uncomplete

    func complete(_ item: ActionItem) {
        setCompleted(item, completed: true)
    }

    func uncomplete(_ item: ActionItem) {
        setCompleted(item, completed: false)
    }

    /// Toggles `completed` using the live state from `items`, not a captured copy.
    func toggle(_ item: ActionItem) {
        guard let live = items.first(where: { $0.id == item.id }) else { return }
        setCompleted(live, completed: !live.completed)
    }

    private func setCompleted(_ item: ActionItem, completed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard !completionSyncInFlightIDs.contains(item.id) else { return }
        var inFlight = completionSyncInFlightIDs
        inFlight.insert(item.id)
        completionSyncInFlightIDs = inFlight

        let previousCompleted = items[index].completed
        let previousCompletedAt = items[index].completedAt
        var updated = items[index]
        updated.completed = completed
        updated.completedAt = completed ? Date() : nil
        items[index] = updated
        let id = item.id
        let entryID = item.entryID
        let taskBody = item.content
        Task { @MainActor in
            defer {
                var ids = completionSyncInFlightIDs
                ids.remove(id)
                completionSyncInFlightIDs = ids
            }
            do {
                try await service.patchActionCompletion(
                    actionID: id,
                    entryID: entryID,
                    content: taskBody,
                    completed: completed
                )
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) {
                    var reverted = items[i]
                    reverted.completed = previousCompleted
                    reverted.completedAt = previousCompletedAt
                    items[i] = reverted
                }
                print("Failed to patch action completion: \(error)")
                return
            }
            NotificationCenter.default.post(
                name: .siftActionCompletionChanged,
                object: nil,
                userInfo: [
                    "actionContent": taskBody,
                    "completed": completed,
                    "entryID": entryID as Any
                ]
            )
        }
    }

    // MARK: Delete

    func delete(_ item: ActionItem) {
        items.removeAll { $0.id == item.id }
        let id = item.id
        Task {
            do {
                try await service.client
                    .from("action_items")
                    .delete()
                    .eq("id", value: id.uuidString)
                    .execute()
            } catch {
                print("Failed to delete action item: \(error)")
            }
        }
    }

    // MARK: Update Content

    func updateContent(_ item: ActionItem, content: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.content = content
        items[index] = updated
        let id = item.id
        contentUpdateTasks[id]?.cancel()
        contentUpdateTasks[id] = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            do {
                try await service.client
                    .from("action_items")
                    .update(ContentUpdate(content: content))
                    .eq("id", value: id.uuidString)
                    .execute()
            } catch {
                print("Failed to update action item content: \(error)")
            }
        }
    }

    // MARK: Computed

    var activeItems: [ActionItem] { items.filter { !$0.completed } }
    var completedItems: [ActionItem] { items.filter { $0.completed } }
    var sortedItems: [ActionItem] { activeItems + completedItems }
}

// MARK: - Update payloads

private struct ContentUpdate: Encodable {
    let content: String
}

private struct CarriedForwardUpdate: Encodable {
    let carriedForward: Bool

    enum CodingKeys: String, CodingKey {
        case carriedForward = "carried_forward"
    }
}
