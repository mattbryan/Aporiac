import SwiftUI
import UIKit

/// Which entry the writing surface should load.
enum EntryDestination: Sendable, Equatable {
    case today
    /// `calendarDay` is used for the header while the entry row loads (and should match that row's `created_at` day).
    case past(entryID: UUID, calendarDay: Date)
}

enum ReviewContext: Sendable {
    case theme
    case habit
    case combined
}

struct EntryView: View {
    var destination: EntryDestination = .today
    var reviewContext: ReviewContext? = nil
    var onReviewComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = EntryViewModel()

    /// Whether the ENTRY section is unlocked. False = show "Start Entry" button. True = show editor.
    @State private var entryStarted: Bool = false

    @FocusState private var gratitudeEditorFocused: Bool

    private let contentTransformTrigger = MarkdownTransformTrigger()

    private var entryBodyOpacity: Double {
        guard case .past(_, let calendarDay) = destination else { return 1.0 }
        let today = Calendar.current.startOfDay(for: Date())
        let entryDay = Calendar.current.startOfDay(for: calendarDay)
        let days = Calendar.current.dateComponents([.day], from: entryDay, to: today).day ?? 0
        return DS.entryBodyOpacity(daysAgo: max(days, 0))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
            // MARK: Entry surface
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if viewModel.isEntryContentLoading {
                        SiftSkeletonShimmer { preEntrySkeleton }
                    } else {
                        // GRATITUDE — always visible
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("GRATITUDE")
                                .siftTextStyle(.microBold)
                                .foregroundStyle(Color.siftAccent)
                            Text("I'm grateful for...")
                                .siftTextStyle(.h2Bold)
                                .foregroundStyle(Color.siftInk)
                        }
                        RichTextEditor(
                            text: $viewModel.gratitudeText,
                            placeholder: "What are you grateful for today?",
                            textColor: .siftInk.opacity(entryBodyOpacity),
                            listMode: .bullet,
                            onSelectionChanged: { _, _ in }
                        )
                        .focused($gratitudeEditorFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle()
                            .fill(Color.siftDivider)
                            .frame(maxWidth: .infinity)
                            .frame(height: 2)

                        if !viewModel.activeThemes.isEmpty {
                            // THEMES — visible only when the user has at least one active theme.
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("THEMES")
                                    .siftTextStyle(.microBold)
                                    .foregroundStyle(Color.siftAccent)
                                Text("Today's Focus")
                                    .siftTextStyle(.h2Bold)
                                    .foregroundStyle(Color.siftInk)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DS.Spacing.xs) {
                                    ForEach(viewModel.activeThemes) { theme in
                                        ThemeToggleButton(
                                            title: theme.title,
                                            isActive: viewModel.selectedThemeIDs.contains(theme.id),
                                            action: { viewModel.toggleTheme(theme.id) }
                                        )
                                    }
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle()
                                .fill(Color.siftDivider)
                                .frame(maxWidth: .infinity)
                                .frame(height: 2)
                        }

                        // ENTRY — toggled by entryStarted
                        if entryStarted {
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                Text("ENTRY")
                                    .siftTextStyle(.microBold)
                                    .foregroundStyle(Color.siftAccent)
                                MarkdownTextEditor(
                                    text: $viewModel.contentText,
                                    placeholder: viewModel.dailyPrompt,
                                    textColor: .siftInk,
                                    bodyOpacity: entryBodyOpacity,
                                    trigger: contentTransformTrigger,
                                    onSelectionChanged: nil
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            // Start Entry button
                            Button {
                                gratitudeEditorFocused = false
                                Task {
                                    await viewModel.prepareWritingPhase()
                                    withAnimation(DS.animationSlow) {
                                        entryStarted = true
                                    }
                                }
                            } label: {
                                Text("Start Entry")
                                    .font(.siftBodyMedium)
                                    .foregroundStyle(Color.siftInk)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .buttonStyle(.plain)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.xs)
                                    .strokeBorder(Color.siftAccent, lineWidth: 2)
                            )
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.siftSurface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await viewModel.saveNow()
                            onReviewComplete?()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.siftInk)
                            .frame(width: 40, height: 40)
                    }
                }
            }
        }
        .task {
            await SupabaseService.shared.waitForCurrentUser()
            if let context = reviewContext {
                viewModel.reviewPrompt = reviewPromptText(for: context)
            }
            switch destination {
            case .today:
                await viewModel.loadOrCreateTodayEntry()
                let hasContent = !viewModel.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasContent || reviewContext != nil {
                    await viewModel.prepareWritingPhase()
                    entryStarted = true
                }
            case .past(let id, _):
                await viewModel.loadEntry(id: id)
                entryStarted = true
            }
        }
        .onChange(of: viewModel.gratitudeText) { viewModel.scheduleAutosave() }
        .onChange(of: viewModel.contentText) { viewModel.scheduleAutosave() }
        .onReceive(NotificationCenter.default.publisher(for: .siftActionCompletionChanged)) { notification in
            guard
                let content = notification.userInfo?["actionContent"] as? String,
                let completed = notification.userInfo?["completed"] as? Bool,
                let entryID = notification.userInfo?["entryID"] as? UUID,
                entryID == viewModel.currentEntry?.id
            else { return }

            viewModel.applyActionCompletionUpdate(content: content, completed: completed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftEntryBodyUpdatedFromDayView)) { note in
            guard let entryID = note.object as? UUID else { return }
            Task { await viewModel.reloadCurrentEntryBodyFromServerIfNeeded(entryID: entryID) }
        }
    }

    /// Placeholder layout while the entry payload loads.
    private var preEntrySkeleton: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                SiftSkeletonLine(height: 11, widthFraction: 0.28)
                SiftSkeletonLine(height: 24, widthFraction: 0.72)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(0..<3, id: \.self) { i in
                    SiftSkeletonLine(height: 16, widthFraction: i == 2 ? 0.55 : 1)
                }
            }
            SiftSkeletonBlock(height: 2, width: nil)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                SiftSkeletonLine(height: 11, widthFraction: 0.22)
                SiftSkeletonLine(height: 24, widthFraction: 0.48)
            }
            HStack(spacing: DS.Spacing.xs) {
                SiftSkeletonBlock(height: 32, width: 72)
                SiftSkeletonBlock(height: 32, width: 88)
                SiftSkeletonBlock(height: 32, width: 64)
            }
            SiftSkeletonBlock(height: 2, width: nil)
            SiftSkeletonLine(height: 44, widthFraction: 1)
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func reviewPromptText(for context: ReviewContext) -> String {
        switch context {
        case .theme:
            return "It's been 90 days. Take a few minutes to reflect on your themes. Are they still the right orientations for where you are? What have you learned about yourself through them? What would you change, retire, or carry forward?"
        case .habit:
            return "It's been 14 days. Look honestly at your habits. Which ones are serving you? Which feel like obligation rather than intention? What would it look like to adjust, retire, or recommit?"
        case .combined:
            return "Time to step back and look at the bigger picture. Reflect on your themes — are they still the right orientations? Then look at your habits — are they in service of those themes? What would you change, retire, or carry forward into the next season?"
        }
    }
}

// MARK: - Theme toggle

/// Capsule chip for toggling an active theme on the entry screen.
private struct ThemeToggleButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isActive ? .siftCaptionBold : .siftCaption)
                .foregroundStyle(isActive ? Color.siftInk : Color.siftSubtle)
                .tracking(isActive ? SiftTracking.captionBold : SiftTracking.captionRegular)
                .padding(.vertical, 4)
                .padding(.horizontal, DS.Spacing.sm)
                .background(isActive ? Color.siftCard : Color.clear, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.siftDivider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EntryView()
}
