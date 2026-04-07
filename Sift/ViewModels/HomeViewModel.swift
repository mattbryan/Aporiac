import Foundation

/// What the Today tab entry card shows before opening the editor.
enum HomeEntryCardState: Equatable {
    case startPrompt
    case loadingBrief
    case brief(String)
}

/// Drives the Today tab entry card: load today's row, optional Haiku micro-label when there is written content.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var entryCardState: HomeEntryCardState = .startPrompt
    /// Set when the card reflects a loaded `Entry` row (latest for the day being refreshed).
    private(set) var displayedEntryID: UUID?

    private static let fingerprintKey = "sift.summaryCache.fingerprint"
    private static let textKey = "sift.summaryCache.text"

    private var summaryCacheFingerprint: String? {
        get { UserDefaults.standard.string(forKey: Self.fingerprintKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.fingerprintKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.fingerprintKey)
            }
        }
    }

    private var summaryCacheText: String? {
        get { UserDefaults.standard.string(forKey: Self.textKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.textKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.textKey)
            }
        }
    }

    private var service: SupabaseService { .shared }

    /// Refreshes from Supabase and, when there is body text, requests or reuses a brief AI label.
    func refreshEntryCard() async {
        let day = Calendar.current.startOfDay(for: Date())
        await refreshEntryCard(for: day)
    }

    /// Refreshes the entry card for a specific local calendar day (latest entry that day).
    func refreshEntryCard(for calendarDay: Date) async {
        guard service.currentUser != nil else {
            entryCardState = .startPrompt
            displayedEntryID = nil
            return
        }

        let dayStart = Calendar.current.startOfDay(for: calendarDay)

        do {
            guard let entry = try await service.fetchEntry(on: dayStart) else {
                entryCardState = .startPrompt
                displayedEntryID = nil
                return
            }

            displayedEntryID = entry.id

            let combined = entry.gratitudeContent + "\n" + entry.content
            if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entryCardState = .startPrompt
                displayedEntryID = nil
                return
            }

            let fingerprint = entry.id.uuidString + "|" + combined
            if fingerprint == summaryCacheFingerprint, let cached = summaryCacheText {
                entryCardState = .brief(cached)
                return
            }

            let sameEntryAsCache = summaryCacheFingerprint?.hasPrefix(entry.id.uuidString + "|") == true
            if sameEntryAsCache, let stale = summaryCacheText {
                entryCardState = .brief(stale)
            } else {
                entryCardState = .loadingBrief
            }
            let summary = await AIService.shared.entryCardBriefSummary(
                gratitude: entry.gratitudeContent,
                mindDump: entry.content
            )

            if let summary, !summary.isEmpty {
                summaryCacheFingerprint = fingerprint
                summaryCacheText = summary
                entryCardState = .brief(summary)
            } else {
                entryCardState = .brief(fallbackLabel(from: entry, dayStart: dayStart))
            }
        } catch {
            print("[Home] refreshEntryCard failed: \(error)")
            entryCardState = .startPrompt
            displayedEntryID = nil
        }
    }

    private func fallbackLabel(from entry: Entry, dayStart: Date) -> String {
        let blob = (entry.gratitudeContent + " " + entry.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = blob.split(whereSeparator: \.isNewline).map(String.init).first, !first.isEmpty {
            let capped = first.count > 48 ? String(first.prefix(45)) + "…" : first
            return capped
        }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.isDate(dayStart, inSameDayAs: today) ? "Today's entry" : "Entry"
    }
}
