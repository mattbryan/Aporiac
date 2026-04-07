# Sift — Cursor Development Instructions

## Read First

Before writing any code, read `CLAUDE.md` in full. It defines the product philosophy, schema, architecture rules, and design system. This document adds implementation-level detail for working inside the codebase day-to-day.

---

## Project Structure

```
Sift/
  App/
    SiftApp.swift           ← Entry point. AuthGateView → OnboardingView | MainAppView
  Models/                   ← Pure data structs. Codable, Sendable, value types only.
  ViewModels/               ← @Observable classes. One per domain. Business logic lives here.
  Views/
    Entry/                  ← EntryView — the core writing surface
    Gems/                   ← GemsView, GemCard, GemDetailView
    Themes/                 ← ThemesView, ThemeFormSheet
    Habits/                 ← HabitsView, HabitFormSheet, HabitDetailView
    Home/                   ← HomeView (Today tab), ActionItemsView
    Onboarding/             ← OnboardingView (Sign in with Apple)
    Settings/               ← SettingsView
    DayPicker/              ← DayPickerView, CalendarDayHomeView
  Services/
    SupabaseService.swift   ← All Supabase calls. @Observable singleton.
    AIService.swift         ← Anthropic API. Gem thread generation only.
    EntitlementService.swift← StoreKit 2 stub (not yet implemented)
  Components/               ← Reusable UI: DesignSystem.swift, MarkdownTextEditor, QuickActionSheet, etc.
  Resources/                ← Fonts, assets
```

---

## Architecture Rules

### Observable Pattern
Use `@Observable` macro — never `ObservableObject`. ViewModels are `@State` in the owning view, not injected via environment unless shared across many unrelated views.

```swift
// ✅ Correct
@Observable
final class ThemeViewModel { ... }

struct ThemesView: View {
    @State private var viewModel = ThemeViewModel()
}

// ❌ Wrong
class ThemeViewModel: ObservableObject { ... }
```

### ViewModel Ownership
Each view owns its ViewModel via `@State`. If two sibling views need to share state, lift the ViewModel to their parent or use a notification.

### Async/Await
All async work uses `async/await`. No completion handlers. No Combine publishers. Tasks are created with `Task { }` inside view modifiers or button actions.

### No Force Unwrapping
Use `guard let`, `if let`, or `?? default`. Never `!` in production code.

---

## Service Layer

### SupabaseService
The single point of contact for all database operations. Never call `client` directly from a view or ViewModel — always go through `SupabaseService.shared`.

```swift
// ✅ Correct
let themes = try await SupabaseService.shared.fetchActiveThemes()

// ❌ Wrong
let themes = try await SupabaseService.shared.client.from("themes")...
```

**Schema:** All sift data lives in the `sift` schema. Public data (user settings, entitlements) lives in the `public` schema. The client is configured for `sift` by default; use `client.schema("public")` for the other.

**RLS:** Every query is automatically scoped to the current user via Row Level Security. The `user_id` filter in queries is a belt-and-suspenders guard — RLS is the real gate.

### Auth State
`SupabaseService.shared.currentUser` is the auth source of truth. `isAuthReady` gates the splash screen. Both are `@Observable` — views that read them will re-render automatically.

---

## Design System

All tokens are in `DesignSystem.swift`. Never hardcode colours, spacing, or radii.

### Colours
```swift
Color.siftInk        // Primary text
Color.siftSubtle     // Secondary/tertiary text
Color.siftSurface    // App background
Color.siftCard       // Card / row background
Color.siftAccent     // Teal — primary interactive accent
Color.siftGem        // Gold — gems only
Color.siftDivider    // Separator lines
Color.siftDelete     // Destructive swipe actions
```

### Spacing
```swift
DS.Spacing.xs   // 4pt
DS.Spacing.sm   // 8pt
DS.Spacing.md   // 16pt
DS.Spacing.lg   // 24pt
DS.Spacing.xl   // 32pt
DS.Spacing.screenEdge  // 20pt — horizontal page margin
```

### Typography
```swift
.font(.siftBody)         // 17pt Regular
.font(.siftBodyMedium)   // 17pt Medium
.font(.siftCallout)      // 15pt Regular
.font(.siftCaption)      // 13pt Regular
.siftTextStyle(.h1Medium)  // Newsreader Italic 36pt Medium
.siftTextStyle(.h2Medium)  // Newsreader Italic 24pt Medium
```

### Buttons
```swift
DS.ButtonHeight.large   // 52pt — primary actions
DS.ButtonHeight.medium  // 44pt — secondary actions
DS.Radius.sm   // 8pt — button corner radius
DS.Radius.md   // 12pt — card corner radius
```

---

## Common Patterns

### Adding a New Sheet
1. Add `@State private var showXxx = false` to the owning view
2. Add `.sheet(isPresented: $showXxx) { XxxView() }` to the view body
3. Use `.presentationDetents([.medium])` or `.large` depending on content height
4. Always add `.presentationDragIndicator(.visible)`

### Adding a New Form Sheet
Follow the pattern in `ThemeFormSheet` and `HabitFormSheet`:
- Accept a `mode: enum { case create; case edit(Model) }` parameter
- Accept `onSave: (fields...) -> Void` callback
- Optionally accept `onArchive: (() -> Void)?`
- Drive the Save button disabled state from field validation
- Call `dismiss()` after save

### Adding a New ViewModel
```swift
@Observable
final class XxxViewModel {
    private let service = SupabaseService.shared
    private(set) var items: [Xxx] = []
    private(set) var isLoading = false

    func load() async throws {
        isLoading = true
        defer { isLoading = false }
        items = try await service.fetchXxx()
    }
}
```

### Adding a New SupabaseService Method
1. Add the method to `SupabaseService.swift`
2. Add any required private Encodable/Decodable structs at the bottom of the file
3. Always guard on `currentUser?.id` at the start
4. Use `try await` — no completion handlers

```swift
func fetchXxx() async throws -> [Xxx] {
    guard let userID = currentUser?.id else { return [] }
    return try await client
        .from("xxx")
        .select()
        .eq("user_id", value: userID.uuidString)
        .order("created_at")
        .execute()
        .value
}
```

### Notifications (Cross-View Refresh)
Use `NotificationCenter` sparingly — only for cross-hierarchy refresh where a direct binding isn't possible. All notification names are defined in the `Notification.Name` extension at the bottom of `EntryViewModel.swift`.

```swift
// Post
NotificationCenter.default.post(name: .siftJournalEntitiesDidSync, object: nil)

// Receive
.onReceive(NotificationCenter.default.publisher(for: .siftJournalEntitiesDidSync)) { _ in
    Task { await reload() }
}
```

**Existing notifications:**
- `siftJournalEntitiesDidSync` — general refresh; posted after entry save, gem changes, action changes
- `siftEntryBodyUpdatedFromDayView` — entry body changed externally; object is the entry UUID
- `siftActionCompletionChanged` — action toggled from Today; userInfo has action content + completed state

### Skeleton Loading
Use `SiftSkeletonShimmer { }` to wrap skeleton placeholder views while data loads.

```swift
if isLoading {
    SiftSkeletonShimmer {
        ForEach(0..<4, id: \.self) { _ in
            SiftListRowSkeleton()
        }
    }
}
```

---

## Compose Menu (Global Create)

The compose button lives in `MainTabBottomAccessory` in `SiftApp.swift`. All creation sheets are presented from `MainAppView` so they float above any tab without switching tabs.

| Action | Behaviour |
|--------|-----------|
| Today's Entry | `fullScreenCover` → `EntryView()` |
| New Gem | Calls `SupabaseService.createQuickGem()`, presents `GemDetailView` as a sheet with `isSheet: true` |
| New Theme | Sheet → `ThemeFormSheet(mode: .create)` |
| New Habit | Sheet → `HabitFormSheet(mode: .create)` |
| New Action | Sheet → `QuickActionSheet` |

To add a new compose action:
1. Add a closure parameter to `MainTabBottomAccessory`
2. Add a `Button { closure() } label: { Label(...) }` to the `Menu`
3. Add the corresponding `@State` and sheet modifier to `MainAppView`

---

## GemDetailView — Sheet vs Navigation

`GemDetailView` works in two contexts:

- **Navigation stack** (default): pushed via `.navigationDestination(for: UUID.self)`, back button pops
- **Sheet** (`isSheet: true`): presented via `.sheet(item:)` wrapped in a `NavigationStack`, shows an X close button, auto-focuses the text field

```swift
// Navigation stack (existing behaviour)
GemDetailView(gemID: id, navigationPath: $path)

// Sheet (compose menu)
GemDetailView(gemID: id, navigationPath: .constant(NavigationPath()), isSheet: true)
```

---

## Auth Flow

```
App launch
  └─ AuthGateView
       ├─ isAuthReady == false  →  Splash (Color.siftSurface)
       ├─ currentUser == nil    →  OnboardingView (Sign in with Apple)
       └─ currentUser != nil    →  MainAppView (tab bar)
```

Sign out or account deletion sets `currentUser = nil` on `SupabaseService`, which `AuthGateView` observes and automatically returns to `OnboardingView`.

---

## What Not to Do

- Do not modify `.pbxproj` files — add new files to Xcode manually
- Do not use `UIKit` directly — SwiftUI only, unless wrapping a component with no SwiftUI equivalent
- Do not use third-party UI libraries
- Do not add AI generation for anything except gem thread (one sentence, Haiku only)
- Do not add completion handlers or Combine — `async/await` only
- Do not force-unwrap (`!`) in production code
- Do not hardcode colours, spacing, or font sizes — always use design tokens
- Do not create app-specific user tables in Supabase — all users share `auth.users`
- Do not change the `Gem` model shape without considering the full Aporian suite
