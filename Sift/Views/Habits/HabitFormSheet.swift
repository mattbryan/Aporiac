import SwiftUI

/// Form for creating a habit or editing an existing one.
struct HabitFormSheet: View {
    enum HabitFormMode {
        case create
        case edit(Habit)
    }

    let mode: HabitFormMode
    let onSave: (String, String, String) -> Void
    var onArchive: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var fullCriteria: String = ""
    @State private var partialCriteria: String = ""
    @Environment(\.dismiss) private var dismiss

    private var sheetTitle: String {
        switch mode {
        case .create:
            "New habit"
        case .edit:
            "Edit habit"
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFull: String {
        fullCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPartial: String {
        partialCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !trimmedFull.isEmpty && !trimmedPartial.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sheetTitle)
                .font(.siftHeadline)
                .foregroundStyle(Color.siftInk)
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)

            Text("Title")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .padding(.horizontal, 20)
            TextField("What do you want to build?", text: $title)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .padding(DS.Spacing.md)
                .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.md)

            Text("Full credit")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .padding(.horizontal, 20)
            TextField("What does a complete day look like?", text: $fullCriteria, axis: .vertical)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .lineLimit(2...4)
                .padding(DS.Spacing.md)
                .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.md)

            Text("Partial credit")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)
                .padding(.horizontal, 20)
            TextField("What earns half credit?", text: $partialCriteria, axis: .vertical)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .lineLimit(2...4)
                .padding(DS.Spacing.md)
                .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.sm)

            Spacer()

            Button {
                onSave(trimmedTitle, trimmedFull, trimmedPartial)
                dismiss()
            } label: {
                Text("Save")
                    .font(.siftBodyMedium)
                    .foregroundStyle(Color.siftSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        canSave ? Color.siftInk : Color.siftInk.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: DS.Radius.md)
                    )
            }
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.bottom, DS.Spacing.sm)

            if let onArchive {
                Button {
                    onArchive()
                    dismiss()
                } label: {
                    Text("Archive habit")
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftSubtle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.siftSurface)
        .onAppear {
            if case .edit(let habit) = mode {
                title = habit.title
                fullCriteria = habit.fullCriteria
                partialCriteria = habit.partialCriteria
            }
        }
    }
}

#if DEBUG
#Preview("Create") {
    HabitFormSheet(mode: .create) { _, _, _ in }
        .presentationDetents([.large])
}

#Preview("Edit") {
    HabitFormSheet(
        mode: .edit(
            Habit(
                id: UUID(),
                userID: UUID(),
                title: "Write daily",
                fullCriteria: "750 words",
                partialCriteria: "Any words",
                active: true,
                archivedAt: nil,
                createdAt: Date()
            )
        ),
        onSave: { _, _, _ in },
        onArchive: {}
    )
    .presentationDetents([.large])
}
#endif
