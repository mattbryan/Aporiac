import SwiftUI

/// Searchable list of saved gems with optional theme filtering.
struct GemsView: View {
    @State private var viewModel = GemViewModel()
    @State private var openSwipeRowKey: String?
    @State private var gemNavigationPath = NavigationPath()

    private var emptyMessage: String {
        if viewModel.gemsWithThemes.isEmpty {
            "Nothing kept yet.\nFlag a gem from any entry."
        } else {
            "No gems match."
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $gemNavigationPath) {
            gemsRootContent(viewModel: viewModel)
                .navigationDestination(for: UUID.self) { gemID in
                    GemDetailView(gemID: gemID, navigationPath: $gemNavigationPath)
                }
        }
    }

    @ViewBuilder
    private func gemsRootContent(viewModel: GemViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gems")
                    .siftTextStyle(.h1Bold)
                    .foregroundStyle(Color.siftInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.siftSubtle)
                    .font(.siftCallout)
                TextField("Search gems...", text: $viewModel.searchText)
                    .font(.siftBody)
                    .foregroundStyle(Color.siftInk)
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.sm)
            .background(Color.siftInk.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.sm)

            if !viewModel.allThemes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        themeChip(title: "All", selected: viewModel.selectedThemeID == nil) {
                            viewModel.selectedThemeID = nil
                        }
                        ForEach(viewModel.allThemes) { theme in
                            let selected = viewModel.selectedThemeID == theme.id
                            themeChip(title: theme.title, selected: selected) {
                                if selected {
                                    viewModel.selectedThemeID = nil
                                } else {
                                    viewModel.selectedThemeID = theme.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                }
                .scrollClipDisabled()
                .padding(.bottom, DS.Spacing.xs)
            }

            ZStack {
                if viewModel.isLoading {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            SiftSkeletonShimmer {
                                ForEach(0..<6, id: \.self) { _ in
                                    GemCardSkeleton()
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.screenEdge)
                        .padding(.top, DS.Spacing.xs)
                    }
                } else if viewModel.filteredGems.isEmpty {
                    VStack(spacing: DS.Spacing.md) {
                        Text(emptyMessage)
                            .font(.siftCallout)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(viewModel.filteredGems) { gemWithThemes in
                                SwipeRevealRow(
                                    rowKey: HomeSwipeRowKeys.gem(gemWithThemes.gem.id),
                                    openRowKey: $openSwipeRowKey,
                                    leadingWidth: 0,
                                    trailingWidth: HomeScreenLayout.swipeActionButtonWidth,
                                    allowsFullSwipeLeading: false,
                                    allowsFullSwipeTrailing: true,
                                    contentBackdrop: Color.siftSurface,
                                    onFullSwipeLeading: nil,
                                    onFullSwipeTrailing: {
                                        openSwipeRowKey = nil
                                        Task { await viewModel.removeGem(id: gemWithThemes.gem.id) }
                                    },
                                    leading: { Color.clear },
                                    trailing: {
                                        Button {
                                            openSwipeRowKey = nil
                                            Task { await viewModel.removeGem(id: gemWithThemes.gem.id) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundStyle(Color.siftContrastLight)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .background(Color.siftDelete)
                                    }
                                ) {
                                    NavigationLink(value: gemWithThemes.gem.id) {
                                        GemsPageGemRow(item: gemWithThemes)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .id(gemWithThemes.gem.id)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.screenEdge)
                        .padding(.top, DS.Spacing.xs)
                        .padding(.bottom, DS.Spacing.sm)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color.siftSurface.ignoresSafeArea())
            .onReceive(NotificationCenter.default.publisher(for: .siftJournalEntitiesDidSync)) { _ in
                Task { try? await viewModel.load(showLoadingState: false) }
            }
            .task {
                while SupabaseService.shared.currentUser == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await viewModel.load()
            }
    }

    private func themeChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.siftCaption)
                .foregroundStyle(selected ? Color.siftSurface : Color.siftInk)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.md)
                .background(selected ? Color.siftInk : Color.siftInk.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    GemsView()
}
#endif
