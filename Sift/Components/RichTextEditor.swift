import SwiftUI
import UIKit

// MARK: - TextHighlight

/// A ranged highlight applied to journal text — either a gem (kept) or an action item.
internal struct TextHighlight: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case gem
        case action
    }

    let id: UUID
    var range: NSRange
    var kind: Kind
}

// MARK: - HighlightTrigger

/// A reference type the parent view holds to imperatively trigger a highlight on a specific editor.
internal final class HighlightTrigger: @unchecked Sendable {
    fileprivate var apply: ((TextHighlight.Kind) -> Void)?

    func fire(_ kind: TextHighlight.Kind) {
        apply?(kind)
    }
}

// MARK: - RichTextListMode

internal enum RichTextListMode: Sendable {
    case none
    /// Inserts `• ` at the start of the first line and after each line break as the user writes.
    case bullet
}

// MARK: - RichTextEditor

internal struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var highlights: [TextHighlight]
    var placeholder: String
    var textColor: Color = .siftInk
    var listMode: RichTextListMode = .none
    var trigger: HighlightTrigger? = nil
    var onSelectionChanged: ((Bool) -> Void)? = nil
    var onHighlightAdded: (TextHighlight) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GrowingTextView {
        let textView = GrowingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
        textView.tintColor = UIColor(Color.siftGem)
        textView.font = RichTextEditor.baseFont
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.typingAttributes = RichTextEditor.baseTypingAttributes(textColor: UIColor(textColor))

        let placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = RichTextEditor.baseFont
        placeholderLabel.textColor = UIColor(Color.siftSubtle)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
        ])

        context.coordinator.textView = textView
        context.coordinator.placeholderLabel = placeholderLabel

        trigger?.apply = { [weak coordinator = context.coordinator] kind in
            coordinator?.applyHighlight(kind: kind)
        }

        context.coordinator.applyFullContent(text: text, highlights: highlights, textColor: UIColor(textColor))
        context.coordinator.syncState(text: text, highlights: highlights, textColor: UIColor(textColor))
        context.coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)

        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GrowingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 44))
    }

    func updateUIView(_ uiView: GrowingTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Re-register trigger in case the view was recreated
        trigger?.apply = { [weak coordinator] kind in
            coordinator?.applyHighlight(kind: kind)
        }

        let uiTextColor = UIColor(textColor)
        let tvText = uiView.text ?? ""

        // Placeholder only needs updating if the value changed
        if coordinator.lastPlaceholder != placeholder || coordinator.lastTextEmpty != text.isEmpty {
            coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)
            coordinator.lastPlaceholder = placeholder
            coordinator.lastTextEmpty = text.isEmpty
        }

        // Full content replace — only when text was externally changed (e.g. loaded from Supabase)
        if text != tvText {
            coordinator.applyFullContent(text: text, highlights: highlights, textColor: uiTextColor)
            coordinator.syncState(text: text, highlights: highlights, textColor: uiTextColor)
            uiView.typingAttributes = Self.baseTypingAttributes(textColor: uiTextColor)
            uiView.invalidateIntrinsicContentSize()
            return
        }

        // Visual-only pass — highlights or color changed, plain text is the same
        let newKey = Self.highlightsKey(highlights)
        let colorMatch = coordinator.lastSyncedTextColor.map { $0.isEqual(uiTextColor) } ?? false

        guard newKey != coordinator.lastHighlightsKey || !colorMatch else { return }

        coordinator.reapplyVisualAttributes(text: text, highlights: highlights, textColor: uiTextColor)
        coordinator.lastHighlightsKey = newKey
        coordinator.lastSyncedTextColor = uiTextColor
        uiView.typingAttributes = Self.baseTypingAttributes(textColor: uiTextColor)
        uiView.invalidateIntrinsicContentSize()
    }

    fileprivate static let baseFont: UIFont = UIFont.systemFont(ofSize: 17, weight: .regular)

    /// Plain-text bullet + space — stored verbatim so highlights and Supabase stay aligned with `String` offsets.
    fileprivate static let bulletPrefix = "• "

    fileprivate static func bulletizeMultilineInsertion(_ raw: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            if line.isEmpty { return line }
            if line.hasPrefix(bulletPrefix) { return line }
            return bulletPrefix + line
        }.joined(separator: "\n")
    }

    fileprivate static func baseTypingAttributes(textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key.font: baseFont,
            NSAttributedString.Key.foregroundColor: textColor,
        ]
    }

    fileprivate static func highlightsKey(_ items: [TextHighlight]) -> String {
        items
            .map { "\($0.id.uuidString)|\($0.range.location)|\($0.range.length)|\($0.kind.rawValue)" }
            .sorted()
            .joined(separator: "#")
    }

    fileprivate static func attributes(for kind: TextHighlight.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .gem:
            return [
                .foregroundColor: UIColor(Color.siftGem),
                .backgroundColor: UIColor(Color.siftGemBackground),
            ]
        case .action:
            return [
                .foregroundColor: UIColor(Color.siftAction),
                .backgroundColor: UIColor(Color.siftActionBackground),
            ]
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var parent: RichTextEditor
        fileprivate weak var textView: GrowingTextView?
        fileprivate weak var placeholderLabel: UILabel?

        fileprivate var lastHighlightsKey: String = ""
        fileprivate var lastSyncedPlainText: String = ""
        fileprivate var lastSyncedTextColor: UIColor?
        fileprivate var lastPlaceholder: String = ""
        fileprivate var lastTextEmpty: Bool = true
        fileprivate var lastHadSelection: Bool = false

        fileprivate init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        fileprivate func refreshPlaceholder(placeholder: String, isEmpty: Bool) {
            guard let label = placeholderLabel else { return }
            label.text = placeholder
            label.isHidden = !isEmpty
            if let tv = textView, tv.bounds.width > 0 {
                label.preferredMaxLayoutWidth = tv.bounds.width
            }
        }

        fileprivate func syncState(text: String, highlights: [TextHighlight], textColor: UIColor) {
            lastSyncedPlainText = text
            lastHighlightsKey = RichTextEditor.highlightsKey(highlights)
            lastSyncedTextColor = textColor
        }

        fileprivate func applyFullContent(text: String, highlights: [TextHighlight], textColor: UIColor) {
            guard let textView else { return }
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: RichTextEditor.baseFont,
                .foregroundColor: textColor,
            ]
            let storage = NSMutableAttributedString(string: text, attributes: baseAttrs)
            for highlight in highlights {
                let r = highlight.range
                guard r.location >= 0, r.length > 0, NSMaxRange(r) <= storage.length else { continue }
                var attrs = RichTextEditor.attributes(for: highlight.kind)
                attrs[.font] = RichTextEditor.baseFont
                storage.addAttributes(attrs, range: r)
            }
            textView.attributedText = storage
            textView.textColor = textColor
            textView.font = RichTextEditor.baseFont
        }

        fileprivate func reapplyVisualAttributes(text: String, highlights: [TextHighlight], textColor: UIColor) {
            guard let textView else { return }
            let storage = textView.textStorage
            let fullLen = storage.length
            guard fullLen == (text as NSString).length else {
                applyFullContent(text: text, highlights: highlights, textColor: textColor)
                return
            }

            let baseFont = RichTextEditor.baseFont
            let valid = highlights
                .filter { $0.range.location >= 0 && $0.range.length > 0 && NSMaxRange($0.range) <= fullLen }
                .sorted { $0.range.location < $1.range.location }

            storage.beginEditing()
            let fullRange = NSRange(location: 0, length: fullLen)
            storage.addAttribute(.font, value: baseFont, range: fullRange)
            storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            var cursor = 0
            for h in valid {
                let r = h.range
                if r.location > cursor {
                    let gap = NSRange(location: cursor, length: r.location - cursor)
                    storage.addAttribute(.foregroundColor, value: textColor, range: gap)
                    storage.removeAttribute(.backgroundColor, range: gap)
                }
                var attrs = RichTextEditor.attributes(for: h.kind)
                attrs[.font] = baseFont
                storage.addAttributes(attrs, range: r)
                cursor = NSMaxRange(r)
            }
            if cursor < fullLen {
                let tail = NSRange(location: cursor, length: fullLen - cursor)
                storage.addAttribute(.foregroundColor, value: textColor, range: tail)
                storage.removeAttribute(.backgroundColor, range: tail)
            }
            storage.endEditing()
            textView.textColor = textColor
            textView.font = baseFont
        }

        fileprivate func applyHighlight(kind: TextHighlight.Kind) {
            guard let textView else { return }
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            let len = (textView.text as NSString).length
            guard NSMaxRange(range) <= len else { return }

            var attrs = RichTextEditor.attributes(for: kind)
            attrs[.font] = RichTextEditor.baseFont
            let highlight = TextHighlight(id: UUID(), range: range, kind: kind)

            textView.textStorage.beginEditing()
            textView.textStorage.addAttributes(attrs, range: range)
            textView.textStorage.endEditing()

            parent.onHighlightAdded(highlight)
            textView.selectedTextRange = nil

            lastSyncedPlainText = textView.text ?? ""
            lastHighlightsKey = RichTextEditor.highlightsKey(parent.highlights)
            lastSyncedTextColor = UIColor(parent.textColor)
            textView.invalidateIntrinsicContentSize()

            parent.onSelectionChanged?(false)
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            let next = textView.text ?? ""
            parent.text = next
            lastSyncedPlainText = next
            let isEmpty = next.isEmpty
            if isEmpty != lastTextEmpty {
                refreshPlaceholder(placeholder: parent.placeholder, isEmpty: isEmpty)
                lastTextEmpty = isEmpty
            }
            (textView as? GrowingTextView)?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let hasSelection = textView.selectedRange.length > 0
            // Reset typing attributes to plain whenever cursor moves to a non-selection position
            if !hasSelection {
                textView.typingAttributes = RichTextEditor.baseTypingAttributes(textColor: UIColor(parent.textColor))
            }
            guard hasSelection != lastHadSelection else { return }
            lastHadSelection = hasSelection
            parent.onSelectionChanged?(hasSelection)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.listMode == .bullet else { return true }
            let current = textView.text ?? ""
            let ns = current as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { return true }

            var insertion = text

            if insertion == "\n" {
                insertion = "\n" + RichTextEditor.bulletPrefix
            } else if current.isEmpty && range.length == 0 && !insertion.isEmpty {
                insertion = RichTextEditor.bulletizeMultilineInsertion(insertion)
            } else if range.location == 0 && range.length == ns.length && !insertion.isEmpty {
                insertion = RichTextEditor.bulletizeMultilineInsertion(insertion)
            } else if insertion.contains("\n") {
                insertion = RichTextEditor.bulletizeMultilineInsertion(insertion)
            } else {
                return true
            }

            let newFull = ns.replacingCharacters(in: range, with: insertion)
            textView.text = newFull
            let newCaret = range.location + (insertion as NSString).length
            textView.selectedRange = NSRange(location: newCaret, length: 0)
            textViewDidChange(textView)
            (textView as? GrowingTextView)?.invalidateIntrinsicContentSize()
            return false
        }
    }
}

// MARK: - GrowingTextView

final class GrowingTextView: UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        textContainer.lineFragmentPadding = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update placeholder label width without triggering a layout loop
        for case let label as UILabel in subviews {
            if label.preferredMaxLayoutWidth != bounds.width {
                label.preferredMaxLayoutWidth = bounds.width
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        let fitted = sizeThatFits(
            CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: fitted.height)
    }
}
