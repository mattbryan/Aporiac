import Foundation
import Observation

/// Manages active and archived habits and daily log state for the current user.
@MainActor
@Observable
final class HabitViewModel {
    private(set) var activeHabits: [Habit] = []
    private(set) var archivedHabits: [Habit] = []
    /// Logs for `loadedLogDayStart`, keyed by habit ID — loaded with `activeHabits`.
    private(set) var todayLogs: [UUID: HabitLog] = [:]
    /// Local start-of-day for which `todayLogs` and `setLog` / `cycleLog` apply.
    private(set) var loadedLogDayStart: Date = Calendar.current.startOfDay(for: Date())
    /// `true` until the in-flight `load()` finishes when the caller requests a visible loading state.
    private(set) var isLoading = true
    /// Set when `load()` fails for reasons other than `notAuthenticated` (e.g. network).
    private(set) var lastLoadError: String?

    private var service: SupabaseService { .shared }
    /// Serializes `setLog` mutations per habit so rapid taps and overlapping requests stay ordered.
    private var setLogChainTasks: [UUID: Task<Void, Error>] = [:]

    /// Fetches active habits, archived habits, and logs for `referenceDay` for active habits.
    func load(for referenceDay: Date = Date(), showLoadingState: Bool = true) async throws {
        if showLoadingState { isLoading = true }
        defer { if showLoadingState { isLoading = false } }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: referenceDay)
        let dateKey = HabitLog.dayString(for: dayStart)

        do {
            lastLoadError = nil
            guard let userID = service.currentUser?.id else {
                throw HabitViewModelError.notAuthenticated
            }

            loadedLogDayStart = dayStart

            let active: [Habit] = try await service.client
                .from("habits")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("active", value: true)
                .order("created_at")
                .execute()
                .value

            let archived: [Habit] = try await service.client
                .from("habits")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("active", value: false)
                .order("archived_at", ascending: false)
                .execute()
                .value

            var logsByHabit: [UUID: HabitLog] = [:]
            if active.isEmpty {
                logsByHabit = [:]
            } else {
                let habitIDs = active.map(\.id)
                let logs: [HabitLog] = try await service.client
                    .from("habit_logs")
                    .select()
                    .in("habit_id", values: habitIDs)
                    .eq("date", value: dateKey)
                    .execute()
                    .value
                logsByHabit = Dictionary(uniqueKeysWithValues: logs.map { ($0.habitID, $0) })
            }

            activeHabits = active
            archivedHabits = archived
            todayLogs = logsByHabit
        } catch {
            if case HabitViewModelError.notAuthenticated = error {} else {
                lastLoadError = "Couldn’t load habits."
            }
            throw error
        }
    }

    /// Inserts a new active habit and appends to `activeHabits`, reverting on failure.
    func create(title: String, fullCriteria: String, partialCriteria: String) async throws {
        guard let user = service.currentUser else {
            throw HabitViewModelError.notAuthenticated
        }

        let habit = Habit(
            id: UUID(),
            userID: user.id,
            title: title,
            fullCriteria: fullCriteria,
            partialCriteria: partialCriteria,
            active: true,
            archivedAt: nil,
            createdAt: Date()
        )

        let insert = HabitInsert(
            id: habit.id,
            userID: habit.userID,
            title: habit.title,
            fullCriteria: habit.fullCriteria,
            partialCriteria: habit.partialCriteria,
            active: habit.active,
            archivedAt: habit.archivedAt,
            createdAt: habit.createdAt
        )

        let snapshot = activeHabits
        activeHabits.append(habit)

        do {
            try await service.client
                .from("habits")
                .insert(insert)
                .execute()
        } catch {
            activeHabits = snapshot
            throw error
        }
    }

    /// Updates the editable fields in Supabase and in `activeHabits`, reverting on failure.
    func update(habit: Habit, title: String, fullCriteria: String, partialCriteria: String) async throws {
        guard let userID = service.currentUser?.id else {
            throw HabitViewModelError.notAuthenticated
        }
        guard let index = activeHabits.firstIndex(where: { $0.id == habit.id }) else {
            throw HabitViewModelError.habitNotInActiveList
        }

        let snapshot = activeHabits
        var updated = activeHabits[index]
        updated.title = title
        updated.fullCriteria = fullCriteria
        updated.partialCriteria = partialCriteria
        activeHabits[index] = updated

        do {
            try await service.client
                .from("habits")
                .update(HabitContentUpdate(title: title, fullCriteria: fullCriteria, partialCriteria: partialCriteria))
                .eq("id", value: habit.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeHabits = snapshot
            throw error
        }
    }

    /// Marks the habit archived remotely and moves it from `activeHabits` to `archivedHabits`, reverting on failure.
    func archive(_ habit: Habit) async throws {
        guard let userID = service.currentUser?.id else {
            throw HabitViewModelError.notAuthenticated
        }
        guard let index = activeHabits.firstIndex(where: { $0.id == habit.id }) else {
            throw HabitViewModelError.habitNotInActiveList
        }

        let archivedAt = Date.now
        var archivedHabit = activeHabits[index]
        archivedHabit.active = false
        archivedHabit.archivedAt = archivedAt

        let activeSnapshot = activeHabits
        let archivedSnapshot = archivedHabits
        let logsSnapshot = todayLogs

        activeHabits.remove(at: index)
        archivedHabits.insert(archivedHabit, at: 0)
        todayLogs.removeValue(forKey: habit.id)

        do {
            try await service.client
                .from("habits")
                .update(ArchiveUpdate(active: false, archivedAt: archivedAt))
                .eq("id", value: habit.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeHabits = activeSnapshot
            archivedHabits = archivedSnapshot
            todayLogs = logsSnapshot
            throw error
        }
    }

    /// Marks the habit active remotely and moves it from `archivedHabits` back to `activeHabits`, reverting on failure.
    func unarchive(_ habit: Habit) async throws {
        guard let userID = service.currentUser?.id else {
            throw HabitViewModelError.notAuthenticated
        }
        guard let index = archivedHabits.firstIndex(where: { $0.id == habit.id }) else {
            throw HabitViewModelError.habitNotInArchivedList
        }

        var activeHabit = archivedHabits[index]
        activeHabit.active = true
        activeHabit.archivedAt = nil

        let activeSnapshot = activeHabits
        let archivedSnapshot = archivedHabits
        let logsSnapshot = todayLogs

        archivedHabits.remove(at: index)
        activeHabits.insert(activeHabit, at: 0)

        do {
            try await service.client
                .from("habits")
                .update(ArchiveUpdate(active: true, archivedAt: nil))
                .eq("id", value: habit.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            activeHabits = activeSnapshot
            archivedHabits = archivedSnapshot
            todayLogs = logsSnapshot
            throw error
        }
    }

    func setLog(habitID: UUID, credit: Float) async throws {
        let key = habitID
        let predecessor = setLogChainTasks[key]
        let next = Task { @MainActor in
            if let predecessor {
                _ = try? await predecessor.value
            }
            try await self.applySetLog(habitID: key, credit: credit)
        }
        setLogChainTasks[key] = next
        try await next.value
    }

    /// Cycles today's log for a habit: nil/0 → 0.5 → 1.0 → 0.
    /// Uses the same task-chaining as `setLog` so rapid calls sequence correctly and
    /// each call reads the state left by the previous one.
    func cycleLog(habitID: UUID) async throws {
        let key = habitID
        let predecessor = setLogChainTasks[key]
        let next = Task { @MainActor in
            if let predecessor {
                _ = try? await predecessor.value
            }
            let epsilon: Float = 0.01
            let current = self.todayLogs[key]?.credit
            let nextCredit: Float
            if current == nil || (current.map { abs($0) < epsilon } ?? false) {
                nextCredit = 0.5
            } else if current.map({ abs($0 - 0.5) < epsilon }) ?? false {
                nextCredit = 1.0
            } else {
                nextCredit = 0.0
            }
            try await self.applySetLog(habitID: key, credit: nextCredit)
        }
        setLogChainTasks[key] = next
        try await next.value
    }

    private func applySetLog(habitID: UUID, credit: Float) async throws {
        let dayStr = HabitLog.dayString(for: loadedLogDayStart)

        if credit == 0 {
            // Optimistic remove
            let snapshot = todayLogs[habitID]
            todayLogs.removeValue(forKey: habitID)
            do {
                try await service.client
                    .from("habit_logs")
                    .delete()
                    .eq("habit_id", value: habitID.uuidString)
                    .eq("date", value: dayStr)
                    .execute()
            } catch {
                todayLogs[habitID] = snapshot // revert
                throw error
            }
        } else {
            // Optimistic insert — use a placeholder ID; replaced by confirmed log
            let placeholder = HabitLog(
                id: UUID(),
                habitID: habitID,
                date: dayStr,
                credit: credit
            )
            let snapshot = todayLogs[habitID]
            todayLogs[habitID] = placeholder
            do {
                let confirmed: HabitLog = try await service.client
                    .from("habit_logs")
                    .upsert(
                        HabitLogInsert(habitID: habitID, date: dayStr, credit: credit),
                        onConflict: "habit_id,date"
                    )
                    .select()
                    .single()
                    .execute()
                    .value
                todayLogs[habitID] = confirmed
            } catch {
                todayLogs[habitID] = snapshot // revert
                throw error
            }
        }
    }

    /// Fetches all logs for a habit within a calendar month (inclusive bounds).
    func fetchLogs(habitID: UUID, month: Int, year: Int) async throws -> [HabitLog] {
        guard let firstOfMonth = monthFirstDate(month: month, year: year),
              let lastOfMonth = monthLastDate(month: month, year: year) else {
            throw HabitViewModelError.invalidMonth
        }
        let firstString = HabitLog.dateFormatter.string(from: firstOfMonth)
        let lastString = HabitLog.dateFormatter.string(from: lastOfMonth)

        return try await service.client
            .from("habit_logs")
            .select()
            .eq("habit_id", value: habitID.uuidString)
            .gte("date", value: firstString)
            .lte("date", value: lastString)
            .execute()
            .value
    }

    private func monthFirstDate(month: Int, year: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private func monthLastDate(month: Int, year: Int) -> Date? {
        guard let first = monthFirstDate(month: month, year: year),
              let nextStart = Calendar.current.date(byAdding: .month, value: 1, to: first) else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: -1, to: nextStart)
    }
}

private struct HabitInsert: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let title: String
    let fullCriteria: String
    let partialCriteria: String
    let active: Bool
    let archivedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case fullCriteria = "full_criteria"
        case partialCriteria = "partial_criteria"
        case active
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
}

private struct HabitContentUpdate: Encodable, Sendable {
    let title: String
    let fullCriteria: String
    let partialCriteria: String

    enum CodingKeys: String, CodingKey {
        case title
        case fullCriteria = "full_criteria"
        case partialCriteria = "partial_criteria"
    }
}

private struct ArchiveUpdate: Encodable, Sendable {
    let active: Bool
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case active
        case archivedAt = "archived_at"
    }
}

private struct HabitLogInsert: Encodable, Sendable {
    let habitID: UUID
    let date: String
    let credit: Float

    enum CodingKeys: String, CodingKey {
        case habitID = "habit_id"
        case date
        case credit
    }
}

private enum HabitViewModelError: Error {
    case notAuthenticated
    case habitNotInActiveList
    case habitNotInArchivedList
    case invalidMonth
}
