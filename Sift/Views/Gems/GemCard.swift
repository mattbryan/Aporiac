import SwiftUI

/// A read-only row showing one gem, its optional AI thread line, date, and linked themes.
struct GemCard: View {
    let item: GemWithThemes

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(item.gem.content)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .fixedSize(horizontal: false, vertical: true)

            if let thread = item.gem.thread, !thread.isEmpty {
                Text(thread)
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftSubtle)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Spacing.sm) {
                Text(item.gem.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)

                if !item.themes.isEmpty {
                    ForEach(item.themes) { theme in
                        Text(theme.title)
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftGem)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(Color.siftGem.opacity(0.12), in: Capsule())
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, DS.Spacing.md)
    }
}

#if DEBUG
#Preview {
    GemCard(
        item: GemWithThemes(
            gem: Gem(
                id: UUID(),
                userID: UUID(),
                entryID: UUID(),
                content: "A fragment worth keeping from the entry.",
                rangeStart: 0,
                rangeEnd: 10,
                thread: "Two ideas reach toward the same quiet conclusion.",
                createdAt: .now
            ),
            themes: []
        )
    )
}
#endif
