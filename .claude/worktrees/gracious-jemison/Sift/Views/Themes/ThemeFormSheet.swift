import SwiftUI

/// Form for creating a theme or editing an existing one.
struct ThemeFormSheet: View {
    enum ThemeFormMode {
        case create
        case edit(Theme)
    }

    let mode: ThemeFormMode
    let onSave: (String, String?) -> Void
    var onArchive: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var description: String = ""
    @Environment(\.dismiss) private var dismiss

    private var sheetTitle: String {
        switch mode {
        case .create:
            "New theme"
        case .edit:
            "Edit theme"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sheetTitle)
                .siftTextStyle(.h2Medium)
                .foregroundStyle(Color.siftInk)
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)

            Text("Title")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .padding(.horizontal, 20)
            TextField("What are you orienting toward?", text: $title)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .padding(DS.Spacing.md)
                .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.md)

            Text("Description")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .padding(.horizontal, 20)
            TextField("Optional", text: $description, axis: .vertical)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .lineLimit(3...5)
                .padding(DS.Spacing.md)
                .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.sm)

            Spacer()

            Button {
                let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), desc.isEmpty ? nil : desc)
                dismiss()
            } label: {
                Text("Save")
                    .font(.siftBodyMedium)
                    .foregroundStyle(Color.siftSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.ButtonHeight.large)
                    .background(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.siftInk.opacity(0.3)
                            : Color.siftInk,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md)
                    )
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, DS.Spacing.sm)

            if let onArchive {
                Button {
                    onArchive()
                    dismiss()
                } label: {
                    Text("Archive theme")
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftSubtle)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.ButtonHeight.medium)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.siftSurface)
        .onAppear {
            if case .edit(let theme) = mode {
                title = theme.title
                description = theme.description ?? ""
            }
        }
    }
}

#if DEBUG
#Preview("Create") {
    ThemeFormSheet(mode: .create) { _, _ in }
        .presentationDetents([.medium])
}

#Preview("Edit") {
    ThemeFormSheet(
        mode: .edit(
            Theme(
                id: UUID(),
                userID: UUID(),
                title: "Focus",
                description: "A sample description",
                active: true,
                archivedAt: nil,
                createdAt: Date()
            )
        ),
        onSave: { _, _ in },
        onArchive: {}
    )
    .presentationDetents([.medium])
}
#endif
