import SwiftUI

/// Card showing one gem (editable fragment), date, and linked themes.
struct GemCard: View {
    let item: GemWithThemes
    @FocusState.Binding var focusedField: UUID?
    let onFragmentChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            GemEditableFragmentRow(
                item: item,
                font: .siftBody,
                focusedField: $focusedField,
                onFragmentChange: onFragmentChange
            )

            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                Text(item.gem.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)

                if !item.themes.isEmpty {
                    ForEach(item.themes) { theme in
                        Text(theme.title)
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftAccent)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(Color.siftActionTint, in: Capsule())
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

/// Day summary gem row: gem marker, fragment, theme chips (Figma day component).
struct DaySummaryGemCard: View {
    let item: GemWithThemes

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            ZStack {
                DiamondShape()
                    .fill(Color.siftGem.opacity(0.2))
                DiamondShape()
                    .fill(Color.siftGem)
                    .scaleEffect(0.45)
            }
            .frame(width: 20, height: 20)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(item.gem.content)
                    .font(.siftBody)
                    .foregroundStyle(Color.siftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.themes.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(item.themes) { theme in
                            Text(theme.title)
                                .font(.siftCaption)
                                .foregroundStyle(Color.siftAccent)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(Color.siftActionTint, in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .strokeBorder(Color.siftDivider.opacity(0.85), lineWidth: 1)
        )
    }
}

/// Gems page row: accent bar, fragment preview (2 lines), date and theme chips.
struct GemsPageGemRow: View {
    let item: GemWithThemes

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.siftGem)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(item.gem.content)
                    .font(.siftBody)
                    .foregroundStyle(Color.siftInk)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    Text(item.gem.createdAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.siftCaption)
                        .foregroundStyle(Color.siftSubtle)

                    if !item.themes.isEmpty {
                        ForEach(item.themes) { theme in
                            Text(theme.title)
                                .font(.siftCaption)
                                .foregroundStyle(Color.siftAccent)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(Color.siftActionTint, in: Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, DS.Spacing.md)
            .padding(.horizontal, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.siftCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
    }
}

/// Inspects one gem: formatted date and share/delete in the toolbar, theme links, plain text body.
struct GemDetailView: View {
    let gemID: UUID
    @Binding var navigationPath: NavigationPath
    /// Set to `true` when presented as a sheet rather than pushed onto a navigation stack.
    /// Shows a close button and auto-focuses the text field after loading.
    var isSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var item: GemWithThemes?
    @State private var allThemes: [Theme] = []
    @State private var showDeleteConfirmation = false
    @State private var fragmentText: String = ""
    @FocusState private var fragmentFieldFocused: Bool

    var body: some View {
        Group {
            if isLoading {
                ScrollView {
                    SiftSkeletonShimmer {
                        GemDetailSkeleton()
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.md)
                }
            } else if let item {
                detailContent(item: item)
            } else {
                Text("Gem not found.")
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftSubtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.siftSubtle)
                    }
                }
            }
            if let item, !isLoading {
                ToolbarItem(placement: .principal) {
                    Text(item.gem.createdAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: DS.Spacing.md) {
                        ShareLink(item: fragmentText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.siftInk)
                        }
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.siftInk)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete this gem?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Gem", role: .destructive) {
                Task { await confirmDeleteGem() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: gemID) {
            await load()
            if isSheet {
                fragmentFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func detailContent(item: GemWithThemes) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                themeCarouselSection(for: item)
                TextField(
                    "",
                    text: Binding(
                        get: { fragmentText },
                        set: { newValue in
                            fragmentText = newValue
                            onFragmentTextChanged(newValue)
                        }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.siftBody)
                .foregroundStyle(Color.siftInk)
                .tint(Color.siftGem)
                .lineLimit(1...80)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .focused($fragmentFieldFocused)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: item.gem.content) { _, newValue in
            guard !fragmentFieldFocused else { return }
            guard newValue != fragmentText else { return }
            fragmentText = newValue
        }
    }

    /// Debounced persist into the entry body + `gems` row; notifies lists when the save completes.
    private func onFragmentTextChanged(_ newValue: String) {
        guard var current = item else { return }
        current.gem.content = newValue
        item = current
        SupabaseService.shared.scheduleGemFragmentSave(gemID: gemID, content: newValue) {
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
        }
    }

    @ViewBuilder
    private func themeCarouselSection(for item: GemWithThemes) -> some View {
        let linkedIDs = Set(item.themes.map(\.id))
        let addable = allThemes.filter { !linkedIDs.contains($0.id) }

        if item.themes.isEmpty, addable.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(item.themes) { theme in
                        linkedThemePill(theme: theme)
                    }
                    ForEach(addable) { theme in
                        addThemeChip(theme: theme)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func linkedThemePill(theme: Theme) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(theme.title)
                .font(.siftCaption)
                .foregroundStyle(Color.siftAccent)
            Button {
                Task { await removeThemeLink(themeID: theme.id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.siftSubtle)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.siftActionTint, in: Capsule())
    }

    private func addThemeChip(theme: Theme) -> some View {
        Button {
            Task { await addThemeLink(theme: theme) }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.siftAccent)
                Text(theme.title)
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftInk)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(Color.siftInk.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let gemTask = SupabaseService.shared.fetchGemWithThemes(gemID: gemID)
            async let themesTask = SupabaseService.shared.fetchActiveThemes()
            let gem = try await gemTask
            let themes = try await themesTask
            allThemes = themes
            if let gem {
                item = gem
                fragmentText = gem.gem.content
            } else {
                item = nil
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }
        } catch {
            print("[GemDetail] load failed: \(error)")
            item = nil
        }
    }

    private func confirmDeleteGem() async {
        do {
            try await SupabaseService.shared.deleteGem(id: gemID)
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
            dismiss()
        } catch {
            print("[GemDetail] delete failed: \(error)")
        }
    }

    private func removeThemeLink(themeID: UUID) async {
        guard var current = item else { return }
        do {
            try await SupabaseService.shared.removeGemThemeLink(gemID: gemID, themeID: themeID)
            current.themes.removeAll { $0.id == themeID }
            item = current
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
        } catch {
            print("[GemDetail] remove theme link failed: \(error)")
        }
    }

    private func addThemeLink(theme: Theme) async {
        guard var current = item else { return }
        if current.themes.contains(where: { $0.id == theme.id }) { return }
        do {
            try await SupabaseService.shared.addGemThemeLink(gemID: gemID, themeID: theme.id)
            current.themes.append(theme)
            item = current
            NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
        } catch {
            print("[GemDetail] add theme link failed: \(error)")
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @FocusState var focused: UUID?
    GemCard(
        item: GemWithThemes(
            gem: Gem(
                id: UUID(),
                userID: UUID(),
                entryID: UUID(),
                content: "A fragment worth keeping from the entry.",
                rangeStart: 0,
                rangeEnd: 10,
                createdAt: .now
            ),
            themes: []
        ),
        focusedField: $focused,
        onFragmentChange: { _ in }
    )
}
#endif
