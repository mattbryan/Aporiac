import Foundation

enum PersistedEntryBlockType: String, Codable, Sendable {
    case paragraph
    case heading1
    case heading2
    case gem
    case action
}

struct PersistedEntryBlock: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var type: PersistedEntryBlockType
    var text: String
    var checked: Bool?

    init(id: UUID = UUID(), type: PersistedEntryBlockType, text: String, checked: Bool? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.checked = checked
    }
}

enum EntryMarkdownBlockCodec {
    static func blocks(from markdown: String) -> [PersistedEntryBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [PersistedEntryBlock] = []
        var paragraphLines: [String] = []
        var lineIndex = 0

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !paragraph.isEmpty {
                blocks.append(PersistedEntryBlock(type: .paragraph, text: paragraph))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !paragraphLines.isEmpty, paragraphLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == false {
                    paragraphLines.append("")
                } else {
                    flushParagraph()
                }
                lineIndex += 1
                continue
            }

            if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(PersistedEntryBlock(type: .heading2, text: String(line.dropFirst(3))))
                lineIndex += 1
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(PersistedEntryBlock(type: .heading1, text: String(line.dropFirst(2))))
                lineIndex += 1
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                var gemLines = [String(line.dropFirst(2))]
                var blankRun = 0
                lineIndex += 1
                while lineIndex < lines.count {
                    let next = lines[lineIndex]
                    if isBlockStarter(next) {
                        break
                    }
                    if next.trimmingCharacters(in: .whitespaces).isEmpty {
                        blankRun += 1
                        if blankRun >= 2 {
                            break
                        }
                    } else {
                        blankRun = 0
                    }
                    gemLines.append(next)
                    lineIndex += 1
                }
                let gemText = gemLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(PersistedEntryBlock(type: .gem, text: gemText))
                continue
            }

            if line.hasPrefix("- [x] ") || line.hasPrefix("* [x] ") {
                flushParagraph()
                blocks.append(PersistedEntryBlock(type: .action, text: String(line.dropFirst(6)), checked: true))
                lineIndex += 1
                continue
            }

            if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                flushParagraph()
                blocks.append(PersistedEntryBlock(type: .action, text: String(line.dropFirst(6)), checked: false))
                lineIndex += 1
                continue
            }

            paragraphLines.append(line)
            lineIndex += 1
        }

        flushParagraph()
        return blocks
    }

    static func markdown(from blocks: [PersistedEntryBlock]) -> String {
        blocks
            .filter { !$0.text.isEmpty }
            .map { block in
                switch block.type {
                case .paragraph:
                    return block.text
                case .heading1:
                    return "# " + block.text
                case .heading2:
                    return "## " + block.text
                case .gem:
                    let lines = block.text.components(separatedBy: "\n")
                    guard let first = lines.first else { return "" }
                    if lines.count == 1 {
                        return "> " + first
                    }
                    return (["> " + first] + Array(lines.dropFirst())).joined(separator: "\n")
                case .action:
                    let prefix = (block.checked ?? false) ? "- [x] " : "- [ ] "
                    return prefix + block.text
                }
            }
            .joined(separator: "\n\n")
    }

    private static func isBlockStarter(_ line: String) -> Bool {
        line.hasPrefix("> ")
            || line.hasPrefix("# ")
            || line.hasPrefix("## ")
            || line.hasPrefix("- [ ] ")
            || line.hasPrefix("- [x] ")
            || line.hasPrefix("* [ ] ")
            || line.hasPrefix("* [x] ")
    }
}
