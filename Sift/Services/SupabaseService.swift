import Foundation
import Supabase

/// Shared Supabase client. Configured for the `sift` schema.
@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private(set) var currentUser: User?
    /// True once `initialize()` has completed — used to gate the auth splash.
    private(set) var isAuthReady = false

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

    /// Restores an existing named session on launch. Sets `isAuthReady` when done.
    func initialize() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            print("[Auth] Restored session for \(session.user.id)")
        } catch {
            print("[Auth] No existing session — showing onboarding")
            currentUser = nil
        }
        isAuthReady = true
    }

    /// Signs in with an Apple identity token. Nonce must be the raw (unhashed) value
    /// used to generate the SHA-256 hash passed to Apple's authorization request.
    func signInWithApple(idToken: String, nonce: String) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentUser = session.user
        print("[Auth] Apple sign-in succeeded: \(session.user.id)")
    }

    /// Signs the current user out and clears local session state.
    func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
        print("[Auth] Signed out")
    }

    /// Deletes all user data and signs out. Full auth.users deletion requires a
    /// server-side edge function — TODO: wire up when edge functions are deployed.
    func deleteAccount() async throws {
        guard let userID = currentUser?.id else { return }

        // Delete sift schema data
        try await client.from("gem_themes")
            .delete()
            .in("gem_id", values: gemIDsForUser(userID))
            .execute()
        let schemas: [String] = ["gems", "entries", "themes", "habits", "habit_logs", "action_items", "action_themes"]
        for table in schemas {
            try? await client.from(table)
                .delete()
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
        try? await client.schema("public").from("user_settings")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .execute()

        try await client.auth.signOut()
        currentUser = nil
        print("[Auth] Account deleted for \(userID)")
    }

    // MARK: - Quick Create (compose menu)

    /// Gets today's entry or silently creates one if none exists yet.
    private func getOrCreateTodayEntry(userID: UUID) async throws -> Entry {
        if let existing = try await fetchTodayEntry() { return existing }
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let entry = Entry(
            id: UUID(),
            userID: userID,
            gratitudeContent: "",
            content: "",
            createdAt: now,
            expiresAt: expiry,
            hasGem: false
        )
        try await client.from("entries").insert(entry).execute()
        return entry
    }

    /// Creates a new empty gem attached to today's entry (creating the entry if needed),
    /// appends a `> ` marker to the entry body, and returns the new gem's ID.
    func createQuickGem() async throws -> UUID {
        guard let userID = currentUser?.id else { throw QuickCreateError.notAuthenticated }

        let entry = try await getOrCreateTodayEntry(userID: userID)
        let gemID = UUID()

        let insert = QuickGemInsert(
            id: gemID, userID: userID, entryID: entry.id,
            content: "", rangeStart: 0, rangeEnd: 0
        )
        try await client.from("gems").insert(insert).execute()

        let separator = entry.content.isEmpty ? "" : "\n"
        let newContent = entry.content + separator + "> "
        try? await client.from("entries")
            .update(EntryContentFieldOnlyUpdate(content: newContent))
            .eq("id", value: entry.id.uuidString)
            .execute()
        try? await client.from("entries")
            .update(SupabaseEntryHasGemUpdate(hasGem: true))
            .eq("id", value: entry.id.uuidString)
            .execute()

        return gemID
    }

    /// Inserts an action item with the given content and appends a task line to today's entry body.
    func createQuickAction(content: String) async throws {
        guard let userID = currentUser?.id else { throw QuickCreateError.notAuthenticated }
        guard let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date()) else { return }

        let todayEntry = try? await fetchTodayEntry()
        let item = ActionItem(
            id: UUID(),
            userID: userID,
            entryID: todayEntry?.id,
            content: content,
            completed: false,
            rangeStart: nil,
            rangeEnd: nil,
            createdAt: Date(),
            carriedForward: false,
            expiresAt: expiresAt
        )
        try await client.from("action_items").insert(item).execute()

        if let entry = todayEntry {
            let separator = entry.content.isEmpty ? "" : "\n"
            let newContent = entry.content + separator + "- [ ] \(content)"
            try? await client.from("entries")
                .update(EntryContentFieldOnlyUpdate(content: newContent))
                .eq("id", value: entry.id.uuidString)
                .execute()
        }
    }

    private func gemIDsForUser(_ userID: UUID) async -> [String] {
        let gems: [SupabaseIDOnlyRow] = (try? await client
            .from("gems")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value) ?? []
        return gems.map(\.id.uuidString)
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

    /// Deletes entries older than 7 days that have no gem flagged. Safe to call on every launch —
    /// entries with `has_gem = true` are never touched, preserving gem references.
    func purgeExpiredEntries() async {
        guard let userID = currentUser?.id else { return }
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        do {
            try await client
                .from("entries")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("has_gem", value: false)
                .lt("expires_at", value: now)
                .execute()
        } catch {
            print("[SupabaseService] purgeExpiredEntries failed: \(error)")
        }
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

    /// True if the user has at least one active theme created more than `olderThan` seconds ago.
    func hasActiveThemeOlderThan(_ interval: TimeInterval) async -> Bool {
        guard let userID = currentUser?.id else { return false }
        let cutoff = Date().addingTimeInterval(-interval)
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows: [SupabaseIDOnlyRow] = (try? await client
            .from("themes")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .lt("created_at", value: formatter.string(from: cutoff))
            .limit(1)
            .execute()
            .value) ?? []
        return !rows.isEmpty
    }

    /// True if the user has at least one active habit created more than `olderThan` seconds ago.
    func hasActiveHabitOlderThan(_ interval: TimeInterval) async -> Bool {
        guard let userID = currentUser?.id else { return false }
        let cutoff = Date().addingTimeInterval(-interval)
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows: [SupabaseIDOnlyRow] = (try? await client
            .from("habits")
            .select("id")
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .lt("created_at", value: formatter.string(from: cutoff))
            .limit(1)
            .execute()
            .value) ?? []
        return !rows.isEmpty
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

private struct SupabaseIDOnlyRow: Decodable, Sendable {
    let id: UUID
}

private struct QuickGemInsert: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let entryID: UUID
    let content: String
    let rangeStart: Int
    let rangeEnd: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }
}

enum QuickCreateError: Error {
    case notAuthenticated
}
