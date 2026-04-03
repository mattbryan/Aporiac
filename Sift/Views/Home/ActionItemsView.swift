import SwiftUI

struct ActionItemsView: View {
    @Bindable var viewModel: ActionItemViewModel

    var body: some View {
        ForEach(viewModel.sortedItems) { item in
            itemRow(item)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation(DS.animationSlow) { viewModel.delete(item) }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if item.completed {
                        Button {
                            withAnimation(DS.animationSlow) { viewModel.uncomplete(item) }
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .tint(Color.siftSubtle)
                    } else {
                        Button {
                            withAnimation(DS.animationSlow) { viewModel.complete(item) }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .tint(Color.siftGem)
                    }
                }
        }

        // Completed section label — only shown when there are completed items
        if !viewModel.completedItems.isEmpty {
            Text("Completed")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.top, DS.Spacing.xs)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private func itemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.animationSlow) {
                    item.completed ? viewModel.uncomplete(item) : viewModel.complete(item)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.siftSubtle, lineWidth: 1.5)
                        .opacity(item.completed ? 0 : 1)

                    Circle()
                        .fill(Color.siftInk)
                        .opacity(item.completed ? 1 : 0)
                }
                .frame(width: 24, height: 24)
                .animation(DS.animationSlow, value: item.completed)
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: Binding(
                    get: { item.content },
                    set: { viewModel.updateContent(item, content: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.siftBody)
            .foregroundStyle(Color.siftInk)
            .tint(Color.siftInk)
            .lineLimit(1...8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(item.completed)
        }
        .padding(DS.Spacing.sm)
        .background(Color.siftInk.opacity(0.06), in: Capsule())
        .padding(.horizontal, DS.Spacing.sm)
    }
}
