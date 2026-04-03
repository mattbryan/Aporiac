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

    private var summaryCacheFingerprint: String?
    private var summaryCacheText: String?

    private var service: SupabaseService { .shared }

    /// Refreshes from Supabase and, when there is body text, requests or reuses a brief AI label.
    func refreshEntryCard() async {
        guard service.currentUser != nil else {
            entryCardState = .startPrompt
            summaryCacheFingerprint = nil
            summaryCacheText = nil
            return
        }

        do {
            guard let entry = try await service.fetchTodayEntry() else {
                entryCardState = .startPrompt
                summaryCacheFingerprint = nil
                summaryCacheText = nil
                return
            }

            let combined = entry.gratitudeContent + "\n" + entry.content
            if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entryCardState = .startPrompt
                summaryCacheFingerprint = nil
                summaryCacheText = nil
                return
            }

            let fingerprint = entry.id.uuidString + "|" + combined
            if fingerprint == summaryCacheFingerprint, let cached = summaryCacheText {
                entryCardState = .brief(cached)
                return
            }

            entryCardState = .loadingBrief
            let summary = await AIService.shared.entryCardBriefSummary(
                gratitude: entry.gratitudeContent,
                mindDump: entry.content
            )

            if let summary, !summary.isEmpty {
                summaryCacheFingerprint = fingerprint
                summaryCacheText = summary
                entryCardState = .brief(summary)
            } else {
                entryCardState = .brief(fallbackLabel(from: entry))
            }
        } catch {
            print("[Home] refreshEntryCard failed: \(error)")
            entryCardState = .startPrompt
        }
    }

    private func fallbackLabel(from entry: Entry) -> String {
        let blob = (entry.gratitudeContent + " " + entry.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = blob.split(whereSeparator: \.isNewline).map(String.init).first, !first.isEmpty {
            let capped = first.count > 48 ? String(first.prefix(45)) + "…" : first
            return capped
        }
        return "Today's entry"
    }
}
