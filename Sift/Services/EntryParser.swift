import Foundation

internal struct ParsedGem: Equatable, Sendable {
    let content: String // text with `> ` stripped
    let startLineIndex: Int // 0-indexed line number where the gem block begins
    let endLineIndex: Int // 0-indexed line number where the gem block ends
}

internal struct ParsedAction: Equatable, Sendable {
    let content: String // text with prefix stripped
    let completed: Bool
    let lineIndex: Int
}

internal struct ParsedEntry: Sendable {
    let gems: [ParsedGem]
    let actions: [ParsedAction]
}

internal enum EntryParser {

    static func parse(_ text: String) -> ParsedEntry {
        var gems: [ParsedGem] = []
        var actions: [ParsedAction] = []

        let lines = text.components(separatedBy: "\n")
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            if line.hasPrefix("> ") {
                let startLineIndex = lineIndex
                var gemLines: [String] = []

                while lineIndex < lines.count, lines[lineIndex].hasPrefix("> ") {
                    gemLines.append(String(lines[lineIndex].dropFirst(2)))
                    lineIndex += 1
                }

                let content = gemLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }
                gems.append(
                    ParsedGem(
                        content: content,
                        startLineIndex: startLineIndex,
                        endLineIndex: lineIndex - 1
                    )
                )
                continue

            // GFM `- [ ]` / `- [x]` (used by `MarkdownTextEditor` toolbar) and legacy `*` task markers — all use 6-char prefixes before the body.
            } else if line.hasPrefix("* [x] ") || line.hasPrefix("- [x] ") {
                let content = String(line.dropFirst(6))
                    .trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                actions.append(ParsedAction(content: content, completed: true, lineIndex: lineIndex))

            } else if line.hasPrefix("* [ ] ") || line.hasPrefix("- [ ] ") {
                let content = String(line.dropFirst(6))
                    .trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                actions.append(ParsedAction(content: content, completed: false, lineIndex: lineIndex))
            }

            lineIndex += 1
        }

        return ParsedEntry(gems: gems, actions: actions)
    }
}

// MARK: - Day view ↔ entry markdown (checkbox lines)

internal enum EntryMarkdownActionSync {

    /// Rewrites the first matching task line (`- [ ]` / `- [x]` / `* [ ]` / `* [x]`) whose trimmed body equals `taskBody`.
    /// Returns `nil` if no line matched.
    static func setTaskCompletion(in fullText: String, taskBody: String, completed: Bool) -> String? {
        let target = taskBody.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }

        let lines = fullText.components(separatedBy: "\n")
        var found = false
        let next = lines.map { line -> String in
            guard !found, let parsed = parseChecklistLine(line) else { return line }
            let body = parsed.bodyTrimmed
            guard body == target else { return line }
            found = true
            return renderChecklistLine(hyphen: parsed.hyphen, completed: completed, body: body)
        }
        return found ? next.joined(separator: "\n") : nil
    }

    private struct ParsedChecklistLine {
        let hyphen: Bool
        let bodyTrimmed: String
    }

    private static func parseChecklistLine(_ line: String) -> ParsedChecklistLine? {
        let pairs: [(prefix: String, hyphen: Bool)] = [
            ("- [x] ", true),
            ("- [ ] ", true),
            ("* [x] ", false),
            ("* [ ] ", false),
        ]
        for pair in pairs where line.hasPrefix(pair.prefix) {
            let rest = String(line.dropFirst(pair.prefix.count))
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return ParsedChecklistLine(hyphen: pair.hyphen, bodyTrimmed: trimmed)
        }
        return nil
    }

    private static func renderChecklistLine(hyphen: Bool, completed: Bool, body: String) -> String {
        let bullet = hyphen ? "- " : "* "
        let mark = completed ? "[x] " : "[ ] "
        return bullet + mark + body
    }
}
