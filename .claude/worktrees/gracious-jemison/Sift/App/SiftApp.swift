import SwiftUI

private enum MainTab: Int, Hashable {
    case today = 0
    case gems
    case themes
    case habits
}

// MARK: - Compose menu (shared)

/// Menu actions for the global compose control. Wire implementations when flows exist.
private struct MainTabCompose {
    @ViewBuilder
    static var menuButtons: some View {
        Button("New Entry", systemImage: "square.and.pencil") { }
        Button("New Action", systemImage: "checkmark.circle") { }
        Button("New Theme", systemImage: "circle.hexagongrid") { }
        Button("New Habit", systemImage: "chart.bar") { }
    }
}

/// Native `tabViewBottomAccessory` compose control — layout and Liquid Glass chrome come from the system.
private struct MainTabBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    private var isInline: Bool { accessoryPlacement == .inline }

    var body: some View {
        Menu {
            MainTabCompose.menuButtons
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

@main
struct SiftApp: App {
    @AppStorage(AppColorSchemeOverride.storageKey)
    private var colorSchemeRaw: String = AppColorSchemeOverride.system.rawValue

    @State private var selectedTab: MainTab = .today
    @State private var showThemeReview = false
    @State private var showHabitReview = false
    @State private var bothReviewsDue = false

    private var preferredColorScheme: ColorScheme? {
        (AppColorSchemeOverride(rawValue: colorSchemeRaw) ?? .system).preferredColorScheme
    }

    var body: some Scene {
        WindowGroup {
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
                MainTabBottomAccessory()
            }
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
                await SupabaseService.shared.initialize()
                await checkReviewTriggers()
            }
            .preferredColorScheme(preferredColorScheme)
        }
    }

    private func checkReviewTriggers() async {
        guard let settings = try? await SupabaseService.shared.fetchOrCreateUserSettings() else { return }
        let now = Date()

        let ninetyDays: TimeInterval = 90 * 24 * 60 * 60
        let fourteenDays: TimeInterval = 14 * 24 * 60 * 60

        let themesDue = settings.lastThemeReview.map { now.timeIntervalSince($0) >= ninetyDays } ?? true
        let habitsDue = settings.lastHabitReview.map { now.timeIntervalSince($0) >= fourteenDays } ?? true

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
