import SwiftUI

private enum MainTab: Int, Hashable {
    case today = 0
    case gems
    case themes
    case habits
}

// MARK: - Compose accessory

/// Native `tabViewBottomAccessory` compose control.
/// Closures are injected by `MainAppView` so each action can reach app-level state.
private struct MainTabBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    var onNewEntry: () -> Void
    var onNewGem: () -> Void
    var onNewTheme: () -> Void
    var onNewHabit: () -> Void
    var onNewAction: () -> Void

    private var isInline: Bool { accessoryPlacement == .inline }

    var body: some View {
        Menu {
            Button { onNewEntry() } label: {
                Label("Today's Entry", image: "TabToday")
            }
            Button { onNewGem() } label: {
                Label("New Gem", image: "TabGems")
            }
            Button { onNewTheme() } label: {
                Label("New Theme", image: "TabThemes")
            }
            Button { onNewHabit() } label: {
                Label("New Habit", image: "TabHabits")
            }
            Button { onNewAction() } label: {
                Label("New Action", systemImage: "checkmark.circle")
            }
        } label: {
            Image("ComposePlus")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: isInline ? 17 : 20, height: isInline ? 17 : 20)
                .frame(
                    width: isInline ? DS.ButtonHeight.medium : DS.ButtonHeight.large,
                    height: isInline ? DS.ButtonHeight.medium : DS.ButtonHeight.large
                )
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Auth Gate

/// Routes to splash, onboarding, or the main app based on auth state.
private struct AuthGateView: View {
    var body: some View {
        Group {
            if !SupabaseService.shared.isAuthReady {
                Color.siftSurface.ignoresSafeArea()
            } else if SupabaseService.shared.currentUser == nil {
                OnboardingView()
            } else {
                MainAppView()
            }
        }
        .task {
            await SupabaseService.shared.initialize()
            if SupabaseService.shared.isAuthenticated {
                await SupabaseService.shared.purgeExpiredEntries()
            }
        }
    }
}

// MARK: - Main App

/// Identifiable wrapper so a gem UUID can drive `sheet(item:)`.
private struct GemSheetItem: Identifiable {
    let id: UUID
}

/// The authenticated app shell — tab bar, review triggers, and all primary navigation.
private struct MainAppView: View {
    @State private var selectedTab: MainTab = .today
    @State private var showThemeReview = false
    @State private var showHabitReview = false
    @State private var bothReviewsDue = false

    // Compose menu sheet state
    @State private var showNewEntry = false
    @State private var gemSheetItem: GemSheetItem?
    @State private var showNewTheme = false
    @State private var showNewHabit = false
    @State private var showNewAction = false

    // ViewModels owned here so theme/habit creation works from any tab
    @State private var themeViewModel = ThemeViewModel()
    @State private var habitViewModel = HabitViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", image: "TabToday", value: MainTab.today) {
                HomeView()
            }
            Tab("Gems", image: "TabGems", value: MainTab.gems) {
                GemsView()
            }
            Tab("Themes", image: "TabThemes", value: MainTab.themes) {
                ThemesView()
            }
            Tab("Habits", image: "TabHabits", value: MainTab.habits) {
                HabitsView()
            }
        }
        .tint(Color.siftAccent)
        .defaultAdaptableTabBarPlacement(.tabBar)
        // Avoid minimize-on-scroll: multiline editors (gem fragments) change content height and can
        // disturb scroll metrics, dismissing the keyboard. See IOS_PATTERNS.md (Tab bar minimize).
        .tabBarMinimizeBehavior(.never)
        .tabViewBottomAccessory {
            MainTabBottomAccessory(
                onNewEntry: { showNewEntry = true },
                onNewGem: {
                    Task {
                        if let gemID = try? await SupabaseService.shared.createQuickGem() {
                            gemSheetItem = GemSheetItem(id: gemID)
                        }
                    }
                },
                onNewTheme: { showNewTheme = true },
                onNewHabit: { showNewHabit = true },
                onNewAction: { showNewAction = true }
            )
        }
        // MARK: Compose sheets
        .fullScreenCover(isPresented: $showNewEntry) {
            EntryView()
        }
        .sheet(item: $gemSheetItem) { item in
            NavigationStack {
                GemDetailView(
                    gemID: item.id,
                    navigationPath: .constant(NavigationPath()),
                    isSheet: true
                )
            }
        }
        .sheet(isPresented: $showNewTheme) {
            ThemeFormSheet(mode: .create) { title, description in
                Task {
                    try? await themeViewModel.create(title: title, description: description)
                    NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewHabit) {
            HabitFormSheet(mode: .create) { title, full, partial in
                Task {
                    try? await habitViewModel.create(title: title, fullCriteria: full, partialCriteria: partial)
                    NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewAction) {
            QuickActionSheet()
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        // MARK: Review covers
        .fullScreenCover(isPresented: $showThemeReview) {
            EntryView(
                destination: .today,
                reviewContext: bothReviewsDue ? .combined : .theme,
                onReviewComplete: {
                    Task {
                        try? await SupabaseService.shared.updateLastThemeReview()
                        if bothReviewsDue {
                            try? await SupabaseService.shared.updateLastHabitReview()
                        }
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showHabitReview) {
            EntryView(
                destination: .today,
                reviewContext: .habit,
                onReviewComplete: {
                    Task { try? await SupabaseService.shared.updateLastHabitReview() }
                }
            )
        }
        .task {
            await checkReviewTriggers()
        }
    }

    private func checkReviewTriggers() async {
        guard let settings = try? await SupabaseService.shared.fetchOrCreateUserSettings() else { return }
        let now = Date()

        let ninetyDays: TimeInterval = 90 * 24 * 60 * 60
        let fourteenDays: TimeInterval = 14 * 24 * 60 * 60

        // Only prompt if the timer has elapsed AND the user actually has qualifying data.
        let timerThemesDue = settings.lastThemeReview.map { now.timeIntervalSince($0) >= ninetyDays } ?? false
        let timerHabitsDue = settings.lastHabitReview.map { now.timeIntervalSince($0) >= fourteenDays } ?? false

        async let hasThemeAsync = SupabaseService.shared.hasActiveThemeOlderThan(ninetyDays)
        async let hasHabitAsync = SupabaseService.shared.hasActiveHabitOlderThan(fourteenDays)

        let (hasTheme, hasHabit) = await (hasThemeAsync, hasHabitAsync)

        let themesDue = timerThemesDue && hasTheme
        let habitsDue = timerHabitsDue && hasHabit

        bothReviewsDue = false
        if themesDue && habitsDue {
            bothReviewsDue = true
            showThemeReview = true
        } else if themesDue {
            showThemeReview = true
        } else if habitsDue {
            showHabitReview = true
        }
    }
}

// MARK: - App Entry Point

@main
struct SiftApp: App {
    @AppStorage(AppColorSchemeOverride.storageKey)
    private var colorSchemeRaw: String = AppColorSchemeOverride.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        (AppColorSchemeOverride(rawValue: colorSchemeRaw) ?? .system).preferredColorScheme
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
