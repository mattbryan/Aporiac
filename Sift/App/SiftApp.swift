import SwiftUI

@main
struct SiftApp: App {
    @State private var selectedTab = 1
    @State private var showThemeReview = false
    @State private var showHabitReview = false
    @State private var bothReviewsDue = false

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                DayPickerView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(0)

                HomeView()
                    .tabItem {
                        Label("Today", systemImage: "sun.min")
                    }
                    .tag(1)

                GemsView()
                    .tabItem {
                        Label("Gems", systemImage: "sparkle")
                    }
                    .tag(2)

                ThemesView()
                    .tabItem {
                        Label("Themes", systemImage: "circle.hexagongrid")
                    }
                    .tag(3)

                HabitsView()
                    .tabItem {
                        Label("Habits", systemImage: "chart.bar")
                    }
                    .tag(4)
            }
            .background(Color.siftSurface.ignoresSafeArea())
            .tint(Color.siftInk)
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
