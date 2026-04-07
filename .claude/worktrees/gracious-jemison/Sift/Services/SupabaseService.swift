import Foundation
import Supabase

/// Shared Supabase client. Configured for the `sift` schema.
@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private(set) var currentUser: User?

    /// Debounced gem text saves keyed by gem id.
    private var gemFragmentSaveTasks: [UUID: Task<Void, Never>] = [:]

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: .init(schema: "sift"),
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    var isAuthenticated: Bool { currentUser != nil }

    /// Restores an existing session or signs in anonymously on first launch.
    func initialize() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            print("[Auth] Restored session for \(session.user.id)")
        } catch {
            print("[Auth] No existing session — signing in anonymously")
            await signInAnonymously()
        }
    }

    private func signInAnonymously() async {
        do {
            let session = try await client.auth.signInAnonymously()
            currentUser = session.user
            print("[Auth] Anonymous sign-in succeeded: \(session.user.id)")
        } catch {
            print("[Auth] Anonymous sign-in failed: \(error)")
        }
    }

    /// Today's entry row if one exists, without creating a new row.
    func fetchTodayEntry() async throws -> Entry? {
        try await fetchEntry(on: Calendar.current.startOfDay(for: Date()))
    }

    /// Latest entry created on `calendarDayStart` (local start-of-day) if one exists.
    func fetchEntry(on calendarDayStart: Date) async throws -> Entry? {
        guard let userID = currentUser?.id else { return nil }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: calendarDayStart)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let formatter = ISO8601DateFormatter()
        let entries: [Entry] = try await client
            .from("entries")
            .select()
            .eq("user_id", value: userID.uuidString)
            .gte("created_at", value: formatter.string(from: dayStart))
            .lt("created_at", value: formatter.string(from: nextDayStart))
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return entries.first
    }

    /// All entry row IDs created on `calendarDayStart` (local calendar day), oldest first.
    func fetchEntryIDs(on calendarDayStart: Date) async throws -> [UUID] {
        guard let userID = currentUser?.id else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: calendarDayStart)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let formatter = ISO8601DateFormatter()
        let rows: [SupabaseEntryIDRow] = try await client
            .from("entries")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .gte("created_at", value: formatter.string(from: dayStart))
            .lt("created_at", value: formatter.string(from: nextDayStart))
            .order("created_at", ascending: true)
            .execute()
            .value

        return rows.map(\.id)
    }

    /// Gems flagged on a specific entry, with active theme chips joined in memory (same shape as `GemViewModel` rows).
    func fetchGemsWithThemes(forEntryID entryID: UUID) async throws -> [GemWithThemes] {
        try await fetchGemsWithThemes(forEntryIDs: [entryID])
    }

    /// Gems for any of the given entries (e.g. every session on one calendar day), `created_at` ascending.
    func fetchGemsWithThemes(forEntryIDs entryIDs: [UUID]) async throws -> [GemWithThemes] {
        guard let userID = currentUser?.id else { return [] }

        let uniqueIDs = Array(Set(entryIDs))
        guard !uniqueIDs.isEmpty else { return [] }

        let gems: [Gem] = try await client
            .from("gems")
            .select()
            .eq("user_id", value: userID.uuidString)
            .in("entry_id", values: uniqueIDs.map(\.uuidString))
            .order("created_at", ascending: true)
            .execute()
            .value

        let gemIDs = gems.map(\.id)

        let gemThemeRows: [SupabaseGemThemeRow]
        if gemIDs.isEmpty {
            gemThemeRows = []
        } else {
            gemThemeRows = try await client
                .from("gem_themes")
                .select()
                .in("gem_id", values: gemIDs)
                .execute()
                .value
        }

        let themes: [Theme] = try await client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("created_at")
            .execute()
            .value

        let themeByID = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })

        var themesByGemID: [UUID: [Theme]] = [:]
        for row in gemThemeRows {
            guard let theme = themeByID[row.themeID] else { continue }
            themesByGemID[row.gemID, default: []].append(theme)
        }

        return gems.map { gem in
            GemWithThemes(gem: gem, themes: themesByGemID[gem.id] ?? [])
        }
    }

    /// One gem by id for the current user, joined with active theme chips (same shape as list rows).
    func fetchGemWithThemes(gemID: UUID) async throws -> GemWithThemes? {
        guard let userID = currentUser?.id else { return nil }

        let gems: [Gem] = try await client
            .from("gems")
            .select()
            .eq("id", value: gemID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let gem = gems.first else { return nil }

        let gemThemeRows: [SupabaseGemThemeRow] = try await client
            .from("gem_themes")
            .select()
            .eq("gem_id", value: gemID.uuidString)
            .execute()
            .value

        let themes: [Theme] = try await client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("created_at")
            .execute()
            .value

        let themeByID = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
        let linkedThemes = gemThemeRows.compactMap { themeByID[$0.themeID] }

        return GemWithThemes(gem: gem, themes: linkedThemes)
    }

    /// Active themes for the current user (same filter as gem list chips).
    func fetchActiveThemes() async throws -> [Theme] {
        guard let userID = currentUser?.id else { return [] }

        return try await client
            .from("themes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("created_at")
            .execute()
            .value
    }

    /// Removes one `gem_themes` row.
    func removeGemThemeLink(gemID: UUID, themeID: UUID) async throws {
        try await client
            .from("gem_themes")
            .delete()
            .eq("gem_id", value: gemID.uuidString)
            .eq("theme_id", value: themeID.uuidString)
            .execute()
    }

    /// Inserts one `gem_themes` row (no-op if the pair already exists is handled by caller / DB).
    func addGemThemeLink(gemID: UUID, themeID: UUID) async throws {
        try await client
            .from("gem_themes")
            .insert(SupabaseGemThemeInsert(gemID: gemID, themeID: themeID))
            .execute()
    }

    /// Deletes a gem, its theme links, then updates `entries.has_gem` for the entry.
    func deleteGem(id: UUID) async throws {
        guard let userID = currentUser?.id else { return }

        let rows: [Gem] = try await client
            .from("gems")
            .select()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let gem = rows.first else { return }
        let entryID = gem.entryID

        try await client
            .from("gem_themes")
            .delete()
            .eq("gem_id", value: id.uuidString)
            .execute()

        try await client
            .from("gems")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        let entryRows: [Entry] = (try? await client
            .from("entries")
            .select()
            .eq("id", value: entryID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value) ?? []

        if let entry = entryRows.first {
            let gemLine = "> \(gem.content)"

            var patchedContent = entry.content
            if let range = patchedContent.range(of: "\(gemLine)\n", options: .literal) {
                patchedContent.removeSubrange(range)
            } else if let range = patchedContent.range(of: gemLine, options: .literal) {
                patchedContent.removeSubrange(range)
            }

            if patchedContent != entry.content {
                try? await client
                    .from("entries")
                    .update(EntryContentFieldOnlyUpdate(content: patchedContent))
                    .eq("id", value: entry.id.uuidString)
                    .execute()
            }
        }

        try await reconcileEntryGemFlag(forEntryID: entryID)
    }

    /// Patches the entry body’s first `> {old}` line to `> {new}` when present, updates `gems.content`, then reconciles `entries.has_gem`.
    func updateGemFragment(id gemID: UUID, newContent: String) async throws {
        guard let userID = currentUser?.id else {
            throw SupabaseGemFragmentError.notAuthenticated
        }

        let gemRows: [Gem] = try await client
            .from("gems")
            .select()
            .eq("id", value: gemID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let gem = gemRows.first else {
            throw SupabaseGemFragmentError.gemNotFound
        }

        let entryRows: [Entry] = try await client
            .from("entries")
            .select()
            .eq("id", value: gem.entryID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let entry = entryRows.first else {
            throw SupabaseGemFragmentError.entryNotFound
        }

        let oldLine = "> \(gem.content)"
        let newLine = "> \(newContent)"

        if let range = entry.content.range(of: oldLine, options: .literal) {
            let patchedContent = entry.content.replacingCharacters(in: range, with: newLine)
            try await client
                .from("entries")
                .update(EntryContentFieldOnlyUpdate(content: patchedContent))
                .eq("id", value: entry.id.uuidString)
                .execute()
        }

        try await client
            .from("gems")
            .update(["content": newContent])
            .eq("id", value: gemID.uuidString)
            .execute()

        try await reconcileEntryGemFlag(forEntryID: gem.entryID)
    }

    /// Writes a gem fragment after idle typing (mirrors action item content debounce).
    func scheduleGemFragmentSave(
        gemID: UUID,
        content: String,
        onComplete: (@MainActor () async -> Void)? = nil
    ) {
        gemFragmentSaveTasks[gemID]?.cancel()
        gemFragmentSaveTasks[gemID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            do {
                try await updateGemFragment(id: gemID, newContent: content)
            } catch {
                print("[Supabase] updateGemFragment failed: \(error)")
            }
            await onComplete?()
        }
    }

    func reconcileEntryGemFlag(forEntryID entryID: UUID) async throws {
        let gems: [Gem] = try await client
            .from("gems")
            .select()
            .eq("entry_id", value: entryID.uuidString)
            .execute()
            .value

        let hasGem = !gems.isEmpty
        try await client
            .from("entries")
            .update(SupabaseEntryHasGemUpdate(hasGem: hasGem))
            .eq("id", value: entryID.uuidString)
            .execute()
    }

    /// Loads the signed-in user’s `public.user_settings` row, creating one if missing.
    func fetchOrCreateUserSettings() async throws -> UserSettings {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        let rows: [UserSettings] = try await client.schema("public").from("user_settings")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .limit(1)
            .execute()
            .value
        if let existing = rows.first {
            return existing
        }
        let toInsert = UserSettings(userID: user.id, lastThemeReview: nil, lastHabitReview: nil)
        do {
            return try await client.schema("public").from("user_settings")
                .insert(toInsert)
                .select()
                .single()
                .execute()
                .value
        } catch {
            let retry: [UserSettings] = try await client.schema("public").from("user_settings")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .limit(1)
                .execute()
                .value
            if let created = retry.first {
                return created
            }
            throw error
        }
    }

    /// Sets `last_theme_review` to now for the current user.
    func updateLastThemeReview() async throws {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        try await client.schema("public").from("user_settings")
            .update(ThemeReviewUpdate(lastThemeReview: Date.now))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    /// Sets `last_habit_review` to now for the current user.
    func updateLastHabitReview() async throws {
        guard let user = currentUser else {
            throw SupabaseUserSettingsError.notAuthenticated
        }
        try await client.schema("public").from("user_settings")
            .update(HabitReviewUpdate(lastHabitReview: Date.now))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    /// Waits until `currentUser` is set (e.g. after `initialize()` restores the session), or until `maxWait` elapses.
    func waitForCurrentUser(maxWait: Duration = .seconds(20)) async {
        let deadline = ContinuousClock.now + maxWait
        while currentUser == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Updates an action item's completion state and reflects the change in the entry text (`- [ ]` / `* [ ]` ↔ checked).
    /// If `entryID` is nil or the entry cannot be found, only the action record is updated.
    func patchActionCompletion(
        actionID: UUID,
        entryID: UUID?,
        content: String,
        completed: Bool
    ) async throws {
        let completedAt: Date? = completed ? Date() : nil
        do {
            try await client
                .from("action_items")
                .update(ActionCompletionPatch(completed: completed, completedAt: completedAt))
                .eq("id", value: actionID.uuidString)
                .execute()
        } catch {
            try await client
                .from("action_items")
                .update(ActionCompletionFallbackStringPatch(completed: completed, completedAt: completedAt))
                .eq("id", value: actionID.uuidString)
                .execute()
        }

        guard let entryID else { return }

        let rows: [EntryContentRow] = try await client
            .from("entries")
            .select("id, content")
            .eq("id", value: entryID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return }

        guard let patchedContent = EntryMarkdownActionSync.setTaskCompletion(
            in: row.content,
            taskBody: content,
            completed: completed
        ), patchedContent != row.content else {
            return
        }

        try await client
            .from("entries")
            .update(EntryContentFieldOnlyUpdate(content: patchedContent))
            .eq("id", value: entryID.uuidString)
            .execute()
    }

    /// When the user completes or uncompletes a task on Today, mirror `- [ ]` ↔ `- [x]` in the entry body (if this row is tied to an entry).
    func syncActionCheckboxToEntryContent(entryID: UUID, taskBody: String, completed: Bool) async {
        guard let userID = currentUser?.id else { return }
        do {
            let rows: [Entry] = try await client
                .from("entries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("id", value: entryID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let entry = rows.first else { return }
            guard let next = EntryMarkdownActionSync.setTaskCompletion(
                in: entry.content,
                taskBody: taskBody,
                completed: completed
            ) else { return }
            guard next != entry.content else { return }
            try await client
                .from("entries")
                .update(EntryContentFieldOnlyUpdate(content: next))
                .eq("id", value: entryID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            print("[Supabase] syncActionCheckboxToEntryContent failed: \(error)")
        }
    }
}

private struct ThemeReviewUpdate: Encodable, Sendable {
    let lastThemeReview: Date

    enum CodingKeys: String, CodingKey {
        case lastThemeReview = "last_theme_review"
    }
}

private struct HabitReviewUpdate: Encodable, Sendable {
    let lastHabitReview: Date

    enum CodingKeys: String, CodingKey {
        case lastHabitReview = "last_habit_review"
    }
}

private enum SupabaseUserSettingsError: Error {
    case notAuthenticated
}

private struct SupabaseEntryIDRow: Decodable, Sendable {
    let id: UUID
}

private struct SupabaseGemThemeRow: Codable, Sendable {
    let gemID: UUID
    let themeID: UUID

    enum CodingKeys: String, CodingKey {
        case gemID = "gem_id"
        case themeID = "theme_id"
    }
}

private struct SupabaseGemThemeInsert: Encodable, Sendable {
    let gemID: UUID
    let themeID: UUID

    enum CodingKeys: String, CodingKey {
        case gemID = "gem_id"
        case themeID = "theme_id"
    }
}

private struct SupabaseEntryHasGemUpdate: Encodable, Sendable {
    let hasGem: Bool

    enum CodingKeys: String, CodingKey {
        case hasGem = "has_gem"
    }
}

private struct EntryContentFieldOnlyUpdate: Encodable, Sendable {
    let content: String
}

private enum SupabaseGemFragmentError: Error {
    case notAuthenticated
    case gemNotFound
    case entryNotFound
}

private struct ActionCompletionPatch: Encodable {
    let completed: Bool
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completed
        case completedAt = "completed_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completed, forKey: .completed)
        if let completedAt {
            try container.encode(completedAt, forKey: .completedAt)
        } else {
            try container.encodeNil(forKey: .completedAt)
        }
    }
}

private struct ActionCompletionFallbackStringPatch: Encodable {
    let completed: Bool
    let completed_at: String?

    init(completed: Bool, completedAt: Date?) {
        self.completed = completed
        if let completedAt {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            self.completed_at = f.string(from: completedAt)
        } else {
            self.completed_at = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(completed, forKey: .completed)
        if let completed_at {
            try c.encode(completed_at, forKey: .completed_at)
        } else {
            try c.encodeNil(forKey: .completed_at)
        }
    }

    enum CodingKeys: String, CodingKey {
        case completed
        case completed_at
    }
}

private struct EntryContentRow: Decodable {
    let id: UUID
    let content: String
}
