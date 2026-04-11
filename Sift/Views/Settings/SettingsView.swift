import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("selectedPhilosophies") private var selectedPhilosophiesRaw: String = "stoicism"

    @AppStorage(AppColorSchemeOverride.storageKey)
    private var colorSchemeRaw: String = AppColorSchemeOverride.system.rawValue

    @State private var showDeleteConfirmation = false

    private var selectedPhilosophies: Set<Philosophy> {
        get {
            Set(selectedPhilosophiesRaw.split(separator: ",").compactMap { Philosophy(rawValue: String($0)) })
        }
        set {
            selectedPhilosophiesRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    private func togglePhilosophy(_ philosophy: Philosophy) {
        var next = selectedPhilosophies
        if next.contains(philosophy) {
            guard next.count > 1 else { return }
            next.remove(philosophy)
        } else {
            next.insert(philosophy)
        }
        selectedPhilosophiesRaw = next.map(\.rawValue).joined(separator: ",")
    }

    private var appearanceSelection: Binding<AppColorSchemeOverride> {
        Binding(
            get: { AppColorSchemeOverride(rawValue: colorSchemeRaw) ?? .system },
            set: { colorSchemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Each day, one of the schools of thought below shapes your entry prompt. Select the ones that resonate — the more you choose, the more variety you'll encounter.")
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Philosophy.allCases) { philosophy in
                        Button {
                            togglePhilosophy(philosophy)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: DS.Spacing.xs / 2) {
                                    Text(philosophy.title)
                                        .font(.siftBody)
                                        .foregroundStyle(Color.siftInk)
                                    Text(philosophy.description)
                                        .font(.siftCallout)
                                        .foregroundStyle(Color.siftSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: DS.Spacing.sm)
                                if selectedPhilosophies.contains(philosophy) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.siftAccent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DS.Spacing.md)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(Color.siftDivider, lineWidth: 1)
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            } header: {
                Text("Philosophies")
            }

            Section {
                Picker("Appearance", selection: appearanceSelection) {
                    ForEach(AppColorSchemeOverride.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Design system")
            } footer: {
                Text("Override light or dark mode to test adaptive colors. System follows your device setting.")
            }

            Section {
                Button("Sign Out") {
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        try? await SupabaseService.shared.signOut()
                    }
                }
                .foregroundStyle(Color.siftInk)

                Button("Delete Account", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } header: {
                Text("Account")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    try? await SupabaseService.shared.deleteAccount()
                }
            }
        } message: {
            Text("This will permanently delete your account and all data. This cannot be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
