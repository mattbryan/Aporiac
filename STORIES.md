# Sift — Development Stories

Stories are written for Cursor to implement. Each story is self-contained with full context, acceptance criteria, and file pointers. Read `CLAUDE.md` and `CURSOR.md` before starting any story.

---

## STORY-001 — Compose Menu: Text and Behaviour Overhaul

**Status:** Ready
**Priority:** High

### Background
The global compose menu (the + button in the tab bar accessory) currently has placeholder labels and non-functional buttons. This story wires up every menu item to open the correct creation surface without navigating away from the current tab.

The compose menu lives in `MainTabBottomAccessory` inside `Sift/App/SiftApp.swift`. All sheets are presented from `MainAppView` in the same file.

---

### Story 1a — Rename "New Entry" to "Today's Entry"

**File:** `Sift/App/SiftApp.swift`
**Location:** `MainTabBottomAccessory` body, inside the `Menu`

**Acceptance Criteria:**
- The first menu item label reads **"Today's Entry"**
- Icon remains `TabToday` (custom image asset)
- Tapping it opens `EntryView` as a `fullScreenCover` — behaviour unchanged

---

### Story 1b — New Gem: Open gem detail sheet without leaving current tab

**Files:** `Sift/App/SiftApp.swift`, `Sift/Services/SupabaseService.swift`, `Sift/Views/Gems/GemCard.swift`

**Behaviour:**
1. User taps "New Gem" in the compose menu
2. A new empty gem is created in Supabase, attached to today's entry
   - If today's entry does not exist, create one silently
   - Append a `> ` gem marker line to the entry body
   - Set `has_gem = true` on the entry
3. The gem detail view opens as a sheet **over the current tab** — no tab switch
4. The text field is focused automatically so the user can start typing immediately
5. The user types the gem content; it saves via the existing debounce mechanism
6. An X close button is shown in the top-left of the sheet

**SupabaseService additions needed:**
- `createQuickGem() async throws -> UUID` — creates the entry if needed, inserts gem, appends marker, returns new gem ID

**GemDetailView changes needed (`Sift/Views/Gems/GemCard.swift`):**
- Add `var isSheet: Bool = false` parameter
- Add `@Environment(\.dismiss) private var dismiss`
- When `isSheet == true`: show an X close button in `ToolbarItem(placement: .cancellationAction)`
- When `isSheet == true`: auto-focus `fragmentFieldFocused = true` after load completes
- Replace `navigationPath.removeLast()` in `confirmDeleteGem()` with `dismiss()` — this works correctly in both navigation stack and sheet contexts

**SiftApp.swift additions needed:**
- `private struct GemSheetItem: Identifiable { let id: UUID }` — wrapper for `sheet(item:)`
- `@State private var gemSheetItem: GemSheetItem?` in `MainAppView`
- Compose closure: `Task { if let id = try? await SupabaseService.shared.createQuickGem() { gemSheetItem = GemSheetItem(id: id) } }`
- Sheet modifier on `MainAppView`:
  ```swift
  .sheet(item: $gemSheetItem) { item in
      NavigationStack {
          GemDetailView(gemID: item.id, navigationPath: .constant(NavigationPath()), isSheet: true)
      }
  }
  ```

**Acceptance Criteria:**
- Tapping "New Gem" does not switch tabs
- A sheet slides up showing the gem detail view
- The keyboard appears automatically
- Typing content saves via the existing debounced gem fragment save
- Closing the sheet (X button or swipe) leaves the user on the tab they were on
- Deleting the gem from within the sheet dismisses the sheet

---

### Story 1c — New Theme: Open theme creation modal without leaving current tab

**Files:** `Sift/App/SiftApp.swift`, `Sift/ViewModels/ThemeViewModel.swift`

**Behaviour:**
1. User taps "New Theme" in the compose menu
2. The `ThemeFormSheet` slides up as a sheet **over the current tab** — no tab switch
3. This is the exact same modal opened by the + button on the Themes page
4. On save, the theme is created and the Themes tab list refreshes in the background

**SiftApp.swift additions needed:**
- `@State private var showNewTheme = false` in `MainAppView`
- `@State private var themeViewModel = ThemeViewModel()` in `MainAppView`
- Compose closure: `showNewTheme = true`
- Sheet modifier:
  ```swift
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
  ```

**Acceptance Criteria:**
- Tapping "New Theme" does not switch tabs
- `ThemeFormSheet` slides up in-place
- Saving creates the theme; the Themes tab list shows it next time it's visited
- Icon in menu matches the Themes tab icon (`TabThemes` image asset)

---

### Story 1d — New Habit: Open habit creation modal without leaving current tab

**Files:** `Sift/App/SiftApp.swift`, `Sift/ViewModels/HabitViewModel.swift`

**Behaviour:**
1. User taps "New Habit" in the compose menu
2. The `HabitFormSheet` slides up as a sheet **over the current tab** — no tab switch
3. This is the exact same modal opened by the + button on the Habits page
4. On save, the habit is created and the Habits tab list refreshes in the background

**SiftApp.swift additions needed:**
- `@State private var showNewHabit = false` in `MainAppView`
- `@State private var habitViewModel = HabitViewModel()` in `MainAppView`
- Compose closure: `showNewHabit = true`
- Sheet modifier:
  ```swift
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
  ```

**Acceptance Criteria:**
- Tapping "New Habit" does not switch tabs
- `HabitFormSheet` slides up in-place
- Saving creates the habit; the Habits tab list shows it next time it's visited
- Icon in menu matches the Habits tab icon (`TabHabits` image asset)

---

### Story 1e — New Action: Minimal creation modal without leaving current tab

**Files:** `Sift/App/SiftApp.swift`, `Sift/Services/SupabaseService.swift`
**New file:** `Sift/Components/QuickActionSheet.swift`

**Behaviour:**
1. User taps "New Action" in the compose menu
2. A minimal sheet slides up **over the current tab** — no tab switch
3. Sheet contains:
   - Title: "New Action" (`h2Medium` text style)
   - Single text field: placeholder "What do you want to do?" — auto-focused on appear
   - Save button (primary style, disabled when field is empty)
4. On save:
   - Action item is inserted into `action_items` in Supabase
   - A `- [ ] {content}` line is appended to today's entry body (create entry silently if none exists)
   - `siftJournalEntitiesDidSync` notification is posted so the Today list refreshes
5. Sheet dismisses immediately on save (don't wait for async to complete)

**SupabaseService additions needed:**
- `createQuickAction(content: String) async throws` — inserts action item, appends task line to today's entry body

**QuickActionSheet.swift** (new component in `Sift/Components/`):
- Follows the same visual style as `ThemeFormSheet` and `HabitFormSheet`
- Auto-focus text field `onAppear`
- Dismiss first, then execute async save in background `Task`
- No theme tagging — action themes are out of scope for now

**SiftApp.swift additions needed:**
- `@State private var showNewAction = false` in `MainAppView`
- Compose closure: `showNewAction = true`
- Sheet modifier:
  ```swift
  .sheet(isPresented: $showNewAction) {
      QuickActionSheet()
          .presentationDetents([.height(260)])
          .presentationDragIndicator(.visible)
  }
  ```

**Acceptance Criteria:**
- Tapping "New Action" does not switch tabs
- Sheet appears with keyboard focused
- Saving inserts the action and dismisses the sheet immediately
- Today list refreshes in the background via notification
- Icon in menu uses `systemImage: "checkmark.circle"` (no custom tab icon for actions)

---

### Cleanup Required Alongside This Story

The notification-based approach that was previously wired for these actions must be removed:

- **`Sift/Views/Home/HomeView.swift`** — remove any `onReceive` for `siftRequestCreateAction`
- **`Sift/Views/Themes/ThemesView.swift`** — remove any `onReceive` for `siftRequestShowCreateTheme`
- **`Sift/Views/Habits/HabitsView.swift`** — remove any `onReceive` for `siftRequestShowCreateHabit`

The notification name definitions in `EntryViewModel.swift` can remain (they may be useful later) but their usages should be gone.

---

## STORY-002 — Review Trigger Guards

**Status:** Ready
**Priority:** Medium

### Background
The 90-day theme review and 14-day habit review are currently triggered as soon as the elapsed time has passed, even for brand new users who haven't created any themes or habits yet. The review prompt should only appear when there is something meaningful to review.

**File:** `Sift/App/SiftApp.swift` — `checkReviewTriggers()` inside `MainAppView`

### Acceptance Criteria
- Theme review only triggers if:
  1. 90 days have elapsed since `last_theme_review` (or it has never been set), **AND**
  2. The user has at least one active (non-archived) theme that is itself at least 90 days old
- Habit review only triggers if:
  1. 14 days have elapsed since `last_habit_review` (or it has never been set), **AND**
  2. The user has at least one active (non-archived) habit that is itself at least 14 days old
- A brand new user with no themes or habits sees no review prompt on first launch

### SupabaseService additions needed
- `hasActiveThemeOlderThan(_ interval: TimeInterval) async -> Bool`
- `hasActiveHabitOlderThan(_ interval: TimeInterval) async -> Bool`

Both query their respective table filtered by `active = true` and `created_at < (now - interval)`, returning true if at least one row exists. These can be run concurrently with `async let`.

---

## STORY-003 — Onboarding: Sign in with Apple

**Status:** Ready
**Priority:** High

### Background
The app currently signs users in anonymously. This must be replaced with Sign in with Apple so users have a persistent, recoverable identity.

### Files
- **New:** `Sift/Views/Onboarding/OnboardingView.swift`
- **New:** `Sift/Views/Settings/SettingsView.swift` (extract from `HomeView.swift`)
- **Modified:** `Sift/Services/SupabaseService.swift`
- **Modified:** `Sift/App/SiftApp.swift`
- **Modified:** `Sift/Views/Home/HomeView.swift`

### Auth Gate (`SiftApp.swift`)
Replace the current always-show-TabView approach with a three-state gate:

```
isAuthReady == false  →  Splash (Color.siftSurface, full screen)
currentUser == nil    →  OnboardingView
currentUser != nil    →  MainAppView (existing tab bar)
```

Implement as a `private struct AuthGateView: View` that reads `SupabaseService.shared.isAuthReady` and `SupabaseService.shared.currentUser`. Because `SupabaseService` is `@Observable`, SwiftUI tracks these reads automatically and re-renders when they change.

### SupabaseService changes
- Add `private(set) var isAuthReady = false`
- Remove anonymous sign-in fallback from `initialize()`
- Set `isAuthReady = true` at the end of `initialize()` regardless of outcome
- Add `signInWithApple(idToken: String, nonce: String) async throws`
- Add `signOut() async throws` — calls `client.auth.signOut()`, sets `currentUser = nil`
- Add `deleteAccount() async throws` — deletes user data across sift schema tables, signs out

### OnboardingView
- Full screen, `Color.siftSurface` background
- Centered wordmark: "Sift" in large medium weight, tagline below in `siftCallout`
- `SignInWithAppleButton(.continue)` at the bottom
  - Style: `.white` in dark mode, `.black` in light mode (read from `@Environment(\.colorScheme)`)
  - Height: `DS.ButtonHeight.large` (52pt)
  - Corner radius: `DS.Radius.sm` (8pt) via `.clipShape`
- Nonce: generate with `SecRandomCopyBytes`, SHA-256 hash with `CryptoKit`
  - Raw nonce → Supabase `signInWithIdToken`
  - Hashed nonce → Apple `request.nonce`
- Loading state: `ProgressView` replaces button while sign-in is in flight
- Error state: caption text above button, only shown for non-cancelled errors
- `ASAuthorizationError.canceled` is silent — user dismissed, no message

### SettingsView (extract + extend)
Extract the existing inline `SettingsView` from `HomeView.swift` into `Sift/Views/Settings/SettingsView.swift`. Add an **Account** section:

```swift
Section("Account") {
    Button("Sign Out") {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            try? await SupabaseService.shared.signOut()
        }
    }
    .foregroundStyle(Color.siftInk)

    Button("Delete Account", role: .destructive) {
        showDeleteConfirmation = true
    }
}
```

Delete account requires a `confirmationDialog` with message: *"This will permanently delete your account and all data. This cannot be undone."*

The 300ms delay before sign out allows the sheet dismiss animation to complete before the root view transitions to `OnboardingView`.

### Supabase configuration required (manual, not code)
- Enable Apple provider in Supabase dashboard → Authentication → Providers → Apple
- Set Client ID to the app's bundle identifier
- Leave Secret Key blank (native iOS flow — no OAuth web flow)
- Enable "Allow users without an email"

### Acceptance Criteria
- First launch with no session → OnboardingView shows
- Tapping "Continue with Apple" triggers the system Apple ID sheet
- Successful sign-in → transitions to MainAppView
- Subsequent launches restore session → go directly to MainAppView (no flicker)
- Sign Out in Settings → returns to OnboardingView
- Delete Account in Settings → deletes data, returns to OnboardingView

---

*Add new stories below this line as they are defined.*
