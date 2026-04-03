import SwiftUI

struct HomeView: View {
    @State private var showEntry = false
    @State private var actionViewModel = ActionItemViewModel()
    @State private var focusedItemID: UUID? = nil
    private let hasEntry = false

    var body: some View {
        List {
            // MARK: Date + entry card
            Section {
                headerContent
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // MARK: Active actions
            Section {
                ForEach(actionViewModel.activeItems) { item in
                    actionRow(item, focused: focusedItemID == item.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                withAnimation(DS.animationSlow) {
                                    actionViewModel.complete(item)
                                }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .tint(Color.siftGem)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation(DS.animationSlow) {
                                    actionViewModel.delete(item)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                }


                Button {
                    Task {
                        if let item = await actionViewModel.create() {
                            try? await Task.sleep(for: .milliseconds(400))
                            focusedItemID = item.id
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.siftSubtle)
                            .frame(width: 24, height: 24)
                        Text("New action")
                            .font(.siftBody)
                            .foregroundStyle(Color.siftSubtle)
                        Spacer()
                    }
                    .padding(DS.Spacing.sm)
                    .padding(.horizontal, DS.Spacing.md)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                sectionLabel("Actions")
            }

            // MARK: Completed actions
            if !actionViewModel.completedItems.isEmpty {
                Section {
                    ForEach(actionViewModel.completedItems) { item in
                        actionRow(item, focused: false)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(DS.animationSlow) {
                                        actionViewModel.uncomplete(item)
                                    }
                                } label: {
                                    Image(systemName: "arrow.uturn.left")
                                }
                                .tint(Color.siftSubtle)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(DS.animationSlow) {
                                        actionViewModel.delete(item)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    }
                } header: {
                    sectionLabel("Completed")
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(DS.Spacing.xs)
        .scrollContentBackground(.hidden)
        .background(Color.siftSurface.ignoresSafeArea())
        .animation(DS.animationSlow, value: actionViewModel.items)
        .task {
            await actionViewModel.load()
        }
        .onChange(of: SupabaseService.shared.currentUser?.id) {
            Task { await actionViewModel.load() }
        }
        .onChange(of: showEntry) {
            if !showEntry {
                Task { await actionViewModel.load() }
            }
        }
        .fullScreenCover(isPresented: $showEntry) {
            EntryView()
        }
    }

    // MARK: Row

    private func actionRow(_ item: ActionItem, focused: Bool = false) -> some View {
        ActionItemRow(
            item: item,
            focused: focused,
            onToggle: { item.completed ? actionViewModel.uncomplete(item) : actionViewModel.complete(item) },
            onContentChange: { actionViewModel.updateContent(item, content: $0) },
            onReturnCreatesNewItemBelow: item.completed
                ? nil
                : { tail in
                    Task {
                        if let newItem = await actionViewModel.create(after: item, content: tail) {
                            try? await Task.sleep(for: .milliseconds(200))
                            focusedItemID = newItem.id
                        }
                    }
                }
        )
    }

    // MARK: Header

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)
                Text(Date.now, format: .dateTime.month(.wide).day())
                    .font(.siftTitle)
                    .foregroundStyle(Color.siftInk)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.lg)

            Button {
                showEntry = true
            } label: {
                Group {
                    if hasEntry {
                        Text("Entry preview goes here...")
                            .font(.siftBody)
                            .foregroundStyle(Color.siftInk)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Start today's entry")
                            .font(.siftBodyMedium)
                            .foregroundStyle(Color.siftSubtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(DS.Spacing.sm)
                .frame(minHeight: 80, alignment: .topLeading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xs)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.siftCaption)
            .foregroundStyle(Color.siftSubtle)
            .textCase(nil)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.xs)
    }
}

// MARK: - ActionItemRow

private struct ActionItemRow: View {
    let item: ActionItem
    let focused: Bool
    let onToggle: () -> Void
    let onContentChange: (String) -> Void
    /// When non-nil, the first newline in the field finishes the current line and invokes this with text after the newline (new item body).
    var onReturnCreatesNewItemBelow: ((String) -> Void)?

    @FocusState private var isFocused: Bool
    /// Local text keeps Return-from-new-item from briefly showing a second line before the parent model catches up.
    @State private var fieldText: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.animationSlow) { onToggle() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.siftSubtle, lineWidth: 1.5)
                        .opacity(item.completed ? 0 : 1)
                    Circle()
                        .fill(Color.siftGem)
                        .opacity(item.completed ? 1 : 0)
                }
                .frame(width: 24, height: 24)
                .animation(DS.animationSlow, value: item.completed)
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: Binding(
                    get: { fieldText },
                    set: { newValue in
                        if let (head, tail) = newValue.splitAtFirstNewline(),
                           let onReturn = onReturnCreatesNewItemBelow
                        {
                            fieldText = head
                            onContentChange(head)
                            onReturn(tail)
                        } else {
                            fieldText = newValue
                            onContentChange(newValue)
                        }
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.siftBody)
            .foregroundStyle(Color.siftInk)
            .tint(Color.siftGem)
            .lineLimit(1...8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(item.completed)
            .focused($isFocused)
        }
        .padding(DS.Spacing.sm)
        .background(Color.white, in: Capsule())
        .padding(.horizontal, DS.Spacing.md)
        .onAppear {
            fieldText = item.content
        }
        .onChange(of: item.id) { _, _ in
            fieldText = item.content
        }
        .onChange(of: item.content) { _, newValue in
            guard newValue != fieldText else { return }
            fieldText = newValue
        }
        .onChange(of: focused) { _, newValue in
            isFocused = newValue
        }
    }
}

// MARK: - String (action field newline)

private extension String {
    /// Splits on the first newline character, advancing past `\r\n` when present.
    func splitAtFirstNewline() -> (head: String, tail: String)? {
        guard let i = firstIndex(where: { $0.isNewline }) else { return nil }
        let head = String(self[..<i])
        var tailStart = index(after: i)
        if self[i] == "\r", tailStart < endIndex, self[tailStart] == "\n" {
            tailStart = index(after: tailStart)
        }
        let tail = String(self[tailStart...])
        return (head, tail)
    }
}

#Preview {
    HomeView()
}
