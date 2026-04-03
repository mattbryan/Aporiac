import SwiftUI
import UIKit

/// Which entry the writing surface should load.
enum EntryDestination: Sendable {
    case today
    /// `calendarDay` is used for the header while the entry row loads (and should match that row's `created_at` day).
    case past(entryID: UUID, calendarDay: Date)
}

struct EntryView: View {
    var destination: EntryDestination = .today

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = EntryViewModel()

    @State private var hasSelection = false
    @State private var activeSection: EntrySection = .gratitude
    private let gratitudeTrigger = HighlightTrigger()
    private let contentTrigger = HighlightTrigger()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header
            HStack {
                Button {
                    Task {
                        await viewModel.saveNow()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.siftSubtle)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, DS.Spacing.md)
            .padding(.top, DS.Spacing.sm)

            // MARK: Writing surface
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entryHeaderDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.siftCaption)
                        .foregroundStyle(Color.siftSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)

                    RichTextEditor(
                        text: $viewModel.gratitudeText,
                        highlights: $viewModel.gratitudeHighlights,
                        placeholder: "Today, I'm grateful for...",
                        textColor: .siftInk,
                        listMode: .bullet,
                        trigger: gratitudeTrigger,
                        onSelectionChanged: { selected in
                            if selected { activeSection = .gratitude }
                            hasSelection = selected
                        },
                        onHighlightAdded: { viewModel.addHighlight($0, section: .gratitude) }
                    )
                    .padding(.horizontal, DS.Spacing.md)

                    Divider()
                        .background(Color.siftDivider)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)

                    RichTextEditor(
                        text: $viewModel.contentText,
                        highlights: $viewModel.contentHighlights,
                        placeholder: viewModel.dailyPrompt,
                        textColor: .siftInk,
                        trigger: contentTrigger,
                        onSelectionChanged: { selected in
                            if selected { activeSection = .content }
                            hasSelection = selected
                        },
                        onHighlightAdded: { viewModel.addHighlight($0, section: .content) }
                    )
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, viewModel.completedActionsForEntry.isEmpty ? DS.Spacing.xl : 0)

                    if !viewModel.completedActionsForEntry.isEmpty {
                        Divider()
                            .background(Color.siftDivider)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)

                        Text("Completed actions")
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftSubtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.bottom, DS.Spacing.xs)

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            ForEach(viewModel.completedActionsForEntry) { action in
                                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                                    ZStack {
                                        Circle()
                                            .strokeBorder(Color.siftSubtle, lineWidth: 1.5)
                                            .opacity(0)
                                        Circle()
                                            .fill(Color.siftGem)
                                    }
                                    .frame(width: 24, height: 24)

                                    Text(action.content)
                                        .font(.siftBody)
                                        .foregroundStyle(Color.siftSubtle)
                                        .strikethrough()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(DS.Spacing.sm)
                                .background(Color.white, in: Capsule())
                                .padding(.horizontal, DS.Spacing.md)
                            }
                        }
                        .padding(.bottom, DS.Spacing.xl)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            highlightToolbar
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .task {
            while SupabaseService.shared.currentUser == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            switch destination {
            case .today:
                await viewModel.loadOrCreateTodayEntry()
            case .past(let id, _):
                await viewModel.loadEntry(id: id)
            }
        }
        .onChange(of: viewModel.gratitudeText) { viewModel.scheduleAutosave() }
        .onChange(of: viewModel.contentText) { viewModel.scheduleAutosave() }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingThemePickerGemID != nil },
            set: { if !$0 { viewModel.dismissThemePicker() } }
        )) {
            ThemePickerSheet(
                themes: viewModel.gemViewModel.allThemes,
                onSelect: { themeID in
                    Task { await viewModel.associateTheme(themeID: themeID) }
                },
                onDismiss: { viewModel.dismissThemePicker() }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Toolbar

    @ViewBuilder
    private var highlightToolbar: some View {
        VStack(spacing: 0) {
            if hasSelection {
                HStack(spacing: DS.Spacing.sm) {
                    toolbarButton(label: "Gem", color: Color.siftGem) {
                        activeTrigger.fire(.gem)
                    }
                    toolbarButton(label: "Action", color: Color.siftAction) {
                        activeTrigger.fire(.action)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.bottom, homeIndicatorInset)
                .background(Color.siftSurface)
                .overlay(alignment: .top) {
                    Divider().background(Color.siftDivider)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.animationSlow, value: hasSelection)
    }

    private func toolbarButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.siftBodyMedium)
                .foregroundStyle(color)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var activeTrigger: HighlightTrigger {
        activeSection == .gratitude ? gratitudeTrigger : contentTrigger
    }

    /// Shown above the editor — uses loaded entry metadata when available so past days are not labeled as today.
    private var entryHeaderDate: Date {
        if let created = viewModel.currentEntry?.createdAt {
            return created
        }
        switch destination {
        case .today:
            return Date.now
        case .past(_, let calendarDay):
            return calendarDay
        }
    }

    /// Bottom safe area (home indicator) for toolbar padding; not affected by keyboard.
    private var homeIndicatorInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let window = (scenes.first as? UIWindowScene)?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }
}

// MARK: - Theme picker sheet

/// Bottom sheet to optionally connect a newly flagged gem to an active theme.
/// Extract to `ThemePickerSheet.swift` when you add that file to the Xcode target.
private struct ThemePickerSheet: View {
    let themes: [Theme]
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Add to a theme")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)

            Text("Optional")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle.opacity(0.72))

            if themes.isEmpty {
                Text("No active themes yet")
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftSubtle)
                    .padding(.top, DS.Spacing.xs)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(themes) { theme in
                            Button {
                                onSelect(theme.id)
                            } label: {
                                Text(theme.title)
                                    .font(.siftCallout)
                                    .foregroundStyle(Color.siftInk)
                                    .padding(.vertical, DS.Spacing.xs)
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .background(Color.siftGem.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Text("Skip")
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(Color.siftSurface)
    }
}

#Preview {
    EntryView()
}
