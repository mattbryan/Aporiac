import Foundation

/// Manages the state and actions for the entry writing experience.
@MainActor
@Observable
final class EntryViewModel {
    var gratitudeText: String = ""
    var contentText: String = ""
    var gratitudeHighlights: [TextHighlight] = []
    var contentHighlights: [TextHighlight] = []
    /// Action items marked complete that belong to the loaded entry (for the entry screen).
    private(set) var completedActionsForEntry: [ActionItem] = []

    private(set) var currentEntry: Entry?
    private(set) var dailyPrompt: String = "What's on your mind?"
    private(set) var gemViewModel = GemViewModel()

    var reviewPrompt: String? = nil

    var activeThemes: [Theme] {
        gemViewModel.allThemes
    }

    /// When non-nil, the theme-picker sheet should show for this newly saved gem.
    private(set) var pendingThemePickerGemID: UUID? = nil
    private var saveTask: Task<Void, Never>?
    private var service: SupabaseService { .shared }

    // MARK: Highlights

    func addHighlight(_ highlight: TextHighlight, section: EntrySection) {
        switch section {
        case .gratitude: gratitudeHighlights.append(highlight)
        case .content: contentHighlights.append(highlight)
        }
        Task { @MainActor in
            await persistHighlight(highlight, section: section)
        }
    }

    func dismissThemePicker() {
        pendingThemePickerGemID = nil
    }

    func associateTheme(themeID: UUID) async {
        guard let gemID = pendingThemePickerGemID else { return }
        pendingThemePickerGemID = nil
        do {
            try await gemViewModel.addTheme(themeID: themeID, toGemID: gemID)
        } catch {
            print("[Entry] Failed to associate theme: \(error)")
        }
    }

    private func persistHighlight(_ highlight: TextHighlight, section: EntrySection) async {
        guard let entry = currentEntry, let userID = service.currentUser?.id else {
            print("[Entry] persistHighlight skipped — missing entry or currentUser")
            return
        }

        let sourceText = section == .gratitude ? gratitudeText : contentText
        let nsSource = sourceText as NSString
        guard highlight.range.location >= 0,
              highlight.range.length > 0,
              NSMaxRange(highlight.range) <= nsSource.length else { return }

        let content = nsSource.substring(with: highlight.range)

        switch highlight.kind {
        case .gem:
            let offset = section == .content ? (gratitudeText as NSString).length + 1 : 0
            let rangeStart = highlight.range.location + offset
            let rangeEnd = rangeStart + highlight.range.length
            let insert = GemInsert(
                id: highlight.id,
                userID: userID,
                entryID: entry.id,
                content: content,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )
            do {
                try await service.client.from("gems").insert(insert).execute()
            } catch {
                print("[Entry] Failed to persist gem: \(error)")
                return
            }
            do {
                try await service.client
                    .from("entries")
                    .update(HasGemUpdate(hasGem: true))
                    .eq("id", value: entry.id.uuidString)
                    .execute()
                if var updated = currentEntry {
                    updated.hasGem = true
                    currentEntry = updated
                }
            } catch {
                print("[Entry] Failed to update entry has_gem: \(error)")
            }
            pendingThemePickerGemID = highlight.id
            Task {
                await generateAndStoreThread()
            }

        case .action:
            let offset = section == .content ? (gratitudeText as NSString).length + 1 : 0
            let rangeStart = highlight.range.location + offset
            let rangeEnd = rangeStart + highlight.range.length
            let withRanges = ActionItemInsert(
                id: highlight.id,
                userID: userID,
                entryID: entry.id,
                content: content,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )
            do {
                try await service.client.from("action_items").insert(withRanges).execute()
            } catch {
                let legacy = ActionItemInsertWithoutRanges(
                    id: highlight.id,
                    userID: userID,
                    entryID: entry.id,
                    content: content
                )
                do {
                    try await service.client.from("action_items").insert(legacy).execute()
                    print("[Entry] Action item saved without highlight ranges (add range_start/range_end in Supabase for persisted highlights).")
                } catch {
                    print("[Entry] Failed to persist action item: \(error)")
                }
            }
        }
    }

    private func generateAndStoreThread() async {
        guard let entry = currentEntry else { return }
        let entryID = entry.id

        let gems: [Gem]
        do {
            gems = try await service.client
                .from("gems")
                .select()
                .eq("entry_id", value: entryID.uuidString)
                .order("created_at")
                .execute()
                .value
        } catch {
            print("[Entry] Failed to fetch gems for thread: \(error)")
            return
        }

        guard gems.count >= 2 else { return }

        let contents = gems.map(\.content)
        guard let sentence = await AIService.shared.gemThread(gems: contents) else { return }
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await service.client
                .from("gems")
                .update(ThreadUpdate(thread: trimmed))
                .eq("entry_id", value: entryID.uuidString)
                .execute()
        } catch {
            print("[Entry] Failed to persist gem thread: \(error)")
        }
    }

    private func loadHighlights() async {
        guard let entry = currentEntry, let userID = service.currentUser?.id else { return }

        let gratLen = (gratitudeText as NSString).length
        let separator = 1

        gratitudeHighlights = []
        contentHighlights = []

        do {
            let gems: [Gem] = try await service.client
                .from("gems")
                .select()
                .eq("entry_id", value: entry.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            for gem in gems {
                mapCombinedRangeToSections(
                    id: gem.id,
                    rangeStart: gem.rangeStart,
                    rangeEnd: gem.rangeEnd,
                    gratLen: gratLen,
                    separator: separator,
                    kind: .gem
                )
            }
        } catch {
            print("[Entry] Failed to load gems: \(error)")
        }

        do {
            let entryActions: [ActionItem] = try await service.client
                .from("action_items")
                .select()
                .eq("entry_id", value: entry.id.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            completedActionsForEntry = entryActions
                .filter(\.completed)
                .sorted { $0.createdAt < $1.createdAt }

            for action in entryActions {
                guard let rs = action.rangeStart, let re = action.rangeEnd, re > rs else { continue }
                mapCombinedRangeToSections(
                    id: action.id,
                    rangeStart: rs,
                    rangeEnd: re,
                    gratLen: gratLen,
                    separator: separator,
                    kind: .action
                )
            }
        } catch {
            print("[Entry] Failed to load action items for entry: \(error)")
            completedActionsForEntry = []
        }
    }

    private func mapCombinedRangeToSections(
        id: UUID,
        rangeStart: Int,
        rangeEnd: Int,
        gratLen: Int,
        separator: Int,
        kind: TextHighlight.Kind
    ) {
        if rangeEnd <= gratLen {
            let range = NSRange(location: rangeStart, length: rangeEnd - rangeStart)
            let highlight = TextHighlight(id: id, range: range, kind: kind)
            gratitudeHighlights.append(highlight)
        } else if rangeStart >= gratLen + separator {
            let offset = gratLen + separator
            let loc = rangeStart - offset
            let len = rangeEnd - rangeStart
            if loc >= 0 && len > 0 {
                contentHighlights.append(TextHighlight(id: id, range: NSRange(location: loc, length: len), kind: kind))
            }
        }
    }

    // MARK: Load / Create

    /// Loads today's entry from Supabase, creating one if none exists yet.
    func loadOrCreateTodayEntry() async {
        guard let userID = service.currentUser?.id else {
            print("[Entry] No current user — skipping load")
            return
        }
        print("[Entry] Loading for user \(userID)")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        let formatter = ISO8601DateFormatter()
        print("[Entry] Querying entries between \(formatter.string(from: today)) and \(formatter.string(from: tomorrow))")

        do {
            let entries: [Entry] = try await service.client
                .from("entries")
                .select()
                .eq("user_id", value: userID.uuidString)
                .gte("created_at", value: formatter.string(from: today))
                .lt("created_at", value: formatter.string(from: tomorrow))
                .limit(1)
                .execute()
                .value

            print("[Entry] Found \(entries.count) existing entries")
            if let entry = entries.first {
                currentEntry = entry
                gratitudeText = entry.gratitudeContent
                contentText = entry.content
                await loadHighlights()
                Task { try? await gemViewModel.load() }
            } else {
                print("[Entry] No entry today — creating")
                try await createEntry(userID: userID)
                Task { try? await gemViewModel.load() }
            }

            if let prompt = reviewPrompt, contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentText = prompt
            }

            Task {
                dailyPrompt = await AIService.shared.dailyPrompt()
            }
        } catch {
            print("[Entry] Failed to load: \(error)")
        }
    }

    /// Loads a specific entry by ID. Does not create a new entry.
    func loadEntry(id: UUID) async {
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
            await loadHighlights()
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
        print("[Entry] Inserting entry \(entry.id)")
        try await service.client
            .from("entries")
            .insert(entry)
            .execute()
        print("[Entry] Insert succeeded")
        currentEntry = entry
        gratitudeHighlights = []
        contentHighlights = []
        completedActionsForEntry = []
    }

    // MARK: Autosave

    /// Call this whenever text changes — saves after a short debounce.
    func scheduleAutosave() {
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

    private func save() async {
        guard let entry = currentEntry else {
            print("[Entry] Save skipped — no currentEntry")
            return
        }
        print("[Entry] Saving entry \(entry.id)")
        do {
            try await service.client
                .from("entries")
                .update(EntryContentUpdate(
                    gratitudeContent: gratitudeText,
                    content: contentText
                ))
                .eq("id", value: entry.id.uuidString)
                .execute()
            print("[Entry] Save succeeded")
        } catch {
            print("[Entry] Save failed: \(error)")
        }
    }
}

// MARK: -

enum EntrySection: Sendable {
    case gratitude
    case content
}

private struct EntryContentUpdate: Encodable {
    let gratitudeContent: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case gratitudeContent = "gratitude_content"
        case content
    }
}

private struct ThreadUpdate: Encodable {
    let thread: String
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

private struct ActionItemInsert: Encodable {
    let id: UUID
    let userID: UUID
    let entryID: UUID
    let content: String
    let completed: Bool = false
    let rangeStart: Int
    let rangeEnd: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case completed
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }
}

/// Used when `action_items` has no `range_start` / `range_end` columns yet.
private struct ActionItemInsertWithoutRanges: Encodable {
    let id: UUID
    let userID: UUID
    let entryID: UUID
    let content: String
    let completed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case entryID = "entry_id"
        case content
        case completed
    }
}
