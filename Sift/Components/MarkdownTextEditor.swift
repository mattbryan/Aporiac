import SwiftUI
import UIKit

// MARK: - Block kind

internal enum SiftBlockKind: Int, Sendable {
    case gem
    case actionIncomplete
    case actionComplete
}

// MARK: - Attributed string keys

extension NSAttributedString.Key {
    static let siftBlockKind = NSAttributedString.Key("com.aporian.sift.blockKind")
}

// MARK: - Typography (matches `SiftTextStyleToken` / bundled font PostScript names)

private enum MarkdownEditorTypography {
    /// Matches `SiftTextStyleToken.h2Bold` — Newsreader 24pt bold italic.
    private static let h2BoldSize: CGFloat = 24
    private static let p1MediumSize: CGFloat = 17
    private static let p2RegularSize: CGFloat = 15
    private static let gemBodySize: CGFloat = 17

    private static let satoshiRegularName = "Satoshi-Regular"
    private static let satoshiMediumName = "Satoshi-Medium"

    static var h2BoldUIFont: UIFont {
        let size = h2BoldSize
        let directCandidates = [
            "Newsreader-BoldItalic",
            "Newsreader Bold Italic",
            "NewsreaderItalic-Bold",
        ]
        for name in directCandidates {
            if let font = UIFont(name: name, size: size) {
                return font
            }
        }
        for family in UIFont.familyNames where family.contains("Newsreader") {
            for name in UIFont.fontNames(forFamilyName: family) {
                let lower = name.lowercased()
                if lower.contains("italic"), lower.contains("bold"), let font = UIFont(name: name, size: size) {
                    return font
                }
            }
        }
        #if DEBUG
        assertionFailure("H2 font (Newsreader bold italic) not found — check UIAppFonts.")
        #endif
        return UIFont.systemFont(ofSize: size, weight: .bold)
    }

    static func p1MediumUIFont() -> UIFont {
        UIFont(name: satoshiMediumName, size: p1MediumSize)
            ?? UIFont.systemFont(ofSize: p1MediumSize, weight: .medium)
    }

    static func p2RegularUIFont() -> UIFont {
        UIFont(name: satoshiRegularName, size: p2RegularSize)
            ?? UIFont.systemFont(ofSize: p2RegularSize, weight: .regular)
    }

    static func gemBodyUIFont() -> UIFont {
        UIFont(name: satoshiRegularName, size: gemBodySize)
            ?? UIFont.systemFont(ofSize: gemBodySize, weight: .regular)
    }
}

// MARK: - MarkdownTransformTrigger

internal final class MarkdownTransformTrigger: @unchecked Sendable {
    fileprivate var apply: ((SiftBlockKind) -> Void)?

    func fire(_ kind: SiftBlockKind) {
        apply?(kind)
    }
}

// MARK: - Block card layout

/// Block cards use **line fragment** rects (full typographic line, caret-safe). Extra vertical paint
/// (`cardVerticalPadding`) extends below the fragment; keep `paragraphMargin` ≥ that value so the next
/// line’s layout clears the fill.
private enum MarkdownBlockCardLayout {
    /// No extra inset — fragment already matches layout; avoids painting below the line the typesetter uses.
    static let cardVerticalPadding: CGFloat = 0
    /// Space before/after gem paragraphs (plain lines use default 0).
    static let gemParagraphMargin = DS.Spacing.sm
    /// More vertical separation keeps stacked action cards from visually colliding.
    static let actionParagraphMargin = DS.Spacing.md
}

/// Horizontal rhythm for gem accent + action checkbox — keep drawing and `headIndent` aligned.
private enum MarkdownBlockInlineMetrics {
    static let gemAccentBarWidth = DS.Radius.xs
    /// Gold bar + gap before visible text.
    static var gemHeadIndent: CGFloat { gemAccentBarWidth + DS.Spacing.sm }

    static let actionCheckboxLeadingInset = DS.Spacing.md
    static let actionCheckboxSize = DS.IconSize.m
    /// Between checkbox and action text.
    static let actionGapAfterCheckbox: CGFloat = 8
    /// Left padding + circle + gap before visible text.
    static var actionHeadIndent: CGFloat { actionCheckboxLeadingInset + actionCheckboxSize + actionGapAfterCheckbox }
}

/// Plain-text task markers: GFM `- [ ]` / `- [x]` and legacy `* [ ]` / `* [x]` (all 6 characters before body).
private enum MarkdownActionPrefixes {
    static let prefixLength = 6

    static func isCompleteTaskLine(_ line: String) -> Bool {
        line.hasPrefix("* [x] ") || line.hasPrefix("- [x] ")
    }

    static func isIncompleteTaskLine(_ line: String) -> Bool {
        line.hasPrefix("* [ ] ") || line.hasPrefix("- [ ] ")
    }

    static func isAnyTaskLine(_ line: String) -> Bool {
        isCompleteTaskLine(line) || isIncompleteTaskLine(line)
    }

    static func isEmptyTaskLine(_ line: String) -> Bool {
        line == "* [ ] " || line == "* [x] " || line == "- [ ] " || line == "- [x] "
    }

    /// Toolbar inserts GFM-style hyphen lists.
    static let toolbarIncomplete = "- [ ] "
    static let toolbarComplete = "- [x] "

    static func continuationIncomplete(afterLineContents line: String) -> String {
        if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") { return "\n- [ ] " }
        if line.hasPrefix("* [ ] ") || line.hasPrefix("* [x] ") { return "\n* [ ] " }
        return "\n" + toolbarIncomplete
    }

    /// Toggles `- [ ]` ↔ `- [x]` (and `*` variants); prefix and body stay the same length at the marker.
    static func toggledTaskLineContents(_ line: String) -> String? {
        if line.hasPrefix("- [x] ") { return "- [ ] " + String(line.dropFirst(prefixLength)) }
        if line.hasPrefix("- [ ] ") { return "- [x] " + String(line.dropFirst(prefixLength)) }
        if line.hasPrefix("* [x] ") { return "* [ ] " + String(line.dropFirst(prefixLength)) }
        if line.hasPrefix("* [ ] ") { return "* [x] " + String(line.dropFirst(prefixLength)) }
        return nil
    }
}

// MARK: - MarkdownLayoutManager

final class MarkdownLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage,
              let textContainer = textContainers.first else { return }

        let characterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.siftBlockKind, in: characterRange, options: []) { value, range, _ in
            guard let kind = value as? SiftBlockKind else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let cardRect = self.symmetricBlockCardRect(
                glyphRange: glyphRange,
                textContainer: textContainer,
                viewOrigin: origin,
                verticalPadding: MarkdownBlockCardLayout.cardVerticalPadding
            )
            guard cardRect.height > 0.5 else { return }

            switch kind {
            case .gem:
                drawGemCard(in: cardRect)
            case .actionIncomplete:
                drawActionCard(in: cardRect, completed: false, glyphRange: glyphRange, viewOrigin: origin)
            case .actionComplete:
                drawActionCard(in: cardRect, completed: true, glyphRange: glyphRange, viewOrigin: origin)
            }
        }
    }

    /// Full-width card behind a block: height from **line fragment** union (matches TextKit line layout and
    /// caret). Optional symmetric `verticalPadding` for visual breathing only — keep in sync with
    /// `MarkdownBlockCardLayout.paragraphMargin` when non-zero.
    private func symmetricBlockCardRect(
        glyphRange: NSRange,
        textContainer: NSTextContainer,
        viewOrigin: CGPoint,
        verticalPadding: CGFloat
    ) -> CGRect {
        var fragmentUnion = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            fragmentUnion = fragmentUnion.isNull ? rect : fragmentUnion.union(rect)
        }

        let glyphBounds = boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let glyphUsable = !glyphBounds.isNull && !glyphBounds.isInfinite && glyphBounds.height >= 0.5

        // Prefer fragments — already include full line height; union with glyphs was inflating the card.
        let contentRect: CGRect
        if !fragmentUnion.isNull {
            contentRect = fragmentUnion
        } else if glyphUsable {
            contentRect = glyphBounds
        } else {
            return .zero
        }

        var cardRect = contentRect
        cardRect.origin.x = 0
        cardRect.size.width = textContainer.size.width
        cardRect = cardRect.insetBy(dx: 0, dy: -verticalPadding)

        cardRect.origin.x += viewOrigin.x
        cardRect.origin.y += viewOrigin.y
        return cardRect
    }

    private func drawGemCard(in rect: CGRect) {
        UIColor(Color.siftCard).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: DS.Radius.xs).fill()

        let borderRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: MarkdownBlockInlineMetrics.gemAccentBarWidth,
            height: rect.height
        )
        UIColor(Color.siftGem).setFill()
        UIBezierPath(
            roundedRect: borderRect,
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: DS.Radius.xs, height: DS.Radius.xs)
        ).fill()
    }

    private func drawActionCard(
        in rect: CGRect,
        completed: Bool,
        glyphRange _: NSRange,
        viewOrigin _: CGPoint
    ) {
        UIColor(Color.siftCard).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: DS.Radius.xs).fill()

        let checkboxSize = MarkdownBlockInlineMetrics.actionCheckboxSize
        let checkboxX = rect.minX + MarkdownBlockInlineMetrics.actionCheckboxLeadingInset
        let checkboxY = rect.midY - (checkboxSize / 2)
        let checkboxRect = CGRect(x: checkboxX, y: checkboxY, width: checkboxSize, height: checkboxSize)

        if completed {
            UIColor(Color.siftAccent).setFill()
            UIBezierPath(ovalIn: checkboxRect).fill()

            UIColor.white.setStroke()
            let checkPath = UIBezierPath()
            checkPath.lineWidth = 2
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            let cx = checkboxRect.midX
            let cy = checkboxRect.midY
            checkPath.move(to: CGPoint(x: cx - 5, y: cy))
            checkPath.addLine(to: CGPoint(x: cx - 1.5, y: cy + 4))
            checkPath.addLine(to: CGPoint(x: cx + 5.5, y: cy - 4.5))
            checkPath.stroke()
        } else {
            let insetRect = checkboxRect.insetBy(dx: 1, dy: 1)
            let circlePath = UIBezierPath(ovalIn: insetRect)
            circlePath.lineWidth = 2
            UIColor(Color.siftAccent).setStroke()
            circlePath.stroke()
        }
    }

}

// MARK: - MarkdownGrowingTextView

final class MarkdownGrowingTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.textContainer.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.textContainer.lineFragmentPadding = 0
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
            CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
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

    // Disable system context menu since we have a custom toolbar
    @available(iOS 15.0, *)
    override func buildMenu(with builder: UIMenuBuilder) {
        // Don't call super to skip the system menu
    }
}

// MARK: - MarkdownTextEditor

internal struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textColor: Color = .siftInk
    /// Opacity multiplier for plain body and heading text; gems and actions stay full ink.
    var bodyOpacity: Double = 1.0
    var trigger: MarkdownTransformTrigger? = nil
    var onSelectionChanged: ((Bool, NSRange) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MarkdownGrowingTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownGrowingTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
        textView.tintColor = UIColor(Color.siftAccent)
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences

        let placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
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

        let taskCheckboxTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTaskCheckboxTap(_:))
        )
        taskCheckboxTap.delegate = context.coordinator
        taskCheckboxTap.cancelsTouchesInView = true
        textView.addGestureRecognizer(taskCheckboxTap)
        context.coordinator.taskCheckboxTapGesture = taskCheckboxTap

        trigger?.apply = { [weak coordinator = context.coordinator] kind in
            coordinator?.applyTransform(kind: kind)
        }

        textView.text = text
        context.coordinator.reapplyMarkdownAttributes()
        context.coordinator.lastBodyOpacity = bodyOpacity
        context.coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)

        let accessory = context.coordinator.makeKeyboardAccessoryView()
        textView.inputAccessoryView = accessory

        return textView
    }

    func updateUIView(_ uiView: MarkdownGrowingTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        trigger?.apply = { [weak coordinator] kind in
            coordinator?.applyTransform(kind: kind)
        }

        if coordinator.lastPlaceholder != placeholder || coordinator.lastTextEmpty != text.isEmpty {
            coordinator.refreshPlaceholder(placeholder: placeholder, isEmpty: text.isEmpty)
            coordinator.lastPlaceholder = placeholder
            coordinator.lastTextEmpty = text.isEmpty
        }

        let tvText = uiView.text ?? ""
        if text != tvText {
            uiView.text = text
            coordinator.reapplyMarkdownAttributes()
            coordinator.lastBodyOpacity = bodyOpacity
            uiView.invalidateIntrinsicContentSize()
        } else if coordinator.lastBodyOpacity != bodyOpacity {
            coordinator.reapplyMarkdownAttributes()
            coordinator.lastBodyOpacity = bodyOpacity
            uiView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownGrowingTextView, context: Context) -> CGSize? {
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

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        fileprivate var parent: MarkdownTextEditor
        fileprivate weak var textView: MarkdownGrowingTextView?
        fileprivate weak var placeholderLabel: UILabel?
        fileprivate weak var taskCheckboxTapGesture: UITapGestureRecognizer?

        fileprivate var lastPlaceholder: String = ""
        fileprivate var lastTextEmpty: Bool = true
        fileprivate var lastHadSelection: Bool = false
        fileprivate var lastBodyOpacity: Double = .nan

        fileprivate init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        // MARK: Task checkbox tap (toggle + zone left of body)

        @objc fileprivate func handleTaskCheckboxTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let tv = textView else { return }
            applyTaskLineToggleIfNeeded(at: gesture.location(in: tv), textView: tv)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === taskCheckboxTapGesture,
                  let tv = textView else { return true }
            return taskToggleHit(at: touch.location(in: tv), textView: tv) != nil
        }

        private func containerPoint(fromTextViewPoint point: CGPoint, textView: UITextView) -> CGPoint {
            CGPoint(
                x: point.x - textView.textContainerInset.left + textView.contentOffset.x,
                y: point.y - textView.textContainerInset.top + textView.contentOffset.y
            )
        }

        /// Hit inside the action gutter (drawn checkbox + space before visible body) on a task line.
        private func taskToggleHit(at point: CGPoint, textView: UITextView) -> (lineStart: Int, contentsEnd: Int, newLine: String)? {
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer

            let c = containerPoint(fromTextViewPoint: point, textView: textView)
            let maxX = MarkdownBlockInlineMetrics.actionHeadIndent
            guard c.x >= 0, c.x < maxX else { return nil }

            let idx = layoutManager.characterIndex(
                for: c,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let text = textView.text ?? ""
            let ns = text as NSString
            guard !text.isEmpty, idx != NSNotFound, idx <= ns.length else { return nil }

            let clamped = min(max(0, idx), max(0, ns.length - 1))
            var lineStart = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: clamped, length: 0))
            let lineContents = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            guard let newLine = MarkdownActionPrefixes.toggledTaskLineContents(lineContents) else { return nil }
            return (lineStart, contentsEnd, newLine)
        }

        private func applyTaskLineToggleIfNeeded(at point: CGPoint, textView: UITextView) {
            guard let hit = taskToggleHit(at: point, textView: textView) else { return }
            let current = textView.text ?? ""
            let mutable = NSMutableString(string: current)
            let replace = NSRange(location: hit.lineStart, length: hit.contentsEnd - hit.lineStart)
            guard NSMaxRange(replace) <= mutable.length else { return }
            mutable.replaceCharacters(in: replace, with: hit.newLine)
            textView.text = mutable as String
            textViewDidChange(textView)
            let len = (hit.newLine as NSString).length
            let caret = hit.lineStart + len
            let maxCaret = (textView.text ?? "").count
            textView.selectedRange = NSRange(location: min(caret, maxCaret), length: 0)
        }

        fileprivate func refreshPlaceholder(placeholder: String, isEmpty: Bool) {
            guard let label = placeholderLabel else { return }
            label.text = placeholder
            label.isHidden = !isEmpty
            if let tv = textView, tv.bounds.width > 0 {
                label.preferredMaxLayoutWidth = tv.bounds.width
            }
        }

        /// Keyboard toolbar: block shortcuts (gem, action, headings). Matches entry highlight toolbar styling.
        fileprivate func makeKeyboardAccessoryView() -> UIView {
            let accessory = UIView()
            accessory.backgroundColor = UIColor(Color.siftSurface)
            accessory.translatesAutoresizingMaskIntoConstraints = false

            let topBorder = UIView()
            topBorder.translatesAutoresizingMaskIntoConstraints = false
            topBorder.backgroundColor = UIColor(Color.siftDivider)
            accessory.addSubview(topBorder)

            let stack = UIStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = DS.Spacing.md
            stack.distribution = .fill

            let font = MarkdownEditorTypography.p1MediumUIFont()
            let specs: [(label: String, color: Color, prefix: String)] = [
                ("Gem", .siftGem, "> "),
                ("Action", .siftAction, MarkdownActionPrefixes.toolbarIncomplete),
                ("H1", .siftSubtle, "# "),
                ("H2", .siftSubtle, "## "),
            ]
            for spec in specs {
                let button = UIButton(type: .system)
                button.setTitle(spec.label, for: .normal)
                button.setTitleColor(UIColor(spec.color), for: .normal)
                button.titleLabel?.font = font
                button.addAction(
                    UIAction { [weak self] _ in
                        self?.insertBlockLine(prefix: spec.prefix)
                    },
                    for: .touchUpInside
                )
                stack.addArrangedSubview(button)
            }

            accessory.addSubview(stack)

            let borderHeight: CGFloat = 1
            let rowHeight: CGFloat = 44
            NSLayoutConstraint.activate([
                accessory.heightAnchor.constraint(equalToConstant: borderHeight + rowHeight),

                topBorder.topAnchor.constraint(equalTo: accessory.topAnchor),
                topBorder.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
                topBorder.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                topBorder.heightAnchor.constraint(equalToConstant: borderHeight),

                stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: DS.Spacing.md),
                stack.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
                stack.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            ])

            return accessory
        }

        fileprivate func insertBlockLine(prefix: String) {
            guard let textView else { return }
            let text = textView.text ?? ""
            let ns = text as NSString
            let cursor = textView.selectedRange.location
            let safeCursor = min(max(cursor, 0), ns.length)

            var lineStart = 0, contentsEnd = 0
            if ns.length > 0 {
                ns.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd,
                                for: NSRange(location: min(safeCursor, max(0, ns.length - 1)), length: 0))
            }
            let lineContents = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            let isEmptyLine = lineContents.trimmingCharacters(in: .whitespaces).isEmpty

            let insertion: String
            let insertAt: Int
            if isEmptyLine {
                insertion = prefix
                insertAt = lineStart
            } else {
                insertion = "\n" + prefix
                insertAt = safeCursor
            }

            let mutable = NSMutableString(string: text)
            mutable.insert(insertion, at: insertAt)
            textView.text = mutable as String

            let newCursor = min(insertAt + (insertion as NSString).length, (textView.text ?? "").count)
            textView.selectedRange = NSRange(location: newCursor, length: 0)
            textViewDidChange(textView)
        }

        fileprivate func baseTypingAttributes(textColor: UIColor) -> [NSAttributedString.Key: Any] {
            [
                .font: MarkdownEditorTypography.p2RegularUIFont(),
                .foregroundColor: textColor,
            ]
        }

        fileprivate func reapplyMarkdownAttributes() {
            guard let textView else { return }
            let text = textView.text ?? ""
            let nsText = text as NSString
            let storage = textView.textStorage
            let uiTextColor = UIColor(parent.textColor)
            let bodyTextColor = uiTextColor.withAlphaComponent(CGFloat(parent.bodyOpacity))
            let len = nsText.length
            let fullRange = NSRange(location: 0, length: len)

            let baseFont = MarkdownEditorTypography.p2RegularUIFont()

            if len > 0 {
                storage.beginEditing()
                storage.setAttributes(
                    [
                        .font: baseFont,
                        .foregroundColor: bodyTextColor,
                    ],
                    range: fullRange
                )
                storage.removeAttribute(.siftBlockKind, range: fullRange)
                storage.removeAttribute(.paragraphStyle, range: fullRange)
                storage.removeAttribute(.strikethroughStyle, range: fullRange)

                var lineStart = 0
                while lineStart < len {
                    var lineEnd = 0
                    var contentsEnd = 0
                    nsText.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))

                    let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                    let contentsRange = NSRange(location: lineStart, length: contentsEnd - lineStart)

                    guard contentsRange.length > 0 else {
                        lineStart = lineEnd
                        continue
                    }

                    guard NSMaxRange(lineRange) <= storage.length else {
                        lineStart = lineEnd
                        continue
                    }

                    let lineString = nsText.substring(with: contentsRange)

                    if lineString.hasPrefix("## ") {
                        applyHeading2Attributes(to: storage, lineRange: lineRange, prefixLength: 3, textColor: bodyTextColor)
                    } else if lineString.hasPrefix("# ") {
                        applyHeading1Attributes(to: storage, lineRange: lineRange, prefixLength: 2, textColor: bodyTextColor)
                    } else if lineString.hasPrefix("> ") {
                        applyGemAttributes(to: storage, lineRange: lineRange, prefixLength: 2, textColor: uiTextColor)
                    } else if MarkdownActionPrefixes.isCompleteTaskLine(lineString) {
                        applyActionAttributes(
                            to: storage,
                            lineRange: lineRange,
                            prefixLength: MarkdownActionPrefixes.prefixLength,
                            completed: true,
                            textColor: uiTextColor
                        )
                    } else if MarkdownActionPrefixes.isIncompleteTaskLine(lineString) {
                        applyActionAttributes(
                            to: storage,
                            lineRange: lineRange,
                            prefixLength: MarkdownActionPrefixes.prefixLength,
                            completed: false,
                            textColor: uiTextColor
                        )
                    }

                    lineStart = lineEnd
                }

                storage.endEditing()
            }

            textView.typingAttributes = baseTypingAttributes(textColor: bodyTextColor)
            textView.invalidateIntrinsicContentSize()
        }

        /// Headings: no `paragraphStyle` (negative `firstLineHeadIndent` was unreliable and affected layout). Prefix stays in the string but is clear and uses a near-zero font size (0.1pt) so it occupies no horizontal space. Visible title left-aligns with body text at x=0.
        private func applyHeading1Attributes(to storage: NSTextStorage, lineRange: NSRange, prefixLength: Int, textColor: UIColor) {
            let h2Font = MarkdownEditorTypography.h2BoldUIFont
            storage.addAttribute(.font, value: h2Font, range: lineRange)
            storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
            let prefixRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
            guard NSMaxRange(prefixRange) <= storage.length else { return }
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.1), range: prefixRange)
        }

        private func applyHeading2Attributes(to storage: NSTextStorage, lineRange: NSRange, prefixLength: Int, textColor: UIColor) {
            let p1MediumFont = MarkdownEditorTypography.p1MediumUIFont()
            storage.addAttribute(.font, value: p1MediumFont, range: lineRange)
            storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
            let prefixRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
            guard NSMaxRange(prefixRange) <= storage.length else { return }
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.1), range: prefixRange)
        }

        private func applyGemAttributes(to storage: NSTextStorage, lineRange: NSRange, prefixLength: Int, textColor: UIColor) {
            let style = NSMutableParagraphStyle()
            let head = MarkdownBlockInlineMetrics.gemHeadIndent + DS.Spacing.xs
            style.headIndent = head
            style.firstLineHeadIndent = head
            style.tailIndent = -DS.Spacing.xs
            style.paragraphSpacingBefore = MarkdownBlockCardLayout.gemParagraphMargin
            style.paragraphSpacing = MarkdownBlockCardLayout.gemParagraphMargin

            storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
            storage.addAttribute(.siftBlockKind, value: SiftBlockKind.gem, range: lineRange)
            storage.addAttribute(.font, value: MarkdownEditorTypography.gemBodyUIFont(), range: lineRange)
            storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)

            let prefixRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
            guard NSMaxRange(prefixRange) <= storage.length else { return }
            // Collapse prefix to near-zero width so first-line text aligns with wrapped lines
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.1), range: prefixRange)
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
        }

        private func applyActionAttributes(
            to storage: NSTextStorage,
            lineRange: NSRange,
            prefixLength: Int,
            completed: Bool,
            textColor: UIColor
        ) {
            let style = NSMutableParagraphStyle()
            let head = MarkdownBlockInlineMetrics.actionHeadIndent + DS.Spacing.xs
            style.headIndent = head
            style.firstLineHeadIndent = head
            style.tailIndent = -DS.Spacing.xs
            style.paragraphSpacingBefore = 0
            style.paragraphSpacing = MarkdownBlockCardLayout.actionParagraphMargin

            storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
            let kind: SiftBlockKind = completed ? .actionComplete : .actionIncomplete
            storage.addAttribute(.siftBlockKind, value: kind, range: lineRange)
            storage.addAttribute(.font, value: MarkdownEditorTypography.p2RegularUIFont(), range: lineRange)

            if completed {
                storage.addAttribute(.foregroundColor, value: UIColor(Color.siftSubtle), range: lineRange)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            } else {
                storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
            }

            let prefixRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
            guard NSMaxRange(prefixRange) <= storage.length else { return }
            // Collapse prefix to near-zero width so first-line text aligns with wrapped lines
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.1), range: prefixRange)
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
            if completed {
                storage.addAttribute(.strikethroughStyle, value: 0, range: prefixRange)
            }
        }

        fileprivate func applyTransform(kind: SiftBlockKind) {
            guard let textView else { return }
            let selection = textView.selectedRange
            guard selection.length > 0 else { return }

            let text = textView.text ?? ""
            let ns = text as NSString
            guard NSMaxRange(selection) <= ns.length else { return }

            let selectedText = ns.substring(with: selection)

            let firstLine = selectedText.components(separatedBy: "\n").first ?? selectedText
            switch kind {
            case .gem:
                if firstLine.hasPrefix("> ") { return }
            case .actionIncomplete:
                if MarkdownActionPrefixes.isAnyTaskLine(firstLine) { return }
            case .actionComplete:
                return
            }

            let prefix: String
            switch kind {
            case .gem: prefix = "> "
            case .actionIncomplete: prefix = MarkdownActionPrefixes.toolbarIncomplete
            case .actionComplete: prefix = MarkdownActionPrefixes.toolbarComplete
            }

            var leadingNewline = ""
            if selection.location > 0 {
                let charBefore = ns.substring(with: NSRange(location: selection.location - 1, length: 1))
                if charBefore != "\n" { leadingNewline = "\n" }
            }

            var trailingNewline = ""
            let endLocation = NSMaxRange(selection)
            if endLocation < ns.length {
                let charAfter = ns.substring(with: NSRange(location: endLocation, length: 1))
                if charAfter != "\n" { trailingNewline = "\n" }
            }

            let replacement = "\(leadingNewline)\(prefix)\(selectedText)\(trailingNewline)"
            let mutable = NSMutableString(string: text)
            mutable.replaceCharacters(in: selection, with: replacement)
            textView.text = mutable as String

            let cursorPos = selection.location + (leadingNewline as NSString).length + (prefix as NSString).length + selection.length
            textView.selectedRange = NSRange(location: cursorPos, length: 0)

            reapplyMarkdownAttributes()

            parent.text = textView.text ?? ""
            lastHadSelection = false
            parent.onSelectionChanged?(false, textView.selectedRange)
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }

            let currentText = textView.text ?? ""
            let ns = currentText as NSString

            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
            let lineContents = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))

            if lineContents == "> " {
                let deleteRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
                let mutable = NSMutableString(string: currentText)
                mutable.replaceCharacters(in: deleteRange, with: "")
                textView.text = mutable as String
                textView.selectedRange = NSRange(location: lineStart, length: 0)
                reapplyMarkdownAttributes()
                (textView as? MarkdownGrowingTextView)?.invalidateIntrinsicContentSize()
                textViewDidChange(textView)
                return false
            } else if lineContents.hasPrefix("> ") {
                let insertion = "\n> "
                let mutable = NSMutableString(string: currentText)
                mutable.replaceCharacters(in: range, with: insertion)
                textView.text = mutable as String
                let newCaret = range.location + (insertion as NSString).length
                textView.selectedRange = NSRange(location: newCaret, length: 0)
                reapplyMarkdownAttributes()
                (textView as? MarkdownGrowingTextView)?.invalidateIntrinsicContentSize()
                textViewDidChange(textView)
                return false
            } else if MarkdownActionPrefixes.isEmptyTaskLine(lineContents) {
                let deleteRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
                let mutable = NSMutableString(string: currentText)
                mutable.replaceCharacters(in: deleteRange, with: "")
                textView.text = mutable as String
                textView.selectedRange = NSRange(location: lineStart, length: 0)
                reapplyMarkdownAttributes()
                (textView as? MarkdownGrowingTextView)?.invalidateIntrinsicContentSize()
                textViewDidChange(textView)
                return false
            } else if MarkdownActionPrefixes.isAnyTaskLine(lineContents) {
                let insertion = "\n"
                let mutable = NSMutableString(string: currentText)
                mutable.replaceCharacters(in: range, with: insertion)
                textView.text = mutable as String
                let newCaret = range.location + (insertion as NSString).length
                textView.selectedRange = NSRange(location: newCaret, length: 0)
                reapplyMarkdownAttributes()
                (textView as? MarkdownGrowingTextView)?.invalidateIntrinsicContentSize()
                textViewDidChange(textView)
                return false
            }

            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let next = textView.text ?? ""
            parent.text = next
            let isEmpty = next.isEmpty
            if isEmpty != lastTextEmpty {
                refreshPlaceholder(placeholder: parent.placeholder, isEmpty: isEmpty)
                lastTextEmpty = isEmpty
            }
            reapplyMarkdownAttributes()
            (textView as? MarkdownGrowingTextView)?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let hasSelection = range.length > 0

            if !hasSelection {
                let contextAttributes = typingAttributesForCurrentPosition(textView: textView)
                textView.typingAttributes = contextAttributes
            }

            guard hasSelection != lastHadSelection else {
                parent.onSelectionChanged?(hasSelection, range)
                return
            }
            lastHadSelection = hasSelection
            parent.onSelectionChanged?(hasSelection, range)
        }

        private func typingAttributesForCurrentPosition(textView: UITextView) -> [NSAttributedString.Key: Any] {
            let uiTextColor = UIColor(parent.textColor)
            let bodyTextColor = uiTextColor.withAlphaComponent(CGFloat(parent.bodyOpacity))
            guard let text = textView.text, !text.isEmpty else {
                return baseTypingAttributes(textColor: bodyTextColor)
            }
            let ns = text as NSString
            let len = ns.length
            let rawPos = textView.selectedRange.location
            let pos = min(max(0, rawPos), len)
            var lineStart = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: pos, length: 0))
            let lineContents = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))

            if lineContents.hasPrefix("## ") {
                let font = MarkdownEditorTypography.p1MediumUIFont()
                return [
                    .font: font,
                    .foregroundColor: bodyTextColor,
                ]
            }
            if lineContents.hasPrefix("# ") {
                let font = MarkdownEditorTypography.h2BoldUIFont
                return [
                    .font: font,
                    .foregroundColor: bodyTextColor,
                ]
            }
            if lineContents.hasPrefix("> ") {
                return [
                    .font: MarkdownEditorTypography.gemBodyUIFont(),
                    .foregroundColor: uiTextColor,
                ]
            }
            if MarkdownActionPrefixes.isAnyTaskLine(lineContents) {
                return [
                    .font: MarkdownEditorTypography.p2RegularUIFont(),
                    .foregroundColor: uiTextColor,
                ]
            }
            return baseTypingAttributes(textColor: bodyTextColor)
        }
    }
}
