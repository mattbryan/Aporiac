import SwiftUI

/// List of thinking themes with create, edit, and archive flows.
struct ThemesView: View {
    @State private var viewModel = ThemeViewModel()
    @State private var showCreateSheet = false
    @State private var editingThemeID: UUID? = nil
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            PageTopBar(title: "Themes") {
                showCreateSheet = true
            }

            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    if viewModel.isLoading {
                        SiftSkeletonShimmer {
                            ForEach(0..<5, id: \.self) { _ in
                                SiftListRowSkeleton()
                                    .padding(.horizontal, DS.Spacing.md - 20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                            }
                        }
                    } else if viewModel.activeThemes.isEmpty {
                        Text("No themes yet.\nAdd one to start orienting your practice.")
                            .font(.siftCallout)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                            .padding(DS.Spacing.xxl)
                    } else {
                        ForEach(viewModel.activeThemes) { theme in
                            ThemeRow(theme: theme)
                                .onTapGesture {
                                    editingThemeID = theme.id
                                }
                        }
                    }

                    if !viewModel.isLoading && !viewModel.archivedThemes.isEmpty {
                        Button {
                            showArchived.toggle()
                        } label: {
                            HStack {
                                Text(showArchived ? "Hide archived" : "Show archived (\(viewModel.archivedThemes.count))")
                                    .font(.siftCallout)
                                    .foregroundStyle(Color.siftSubtle)
                                Spacer()
                                Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                    .font(.siftCaption)
                                    .foregroundStyle(Color.siftSubtle)
                            }
                        }
                        .padding(.vertical, DS.Spacing.md)
                        .buttonStyle(.plain)
                    }

                    if showArchived {
                        ForEach(viewModel.archivedThemes) { theme in
                            ThemeRow(theme: theme, archived: true)
                                .onTapGesture {
                                    editingThemeID = theme.id
                                }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .sheet(isPresented: $showCreateSheet) {
            ThemeFormSheet(mode: .create) { title, description in
                Task { try? await viewModel.create(title: title, description: description) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: editingThemeBinding) { theme in
            ThemeFormSheet(mode: .edit(theme)) { title, description in
                Task {
                    guard let current = currentTheme(for: theme.id) else { return }
                    try? await viewModel.update(theme: current, title: title, description: description)
                }
            } onArchive: {
                Task {
                    guard let current = currentTheme(for: theme.id) else { return }
                    if current.active {
                        try? await viewModel.archive(current)
                    } else {
                        try? await viewModel.unarchive(current)
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            await SupabaseService.shared.waitForCurrentUser()
            try? await viewModel.load()
        }
    }

    private var editingThemeBinding: Binding<Theme?> {
        Binding(
            get: {
                guard let id = editingThemeID else { return nil }
                return currentTheme(for: id)
            },
            set: { editingThemeID = $0?.id }
        )
    }

    private func currentTheme(for id: UUID) -> Theme? {
        viewModel.activeThemes.first(where: { $0.id == id })
            ?? viewModel.archivedThemes.first(where: { $0.id == id })
    }

    private struct ThemeRow: View {
        let theme: Theme
        var archived: Bool = false

        var body: some View {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(theme.title)
                        .font(.siftBody)
                        .foregroundStyle(archived ? Color.siftSubtle : Color.siftInk)
                    if let desc = theme.description, !desc.isEmpty {
                        Text(desc)
                            .font(.siftCallout)
                            .foregroundStyle(Color.siftSubtle)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }
    }
}

#if DEBUG
#Preview {
    ThemesView()
}
#endif
