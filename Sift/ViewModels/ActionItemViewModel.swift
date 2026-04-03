import Foundation
import Observation

@MainActor
@Observable
final class ActionItemViewModel {
    private(set) var items: [ActionItem] = []

    private var service: SupabaseService { .shared }
    private var contentUpdateTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Load

    func load() async {
        guard let userID = service.currentUser?.id else { return }
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowISO8601 = formatter.string(from: now)
        let expiryOrClause = "expires_at.is.null,expires_at.gt.\(nowISO8601)"

        do {
            let active: [ActionItem] = try await service.client
                .from("action_items")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("completed", value: false)
                .or(expiryOrClause)
                .order("created_at")
                .execute()
                .value

            let completed: [ActionItem] = try await service.client
                .from("action_items")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("completed", value: true)
                .or(expiryOrClause)
                .order("created_at")
                .execute()
                .value

            items = active + completed

            let startOfToday = Calendar.current.startOfDay(for: now)
            for index in items.indices {
                let item = items[index]
                guard !item.completed,
                      item.createdAt < startOfToday,
                      !item.carriedForward
                else { continue }

                items[index].carriedForward = true
                let id = item.id
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
        } catch {
            print("Failed to load action items: \(error)")
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

    private func setCompleted(_ item: ActionItem, completed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].completed = completed
        let id = item.id
        Task {
            do {
                try await service.client
                    .from("action_items")
                    .update(CompletionUpdate(completed: completed))
                    .eq("id", value: id.uuidString)
                    .execute()
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].completed = !completed
                }
                print("Failed to update action item: \(error)")
            }
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
        items[index].content = content
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

private struct CompletionUpdate: Encodable {
    let completed: Bool
}

private struct ContentUpdate: Encodable {
    let content: String
}

private struct CarriedForwardUpdate: Encodable {
    let carriedForward: Bool

    enum CodingKeys: String, CodingKey {
        case carriedForward = "carried_forward"
    }
}
