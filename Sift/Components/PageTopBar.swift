import SwiftUI

/// Unified top bar component for collection pages (Gems, Habits, Themes).
/// Displays a title and an add button.
struct PageTopBar: View {
    let title: String
    let onAddPressed: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .siftTextStyle(.h1Bold)
                .foregroundStyle(Color.siftInk)
            Spacer()
            Button {
                onAddPressed()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.siftInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.md)
    }
}

#if DEBUG
#Preview {
    PageTopBar(title: "Gems") {
        print("Add pressed")
    }
}
#endif
