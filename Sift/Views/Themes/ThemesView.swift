import SwiftUI

/// List of thinking themes with create, edit, and archive flows.
struct ThemesView: View {
    @State private var viewModel = ThemeViewModel()
    @State private var showCreateSheet = false
    @State private var editingTheme: Theme? = nil
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Themes")
                    .siftTextStyle(.h1Medium)
                    .foregroundStyle(Color.siftInk)
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.siftInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, DS.Spacing.md)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.isLoading {
                        SiftSkeletonShimmer {
                            ForEach(0..<5, id: \.self) { _ in
                                SiftListRowSkeleton()
                                Rectangle()
                                    .fill(Color.siftDivider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
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
                                    editingTheme = theme
                                }
                            Rectangle()
                                .fill(Color.siftDivider)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, DS.Spacing.md)
                        .buttonStyle(.plain)
                    }

                    if showArchived {
                        ForEach(viewModel.archivedThemes) { theme in
                            ThemeRow(theme: theme, archived: true)
                            Rectangle()
                                .fill(Color.siftDivider)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
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
        .sheet(item: $editingTheme) { theme in
            ThemeFormSheet(mode: .edit(theme)) { title, description in
                Task { try? await viewModel.update(theme: theme, title: title, description: description) }
            } onArchive: {
                Task { try? await viewModel.archive(theme) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            while SupabaseService.shared.currentUser == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await viewModel.load()
        }
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
                if !archived {
                    Image(systemName: "chevron.right")
                        .font(.siftCaption)
                        .foregroundStyle(Color.siftSubtle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, DS.Spacing.md)
            .contentShape(Rectangle())
        }
    }
}

#if DEBUG
#Preview {
    ThemesView()
}
#endif
