import SwiftUI

@main
struct SiftApp: App {
    @State private var selectedTab = 1

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

                HabitsView()
                    .tabItem {
                        Label("Habits", systemImage: "chart.bar")
                    }
                    .tag(2)
            }
            .tint(Color.siftInk)
            .task {
                await SupabaseService.shared.initialize()
            }
        }
    }
}
