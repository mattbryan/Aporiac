import SwiftUI
import UIKit

// MARK: - RichTextListMode

internal enum RichTextListMode: Sendable {
    case none
    /// Inserts `• ` at the start of the first line and after each line break as the user writes.
    case bullet
}

// MARK: - RichTextEditor

internal struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textColor: Color = .siftInk
    var listMode: RichTextListMode = .none
    var onSelectionChanged: ((Bool, NSRange) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GrowingTextView {
        let textView = GrowingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
        textView.tintColor = UIColor(Color.siftAccent)
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

        context.coordinator.applyFullContent(text: text, textColor: UIColor(textColor))
        context.coordinator.syncState(text: text, textColor: UIColor(textColor))
        context.coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)

        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GrowingTextView, context: Context) -> CGSize? {
        let width = proposal.width
            ?? uiView.window?.windowScene?.screen.bounds.width
            ?? 375
        let textHeight = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let placeholderHeight: CGFloat
        if let label = uiView.subviews.compactMap({ $0 as? UILabel }).first, !label.isHidden {
            placeholderHeight = label.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
        } else {
            placeholderHeight = 0
        }
        return CGSize(width: width, height: max(textHeight, placeholderHeight, 44))
    }

    func updateUIView(_ uiView: GrowingTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let uiTextColor = UIColor(textColor)
        let tvText = uiView.text ?? ""

        if coordinator.lastPlaceholder != placeholder || coordinator.lastTextEmpty != text.isEmpty {
            coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)
            coordinator.lastPlaceholder = placeholder
            coordinator.lastTextEmpty = text.isEmpty
        }

        if text != tvText {
            coordinator.applyFullContent(text: text, textColor: uiTextColor)
            coordinator.syncState(text: text, textColor: uiTextColor)
            uiView.typingAttributes = Self.baseTypingAttributes(textColor: uiTextColor)
            uiView.invalidateIntrinsicContentSize()
            return
        }

        let colorMatch = coordinator.lastSyncedTextColor.map { $0.isEqual(uiTextColor) } ?? false
        guard !colorMatch else { return }

        coordinator.applyFullContent(text: text, textColor: uiTextColor)
        coordinator.syncState(text: text, textColor: uiTextColor)
        uiView.typingAttributes = Self.baseTypingAttributes(textColor: uiTextColor)
        uiView.invalidateIntrinsicContentSize()
    }

    fileprivate static let baseFont: UIFont = UIFont.systemFont(ofSize: 17, weight: .regular)

    /// Plain-text bullet + space — stored verbatim so Supabase stays aligned with `String` offsets.
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

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var parent: RichTextEditor
        fileprivate weak var textView: GrowingTextView?
        fileprivate weak var placeholderLabel: UILabel?

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

        fileprivate func syncState(text: String, textColor: UIColor) {
            lastSyncedPlainText = text
            lastSyncedTextColor = textColor
        }

        fileprivate func applyFullContent(text: String, textColor: UIColor) {
            guard let textView else { return }
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: RichTextEditor.baseFont,
                .foregroundColor: textColor,
            ]
            textView.attributedText = NSAttributedString(string: text, attributes: baseAttrs)
            textView.textColor = textColor
            textView.font = RichTextEditor.baseFont
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
            let range = textView.selectedRange
            let hasSelection = range.length > 0
            if !hasSelection {
                textView.typingAttributes = RichTextEditor.baseTypingAttributes(textColor: UIColor(parent.textColor))
            }
            guard hasSelection != lastHadSelection else {
                parent.onSelectionChanged?(hasSelection, range)
                return
            }
            lastHadSelection = hasSelection
            parent.onSelectionChanged?(hasSelection, range)
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
        let textHeight = sizeThatFits(
            CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let placeholderHeight: CGFloat
        if let label = subviews.compactMap({ $0 as? UILabel }).first, !label.isHidden {
            placeholderHeight = label.sizeThatFits(
                CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
            ).height
        } else {
            placeholderHeight = 0
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: max(textHeight, placeholderHeight))
    }
}
