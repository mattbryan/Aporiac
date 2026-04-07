import Foundation

/// Manages the state and actions for the entry writing experience.
@MainActor
@Observable
final class EntryViewModel {
    var gratitudeText: String = ""
    var contentText: String = ""

    private(set) var currentEntry: Entry?
    /// `true` while the primary entry payload (text) for the current destination is loading.
    private(set) var isEntryContentLoading = true
    private(set) var dailyPrompt: String = "What's on your mind?"
    private(set) var gemViewModel = GemViewModel()

    var reviewPrompt: String? = nil

    /// Theme IDs selected on the pre-entry screen; passed into the daily prompt when starting the writing phase.
    var selectedThemeIDs: Set<UUID> = []

    var activeThemes: [Theme] {
        gemViewModel.allThemes
    }

    func toggleTheme(_ id: UUID) {
        var next = selectedThemeIDs
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        selectedThemeIDs = next
    }

    private var selectedThemeTitles: [String] {
        activeThemes
            .filter { selectedThemeIDs.contains($0.id) }
            .map(\.title)
    }

    private static let promptCacheDateKey = "sift.dailyPrompt.date"
    private static let promptCacheTextKey = "sift.dailyPrompt.text"

    /// Fetches the contextual daily prompt (with selected focus themes) before revealing the main writing surface.
    func prepareWritingPhase() async {
        let today = Calendar.current.startOfDay(for: Date())
        if let cachedDateInterval = UserDefaults.standard.object(forKey: Self.promptCacheDateKey) as? Double,
           let cachedText = UserDefaults.standard.string(forKey: Self.promptCacheTextKey) {
            let cachedDate = Date(timeIntervalSince1970: cachedDateInterval)
            if Calendar.current.isDate(cachedDate, inSameDayAs: today) {
                dailyPrompt = cachedText
                return
            }
        }

        let raw = UserDefaults.standard.string(forKey: "selectedPhilosophies") ?? "stoicism"
        let selected = Set(raw.split(separator: ",").compactMap { Philosophy(rawValue: String($0)) })
        let philosophy = Philosophy.todaysPhilosophy(from: selected)
        let prompt = await AIService.shared.dailyPrompt(themes: selectedThemeTitles, philosophy: philosophy)
        dailyPrompt = prompt

        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: Self.promptCacheDateKey)
        UserDefaults.standard.set(prompt, forKey: Self.promptCacheTextKey)
    }

    private var saveTask: Task<Void, Never>?
    private var service: SupabaseService { .shared }
    /// When true, `scheduleAutosave()` is a no-op (e.g. `contentText` patched to match Supabase after a Home toggle).
    private var suppressScheduleAutosaveForRemoteActionPatch = false

    /// Strips `> ` from the line containing the selection; next save sync removes the gem row.
    func removeGemAtSelection(_ selectionRange: NSRange) {
        let ns = contentText as NSString
        guard selectionRange.location < ns.length else { return }
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                        for: NSRange(location: selectionRange.location, length: 0))
        let lineContents = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        guard lineContents.hasPrefix("> ") else { return }

        let mutable = NSMutableString(string: contentText)
        let prefixRange = NSRange(location: lineStart, length: 2)
        mutable.replaceCharacters(in: prefixRange, with: "")
        contentText = mutable as String
        scheduleAutosave()
    }

    // MARK: Markdown entity sync (post-save)

    /// v1: Gem rows are keyed by content string. Editing `> old` to `> new` deletes the old row and inserts a new id — theme links on the old row are lost.
    private func syncMarkdownEntities() async {
        guard let entry = currentEntry, let userID = service.currentUser?.id else { return }
        let parsed = EntryParser.parse(contentText)
        await syncGems(parsed.gems, entry: entry, userID: userID)
        await syncActions(parsed.actions, entry: entry, userID: userID)
        await updateHasGem(hasGem: !parsed.gems.isEmpty, entry: entry)
    }

    private func syncGems(_ parsedGems: [ParsedGem], entry: Entry, userID: UUID) async {
        do {
            let existing: [Gem] = try await service.client
                .from("gems")
                .select()
                .eq("entry_id", value: entry.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let existingContents = Set(existing.map(\.content))
            let parsedContents = Set(parsedGems.map(\.content))

            let toDelete = existing.filter { !parsedContents.contains($0.content) }
            for gem in toDelete {
                do {
                    try await service.client
                        .from("gems")
                        .delete()
                        .eq("id", value: gem.id.uuidString)
                        .execute()
                } catch {
                    print("[Entry] syncGems delete failed: \(error)")
                }
            }

            let toInsert = parsedGems.filter { !existingContents.contains($0.content) }
            for parsedGem in toInsert {
                let gemID = UUID()
                let (rangeStart, rangeEnd) = utf16LineRange(lineIndex: parsedGem.lineIndex, in: contentText)
                let insert = GemInsert(
                    id: gemID,
                    userID: userID,
                    entryID: entry.id,
                    content: parsedGem.content,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd
                )
                do {
                    try await service.client
                        .from("gems")
                        .insert(insert)
                        .execute()
                    await linkNewGemToEntryThemes(gemID: gemID)
                } catch {
                    print("[Entry] syncGems insert failed: \(error)")
                }
            }

            try? await gemViewModel.load()
        } catch {
            print("[Entry] syncGems failed: \(error)")
        }
    }

    /// UTF-16 offsets of the gem line within `contentText` (matches legacy `range_start` / `range_end` expectations).
    private func utf16LineRange(lineIndex: Int, in text: String) -> (start: Int, end: Int) {
        let ns = text as NSString
        guard ns.length > 0, lineIndex >= 0 else { return (0, 0) }
        var lineNumber = 0
        var location = 0
        while location <= ns.length {
            let probe = min(location, max(0, ns.length - 1))
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: probe, length: 0))
            if lineNumber == lineIndex {
                return (lineStart, contentsEnd)
            }
            lineNumber += 1
            if lineEnd >= ns.length { break }
            location = lineEnd
        }
        return (0, 0)
    }

    /// Links a newly synced gem to **Today's Focus** themes (`selectedThemeIDs`) — no modal; user opts in via entry chips.
    private func linkNewGemToEntryThemes(gemID: UUID) async {
        guard !selectedThemeIDs.isEmpty else { return }
        for themeID in selectedThemeIDs {
            do {
                try await service.client
                    .from("gem_themes")
                    .insert(GemThemeLinkInsert(gemID: gemID, themeID: themeID))
                    .execute()
            } catch {
                // Duplicate (unique constraint) or RLS — non-fatal.
                print("[Entry] gem_themes link skipped for gem \(gemID) theme \(themeID): \(error)")
            }
        }
    }

    private func syncActions(_ parsedActions: [ParsedAction], entry: Entry, userID: UUID) async {
        do {
            let existing: [ActionItem] = try await service.client
                .from("action_items")
                .select()
                .eq("entry_id", value: entry.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let existingByContent = existing.reduce(into: [String: ActionItem]()) { $0[$1.content] = $1 }
            let parsedByContent = parsedActions.reduce(into: [String: ParsedAction]()) { $0[$1.content] = $1 }

            let toDelete = existing.filter { parsedByContent[$0.content] == nil }
            for action in toDelete {
                do {
                    try await service.client
                        .from("action_items")
                        .delete()
                        .eq("id", value: action.id.uuidString)
                        .execute()
                } catch {
                    print("[Entry] syncActions delete failed: \(error)")
                }
            }

            let toInsert = parsedActions.filter { existingByContent[$0.content] == nil }
            let now = Date()
            let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
            for parsedAction in toInsert {
                let insert = ActionItemInsert(
                    id: UUID(),
                    userID: userID,
                    entryID: entry.id,
                    content: parsedAction.content,
                    completed: parsedAction.completed,
                    createdAt: now,
                    expiresAt: expiresAt
                )
                do {
                    try await service.client
                        .from("action_items")
                        .insert(insert)
                        .execute()
                } catch {
                    print("[Entry] syncActions insert failed: \(error)")
                }
            }

            for parsedAction in parsedActions {
                guard let existingRow = existingByContent[parsedAction.content],
                      existingRow.completed != parsedAction.completed else { continue }
                let completedAt: Date? = parsedAction.completed ? Date() : nil
                do {
                    try await service.client
                        .from("action_items")
                        .update(ActionCompletionUpdate(completed: parsedAction.completed, completedAt: completedAt))
                        .eq("id", value: existingRow.id.uuidString)
                        .execute()
                } catch {
                    print("[Entry] syncActions completion update failed: \(error)")
                }
            }
        } catch {
            print("[Entry] syncActions failed: \(error)")
        }
    }

    private func updateHasGem(hasGem: Bool, entry: Entry) async {
        guard entry.hasGem != hasGem else { return }
        do {
            try await service.client
                .from("entries")
                .update(HasGemUpdate(hasGem: hasGem))
                .eq("id", value: entry.id.uuidString)
                .execute()
            if var updated = currentEntry {
                updated.hasGem = hasGem
                currentEntry = updated
            }
        } catch {
            print("[Entry] updateHasGem failed: \(error)")
        }
    }

    // MARK: Load / Create

    /// Loads today's entry from Supabase, creating one if none exists yet.
    func loadOrCreateTodayEntry() async {
        isEntryContentLoading = true
        defer { isEntryContentLoading = false }

        guard let userID = service.currentUser?.id else {
            #if DEBUG
            print("[Entry] No current user — skipping load")
            #endif
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        let formatter = ISO8601DateFormatter()

        #if DEBUG
        print("[Entry] Loading for user \(userID)")
        print("[Entry] Querying entries between \(formatter.string(from: today)) and \(formatter.string(from: tomorrow))")
        #endif

        do {
            let entries: [Entry] = try await service.client
                .from("entries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .gte("created_at", value: formatter.string(from: today))
                .lt("created_at", value: formatter.string(from: tomorrow))
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            #if DEBUG
            print("[Entry] Found \(entries.count) existing entries")
            #endif
            if let entry = entries.first {
                currentEntry = entry
                gratitudeText = entry.gratitudeContent
                contentText = entry.content
                Task { try? await gemViewModel.load() }
            } else {
                #if DEBUG
                print("[Entry] No entry today — creating")
                #endif
                try await createEntry(userID: userID)
                Task { try? await gemViewModel.load() }
            }

            if let prompt = reviewPrompt, contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentText = prompt
            }
        } catch {
            print("[Entry] Failed to load: \(error)")
        }
    }

    /// Loads a specific entry by ID. Does not create a new entry.
    func loadEntry(id: UUID) async {
        isEntryContentLoading = true
        defer { isEntryContentLoading = false }

        guard let userID = service.currentUser?.id else { return }
        do {
            let entries: [Entry] = try await service.client
                .from("entries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value

            guard let entry = entries.first else { return }
            currentEntry = entry
            gratitudeText = entry.gratitudeContent
            contentText = entry.content
            Task { try? await gemViewModel.load() }
        } catch {
            print("[Entry] Failed to load entry \(id): \(error)")
        }
    }

    private func createEntry(userID: UUID) async throws {
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
        #if DEBUG
        print("[Entry] Inserting entry \(entry.id)")
        #endif
        try await service.client
            .from("entries")
            .insert(entry)
            .execute()
        #if DEBUG
        print("[Entry] Insert succeeded")
        #endif
        currentEntry = entry
    }

    // MARK: Autosave

    /// Updates the in-memory `contentText` to reflect a completion toggle that happened outside the entry.
    /// This keeps the open editor current without scheduling an autosave (Supabase already matches).
    func applyActionCompletionUpdate(content: String, completed: Bool) {
        guard let next = EntryMarkdownActionSync.setTaskCompletion(
            in: contentText,
            taskBody: content,
            completed: completed
        ), next != contentText else { return }

        suppressScheduleAutosaveForRemoteActionPatch = true
        contentText = next
        suppressScheduleAutosaveForRemoteActionPatch = false
    }

    /// Call this whenever text changes — saves after a short debounce.
    func scheduleAutosave() {
        if suppressScheduleAutosaveForRemoteActionPatch { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// Cancels any pending debounce and saves immediately. Call on dismiss.
    func saveNow() async {
        saveTask?.cancel()
        await save()
    }

    /// Reloads the journal body from Supabase when Today updates markdown (e.g. completing a task on the day view).
    func reloadCurrentEntryBodyFromServerIfNeeded(entryID: UUID) async {
        guard currentEntry?.id == entryID, let userID = service.currentUser?.id else { return }
        saveTask?.cancel()
        do {
            let rows: [Entry] = try await service.client
                .from("entries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("id", value: entryID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            gratitudeText = row.gratitudeContent
            contentText = row.content
            currentEntry = row
        } catch {
            print("[Entry] reloadCurrentEntryBodyFromServerIfNeeded failed: \(error)")
        }
    }

    private func save() async {
        guard let entry = currentEntry else {
            #if DEBUG
            print("[Entry] Save skipped — no currentEntry")
            #endif
            return
        }
        #if DEBUG
        print("[Entry] Saving entry \(entry.id)")
        #endif
        do {
            try await service.client
                .from("entries")
                .update(EntryContentUpdate(
                    gratitudeContent: gratitudeText,
                    content: contentText
                ))
                .eq("id", value: entry.id.uuidString)
                .execute()
            #if DEBUG
            print("[Entry] Save succeeded")
            #endif
            await syncMarkdownEntities()
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
        } catch {
            print("[Entry] Save failed: \(error)")
        }
    }
}

extension Notification.Name {
    /// Posted after a successful entry save and markdown entity sync so Gems / Today can refresh lists.
    static let siftJournalEntitiesDidSync = Notification.Name("siftJournalEntitiesDidSync")
    /// Posted when Today toggles a task tied to an entry; `object` is the entry `UUID`.
    static let siftEntryBodyUpdatedFromDayView = Notification.Name("siftEntryBodyUpdatedFromDayView")
    /// Posted when Home toggles an action; `userInfo`: `actionContent`, `completed`, `entryID` (optional `UUID`).
    static let siftActionCompletionChanged = Notification.Name("com.aporian.sift.actionCompletionChanged")
    /// Posted by the compose menu to ask ThemesView to open its create sheet.
    static let siftRequestShowCreateTheme = Notification.Name("siftRequestShowCreateTheme")
    /// Posted by the compose menu to ask HabitsView to open its create sheet.
    static let siftRequestShowCreateHabit = Notification.Name("siftRequestShowCreateHabit")
    /// Posted by the compose menu to ask HomeView to create a new inline action.
    static let siftRequestCreateAction = Notification.Name("siftRequestCreateAction")
}

// MARK: - Update DTOs

private struct EntryContentUpdate: Encodable {
    let gratitudeContent: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case gratitudeContent = "gratitude_content"
        case content
    }
}

private struct HasGemUpdate: Encodable {
    let hasGem: Bool

    enum CodingKeys: String, CodingKey {
        case hasGem = "has_gem"
    }
}

private struct GemInsert: Encodable {
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

private struct GemThemeLinkInsert: Encodable {
    let gemID: UUID
    let themeID: UUID

    enum CodingKeys: String, CodingKey {
        case gemID = "gem_id"
        case themeID = "theme_id"
    }
}

private struct ActionItemInsert: Encodable {
    let id: UUID
    let userID: UUID
    let entryID: UUID
    let content: String
    let completed: Bool
    let carriedForward: Bool = false
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case completed
        case carriedForward = "carried_forward"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private struct ActionCompletionUpdate: Encodable {
    let completed: Bool
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completed
        case completedAt = "completed_at"
    }
}
