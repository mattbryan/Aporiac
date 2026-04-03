import SwiftUI

/// Searchable list of saved gems with optional theme filtering.
struct GemsView: View {
    @State private var viewModel = GemViewModel()

    private var emptyMessage: String {
        if viewModel.gemsWithThemes.isEmpty {
            "Nothing kept yet.\nFlag a gem from any entry."
        } else {
            "No gems match."
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            HStack {
                Text("Gems")
                    .font(.siftTitle)
                    .foregroundStyle(Color.siftInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, DS.Spacing.xs)
            }

            ZStack {
                if viewModel.filteredGems.isEmpty {
                    VStack(spacing: DS.Spacing.md) {
                        Text(emptyMessage)
                            .font(.siftCallout)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.filteredGems) { gemWithThemes in
                                GemCard(item: gemWithThemes)
                                Divider()
                                    .background(Color.siftDivider)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .task {
            while SupabaseService.shared.currentUser == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await viewModel.load()
        }
        .onAppear {
            Task {
                try? await viewModel.load()
            }
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
