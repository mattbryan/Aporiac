import SwiftUI

/// Minimal sheet for creating a new action item from the compose menu.
/// Inserts the action into Supabase and appends it to today's entry body.
struct QuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @FocusState private var isFocused: Bool

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text("New Action")
                .siftTextStyle(.h2Medium)
                .foregroundStyle(Color.siftInk)
                .padding(.top, DS.Spacing.lg)

            TextField("What do you want to do?", text: $content, axis: .vertical)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .tint(Color.siftAccent)
                .lineLimit(1...4)
                .focused($isFocused)
                .padding(DS.Spacing.md)
                .background(
                    Color.siftInk.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                )
                .submitLabel(.done)
                .onSubmit {
                    guard !trimmedContent.isEmpty else { return }
                    save()
                }

            Spacer()

            Button {
                save()
            } label: {
                Text("Save")
                    .font(.siftBodyMedium)
                    .foregroundStyle(Color.siftSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.ButtonHeight.large)
                    .background(
                        trimmedContent.isEmpty ? Color.siftInk.opacity(0.3) : Color.siftInk,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    )
            }
            .disabled(trimmedContent.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.siftSurface)
        .onAppear { isFocused = true }
    }

    private func save() {
        let text = trimmedContent
        guard !text.isEmpty else { return }
        dismiss()
        Task {
            try? await SupabaseService.shared.createQuickAction(content: text)
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
        }
    }
}

#Preview {
    QuickActionSheet()
        .presentationDetents([.height(260)])
}
