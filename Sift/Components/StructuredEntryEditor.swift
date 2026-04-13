import SwiftUI
import UIKit

private enum EntryBlockToolbarAction: CaseIterable {
    case paragraph
    case gem
    case action
    case heading1
    case heading2

    var title: String {
        switch self {
        case .paragraph: "Text"
        case .gem: "Gem"
        case .action: "Action"
        case .heading1: "H1"
        case .heading2: "H2"
        }
    }
}

private enum BlockEditCommand {
    case allowSystem
    case replace(text: String, caretLocation: Int)
    case handled
}

internal struct StructuredEntryEditor: View {
    @Binding var text: String
    var placeholder: String
    var bodyOpacity: Double = 1.0

    @State private var blocks: [PersistedEntryBlock] = []
    @State private var focusedBlockID: UUID?
    @State private var lastSerializedText = ""
    @State private var didHydrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if blocks.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        ensureDocumentExists()
                    }
            }

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, index: index)
            }
        }
        .task {
            guard !didHydrate else { return }
            didHydrate = true
            hydrateFromText(text)
        }
        .onChange(of: text) { _, newValue in
            guard newValue != lastSerializedText else { return }
            hydrateFromText(newValue)
        }
    }

    @ViewBuilder
    private func blockView(_ block: PersistedEntryBlock, index: Int) -> some View {
        switch block.type {
        case .paragraph:
            editorBlock(
                index: index,
                placeholder: index == 0 ? placeholder : "",
                textColor: .siftInk.opacity(bodyOpacity),
                font: UIFont(name: "Satoshi-Regular", size: 17) ?? .systemFont(ofSize: 17)
            )

        case .heading1:
            editorBlock(
                index: index,
                placeholder: "",
                textColor: .siftInk.opacity(bodyOpacity),
                font: UIFont(name: "Newsreader-BoldItalic", size: 24) ?? .systemFont(ofSize: 24, weight: .bold)
            )

        case .heading2:
            editorBlock(
                index: index,
                placeholder: "",
                textColor: .siftInk.opacity(bodyOpacity),
                font: UIFont(name: "Satoshi-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
            )

        case .gem:
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(Color.siftGem)
                    .frame(width: DS.Radius.xs)

                editorBlock(
                    index: index,
                    placeholder: "",
                    textColor: .siftInk,
                    font: UIFont(name: "Satoshi-Regular", size: 17) ?? .systemFont(ofSize: 17)
                )
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.sm)
            }
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))

        case .action:
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Button {
                    toggleAction(index)
                } label: {
                    ZStack {
                        Circle()
                            .stroke((block.checked ?? false) ? Color.clear : Color.siftAccent, lineWidth: 2)
                            .background(
                                Circle()
                                    .fill((block.checked ?? false) ? Color.siftAccent : Color.clear)
                            )
                        if block.checked ?? false {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: DS.IconSize.m, height: DS.IconSize.m)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                editorBlock(
                    index: index,
                    placeholder: "",
                    textColor: (block.checked ?? false) ? .siftSubtle : .siftInk,
                    font: UIFont(name: "Satoshi-Regular", size: 15) ?? .systemFont(ofSize: 15)
                )
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }
    }

    private func editorBlock(
        index: Int,
        placeholder: String,
        textColor: Color,
        font: UIFont
    ) -> some View {
        StableBlockTextEditor(
            text: blocks[index].text,
            placeholder: placeholder,
            textColor: textColor,
            uiFont: font,
            isFocused: focusedBlockID == blocks[index].id,
            onFocus: { focusedBlockID = blocks[index].id },
            onTextChange: { handleTextChange(at: index, newText: $0) },
            onReturn: { currentText, selection in
                handleReturn(at: index, currentText: currentText, selection: selection)
            },
            onBackspaceAtStart: {
                handleBackspaceAtStart(at: index)
            },
            onToolbarAction: { action in
                applyToolbarAction(action, at: index)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hydrateFromText(_ source: String) {
        let parsed = EntryMarkdownBlockCodec.blocks(from: source)
        blocks = parsed.isEmpty ? [PersistedEntryBlock(type: .paragraph, text: "")] : parsed
        lastSerializedText = source
        if focusedBlockID == nil {
            focusedBlockID = blocks.first?.id
        }
    }

    private func ensureDocumentExists() {
        guard blocks.isEmpty else { return }
        blocks = [PersistedEntryBlock(type: .paragraph, text: "")]
        focusedBlockID = blocks.first?.id
        syncTextFromBlocks()
    }

    private func handleTextChange(at index: Int, newText: String) {
        guard blocks.indices.contains(index) else { return }

        if let transform = shortcutTransform(for: newText) {
            blocks[index].type = transform.type
            blocks[index].checked = transform.checked
            blocks[index].text = transform.text
        } else {
            blocks[index].text = newText
        }

        syncTextFromBlocks()
    }

    private func handleReturn(at index: Int, currentText: String, selection: NSRange) -> BlockEditCommand {
        guard blocks.indices.contains(index) else { return .allowSystem }
        let block = blocks[index]

        switch block.type {
        case .paragraph, .heading1, .heading2:
            let split = splitText(currentText, at: selection)
            blocks[index].text = split.before
            let newType: PersistedEntryBlockType = .paragraph
            let newBlock = PersistedEntryBlock(type: newType, text: split.after)
            blocks.insert(newBlock, at: index + 1)
            focusedBlockID = newBlock.id
            syncTextFromBlocks()
            return .handled

        case .action:
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                blocks[index].type = .paragraph
                blocks[index].checked = nil
                blocks[index].text = ""
                syncTextFromBlocks()
                return .handled
            }

            let newBlock = PersistedEntryBlock(type: .action, text: "", checked: false)
            blocks.insert(newBlock, at: index + 1)
            focusedBlockID = newBlock.id
            syncTextFromBlocks()
            return .handled

        case .gem:
            let nsText = currentText as NSString
            let atDocumentEnd = selection.location == nsText.length && selection.length == 0
            if atDocumentEnd && currentText.hasSuffix("\n") {
                blocks[index].text = String(currentText.dropLast())
                let newBlock = PersistedEntryBlock(type: .paragraph, text: "")
                blocks.insert(newBlock, at: index + 1)
                focusedBlockID = newBlock.id
                syncTextFromBlocks()
                return .handled
            }

            let replaced = nsText.replacingCharacters(in: selection, with: "\n")
            return .replace(text: replaced, caretLocation: selection.location + 1)
        }
    }

    private func handleBackspaceAtStart(at index: Int) -> BlockEditCommand {
        guard blocks.indices.contains(index) else { return .allowSystem }
        switch blocks[index].type {
        case .gem, .action, .heading1, .heading2:
            blocks[index].type = .paragraph
            blocks[index].checked = nil
            syncTextFromBlocks()
            return .handled
        case .paragraph:
            return .allowSystem
        }
    }

    private func applyToolbarAction(_ action: EntryBlockToolbarAction, at index: Int) {
        guard blocks.indices.contains(index) else { return }
        switch action {
        case .paragraph:
            blocks[index].type = .paragraph
            blocks[index].checked = nil
        case .gem:
            blocks[index].type = .gem
            blocks[index].checked = nil
        case .action:
            blocks[index].type = .action
            blocks[index].checked = false
        case .heading1:
            blocks[index].type = .heading1
            blocks[index].checked = nil
        case .heading2:
            blocks[index].type = .heading2
            blocks[index].checked = nil
        }
        syncTextFromBlocks()
        focusedBlockID = blocks[index].id
    }

    private func toggleAction(_ index: Int) {
        guard blocks.indices.contains(index), blocks[index].type == .action else { return }
        blocks[index].checked = !(blocks[index].checked ?? false)
        syncTextFromBlocks()
    }

    private func syncTextFromBlocks() {
        let serialized = EntryMarkdownBlockCodec.markdown(from: blocks)
        lastSerializedText = serialized
        if text != serialized {
            text = serialized
        }
    }

    private func shortcutTransform(for text: String) -> (type: PersistedEntryBlockType, text: String, checked: Bool?)? {
        if text.hasPrefix("## ") {
            return (.heading2, String(text.dropFirst(3)), nil)
        }
        if text.hasPrefix("# ") {
            return (.heading1, String(text.dropFirst(2)), nil)
        }
        if text.hasPrefix("> ") {
            return (.gem, String(text.dropFirst(2)), nil)
        }
        if text.hasPrefix("- [x] ") || text.hasPrefix("* [x] ") {
            return (.action, String(text.dropFirst(6)), true)
        }
        if text.hasPrefix("- [ ] ") || text.hasPrefix("* [ ] ") {
            return (.action, String(text.dropFirst(6)), false)
        }
        return nil
    }

    private func splitText(_ text: String, at selection: NSRange) -> (before: String, after: String) {
        let nsText = text as NSString
        let safeRange = NSRange(location: min(selection.location, nsText.length), length: min(selection.length, max(0, nsText.length - selection.location)))
        let before = nsText.substring(to: safeRange.location)
        let after = nsText.substring(from: NSMaxRange(safeRange))
        return (before, after)
    }
}

private struct StableBlockTextEditor: UIViewRepresentable {
    let text: String
    let placeholder: String
    let textColor: Color
    let uiFont: UIFont
    let isFocused: Bool
    let onFocus: () -> Void
    let onTextChange: (String) -> Void
    let onReturn: (String, NSRange) -> BlockEditCommand
    let onBackspaceAtStart: () -> BlockEditCommand
    let onToolbarAction: (EntryBlockToolbarAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GrowingTextView {
        let textView = GrowingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
        textView.tintColor = UIColor(Color.siftAccent)
        textView.font = uiFont
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.typingAttributes = [
            .font: uiFont,
            .foregroundColor: UIColor(textColor),
        ]

        let placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = uiFont
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
        context.coordinator.refreshPlaceholder(text: text, placeholder: placeholder)
        textView.text = text
        textView.inputAccessoryView = context.coordinator.makeAccessoryView()
        return textView
    }

    func updateUIView(_ uiView: GrowingTextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = UIColor(textColor)
        uiView.font = uiFont
        uiView.typingAttributes = [
            .font: uiFont,
            .foregroundColor: UIColor(textColor),
        ]
        context.coordinator.refreshPlaceholder(text: text, placeholder: placeholder)

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StableBlockTextEditor
        weak var textView: GrowingTextView?
        weak var placeholderLabel: UILabel?

        init(_ parent: StableBlockTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus()
        }

        func textViewDidChange(_ textView: UITextView) {
            let next = textView.text ?? ""
            refreshPlaceholder(text: next, placeholder: parent.placeholder)
            parent.onTextChange(next)
            (textView as? GrowingTextView)?.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacementText: String) -> Bool {
            if replacementText == "\n" {
                switch parent.onReturn(textView.text ?? "", range) {
                case .allowSystem:
                    return true
                case .replace(let text, let caretLocation):
                    textView.text = text
                    textView.selectedRange = NSRange(location: caretLocation, length: 0)
                    textViewDidChange(textView)
                    return false
                case .handled:
                    return false
                }
            }

            if replacementText.isEmpty, range.length == 0, range.location == 0 {
                switch parent.onBackspaceAtStart() {
                case .allowSystem:
                    return true
                case .replace(let text, let caretLocation):
                    textView.text = text
                    textView.selectedRange = NSRange(location: caretLocation, length: 0)
                    textViewDidChange(textView)
                    return false
                case .handled:
                    return false
                }
            }

            return true
        }

        func refreshPlaceholder(text: String, placeholder: String) {
            placeholderLabel?.text = placeholder
            placeholderLabel?.isHidden = !text.isEmpty
            if let tv = textView, tv.bounds.width > 0 {
                placeholderLabel?.preferredMaxLayoutWidth = tv.bounds.width
            }
        }

        func makeAccessoryView() -> UIView {
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

            for action in EntryBlockToolbarAction.allCases {
                let button = UIButton(type: .system)
                button.setTitle(action.title, for: .normal)
                button.setTitleColor(UIColor(Color.siftInk), for: .normal)
                button.titleLabel?.font = UIFont(name: "Satoshi-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
                button.addAction(UIAction { [weak self] _ in
                    self?.parent.onToolbarAction(action)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }

            accessory.addSubview(stack)

            NSLayoutConstraint.activate([
                accessory.heightAnchor.constraint(equalToConstant: 45),
                topBorder.topAnchor.constraint(equalTo: accessory.topAnchor),
                topBorder.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
                topBorder.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                topBorder.heightAnchor.constraint(equalToConstant: 1),
                stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: DS.Spacing.md),
                stack.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
                stack.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            ])

            return accessory
        }
    }
}
