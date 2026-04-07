# Sift — iOS Native Patterns Reference

> **Reference:** Apple's official Liquid Glass overview: [Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) (`https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass`).
>
> **Cursor:** Read this file (`IOS_PATTERNS.md` in the repo root) before implementing any navigation, tab bar, toolbar, or button pattern.

A living document of native SwiftUI/UIKit implementation patterns used in Sift.
Target: **iOS 26 minimum**. Updated as new patterns are established during the build.

---

## Pattern Index

- [Liquid Glass — Overview](#liquid-glass--overview)
- [Liquid Glass Tab Bar with Bottom Accessory](#liquid-glass-tab-bar-with-bottom-accessory)
- [Navigation Bar — Large Title to Inline Transition](#navigation-bar--large-title-to-inline-transition)
- [Frosted Glass Buttons](#frosted-glass-buttons)
- [Typography — Satoshi + Newsreader + SF Pro](#typography--satoshi--newsreader--sf-pro)
- [Swipe rows inside ScrollView (`SwipeRevealRow`)](#swipe-rows-inside-scrollview-swiperevealrow)

---

## Liquid Glass — Overview

iOS 26 introduces Liquid Glass as Apple's primary design material. It applies automatically to native navigation elements (tab bars, nav bars, toolbars) when compiled against the iOS 26 SDK.

**Rules:**
- Never stack glass on glass — use `GlassEffectContainer` when multiple glass elements share a frame
- Never apply `.glassEffect()` to content-layer views — only to floating navigation elements
- Do not add custom background colors to tab bars or toolbars — the system provides the glass
- Reduced transparency and increased contrast adaptations are handled automatically

**Three material variants:**
| Variant | Usage |
|---|---|
| `.glassEffect(.regular)` | Default — standard floating elements |
| `.glassEffect(.regular.interactive())` | Adds touch response: scale, bounce, shimmer |
| `.glassEffect(.clear)` | High transparency — media backgrounds |
| `.glassEffect(.identity)` | Conditional disable — no visual change |

**Button styles:**
| Style | Usage |
|---|---|
| `.buttonStyle(.glass)` | Secondary actions — translucent |
| `.buttonStyle(.glassProminent)` | Primary actions — opaque with tint |

---

## Liquid Glass Tab Bar with Bottom Accessory

### What it is
iOS 26's native `TabView` automatically adopts Liquid Glass — the tab bar floats above content as a capsule-shaped glass element inset from screen edges. Content scrolls beneath it.

The `.tabViewBottomAccessory` modifier adds a persistent element above the tab bar (e.g. a global create/action button). When the tab bar minimizes on scroll, the accessory moves inline with the minimized bar automatically.

**Sift choice — `.tabBarMinimizeBehavior(.never)`:** Multiline fields (gem fragments in `ScrollView`) change content height and can affect scroll reporting enough that **`.onScrollDown`** minimized the tab bar and contributed to **keyboard dismissal** and focus loss. The app keeps the tab bar expanded for stability; users still get native keyboard Done / scroll dismiss where explicitly configured on each screen.

### When to use
Any app with a primary tab navigation + a globally accessible create/action button. Used in Sift for the main tab bar + plus/action button.

### Implementation

```swift
TabView(selection: $selectedTab) {
    Tab("Today", systemImage: "sun.min", value: 0) {
        TodayView()
    }
    Tab("Gems", systemImage: "sparkle", value: 1) {
        GemsView()
    }
    Tab("Themes", systemImage: "circle.hexagongrid", value: 2) {
        ThemesView()
    }
    Tab("Habits", systemImage: "chart.bar", value: 3) {
        HabitsView()
    }
}
.tabBarMinimizeBehavior(.never)  // Sift uses `.never` — see notes below
.tabViewBottomAccessory {
    Menu {
        Button("Today's Entry", systemImage: "square.and.pencil") { }
        Button("New Action", systemImage: "checkmark.circle") { }
        Button("New Theme", systemImage: "circle.hexagongrid") { }
        Button("New Habit", systemImage: "chart.bar") { }
    } label: {
        Image(systemName: "plus")
            .bold()
    }
    .buttonStyle(.glassProminent)
    .fixedSize()
}
```

### Tab bar minimize behavior options
| Value | Behaviour |
|---|---|
| `.automatic` | System decides based on content |
| `.onScrollDown` | Minimizes when user scrolls down, re-expands on scroll up |
| `.never` | Always fully expanded |

### Notes
- `TabView` gets the Liquid Glass treatment automatically — do not add custom backgrounds
- The accessory view receives a Liquid Glass capsule background automatically
- The accessory is visible across all tabs — use it for globally relevant actions only
- Tapping a `Menu` label presents the native iOS popup menu (chevron, actions list)

---

## Navigation Bar — Large Title to Inline Transition

### What it is
iOS 26 navigation bars are automatically transparent with Liquid Glass buttons. The standard large title → inline title scroll transition still applies and is the correct pattern for screen headers.

- **Large title (top)**: displayed in the scroll content area, large and prominent
- **Inline title (scrolled)**: collapses into the navigation bar with leading/trailing glass buttons

### When to use
All main tab screens in Sift — Today, Gems, Themes, Habits.

### Implementation

```swift
NavigationStack {
    ScrollView {
        // Content here — large title is in the nav bar, not in content
    }
    .navigationTitle("Today")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
        ToolbarItem(placement: .topBarLeading) {
            Button { } label: {
                Image(systemName: "calendar")
            }
            .glassEffect(.regular.interactive())
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { } label: {
                Image(systemName: "gearshape")
            }
            .glassEffect(.regular.interactive())
        }
    }
}
```

### Notes
- The calendar (leading) and settings (trailing) toolbar buttons use `.glassEffect(.regular.interactive())` for the frosted pill appearance
- iOS 26 handles the large → inline transition and glass treatment automatically
- Do NOT build a custom scroll-offset overlay for this — the native NavigationStack handles it
- The leading calendar button only appears in the inline (scrolled) state in the design — use `ToolbarItemGroup` with visibility control if needed, or accept both states showing it

---

## Frosted Glass Buttons

### What it is
Circular or pill-shaped buttons with a frosted glass background, shadow, and touch response. Used for toolbar actions and floating controls.

### Native API
`.glassEffect(.regular.interactive())` — applies the Liquid Glass material with touch feedback.

### Implementation

```swift
Button { } label: {
    Image(systemName: "gearshape")
        .font(.system(size: 20))
        .frame(width: 40, height: 40)
}
.glassEffect(.regular.interactive(), in: Circle())
```

### Shadow
The design token `material/liquid-glass` maps to:
```swift
.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 2)
```
This is applied automatically by `.glassEffect()` — do not add it manually.

### Notes
- Pass `in: Circle()` for circular buttons, `in: Capsule()` for pill-shaped
- `.interactive()` adds scale, bounce, and shimmer on touch — use for all tappable glass elements
- Use `GlassEffectContainer { }` if multiple glass buttons share a frame to prevent stacking artifacts

---

## Typography — Satoshi + Newsreader + SF Pro

### Rule
| Token | Family | Weight | Size | Use |
|---|---|---|---|---|
| Date heading | Newsreader | Bold Italic | 36pt | Today date header only |
| `siftTitle` | SF Pro | Medium | 28pt | Screen navigation titles |
| `siftHeadline` | SF Pro | Medium | 20pt | Section headers |
| `siftBody` | Satoshi | Regular | 17pt | Primary content |
| `siftBodyMedium` | Satoshi | Medium | 17pt | Emphasis, button labels |
| `siftCallout` | Satoshi | Regular | 15pt | Secondary content |
| `siftCaption` | Satoshi | Regular | 13pt | Metadata, timestamps |
| `siftMicro` | Satoshi | Bold | 11pt | Section labels (HABITS, ACTIONS) |
| Tab labels | SF Pro | Regular | 11pt | System tab bar labels |

### Bundling custom fonts
1. Add all `.otf` / `.ttf` files to `Sift/Resources/Fonts/`
2. Add to Xcode target (check target membership in File Inspector)
3. Register each filename in `Info.plist` under key `UIAppFonts` (array of strings)
4. Use: `Font.custom("Satoshi-Regular", size: 17)`

### Files needed
**Satoshi:** Satoshi-Regular, Satoshi-Medium, Satoshi-Bold (minimum)
**Newsreader:** Newsreader-BoldItalic (minimum — only used for date heading)

### Verify PostScript names after bundling
```swift
UIFont.familyNames.sorted().forEach { family in
    UIFont.fontNames(forFamilyName: family).forEach { print($0) }
}
```

---

## Swipe rows inside ScrollView (`SwipeRevealRow`)

### What it is
`List` swipe actions are unreliable inside a vertical `ScrollView`, so Home uses a custom `SwipeRevealRow` (see [`HomeView.swift`](Sift/Views/Home/HomeView.swift)): background leading/trailing action buckets, foreground content offset on a horizontal `DragGesture`, and an `openRowKey` binding so only one row stays open at a time.

### Stability rules
- **Stable SwiftUI identity:** Do not put rapidly changing data (e.g. server-assigned log row IDs after an optimistic write) in `.id(...)` on the row. Prefer `habit.id` (or another stable key) so `@State` swipe offset is not reset on every model refresh.
- **Dismiss after action:** Full-swipe and button actions should clear the parent’s `openSwipeRowKey` (set to `nil`) so `onChange` snaps the row closed; mirror this for every row type (habits, actions).
- **Hit targets:** Action labels should use `.contentShape(Rectangle())` so the full bucket width (~76pt) is tappable, not only the icon.

### Gesture tuning
- Use `DragGesture(minimumDistance: …)` **around 28** so light vertical scrolls are less likely to be interpreted as horizontal swipes; horizontal vs vertical is further gated with a small dominance threshold before committing.
- Gem rows use a **higher minimum distance** and **`simultaneousGesture`** (not `highPriorityGesture`) so embedded `TextField`s keep typing priority.
- **`\.swipeRevealRowIsOpen`** is injected as `offset != 0 || (openRowKey != nil && openRowKey != rowKey)` — **not** `isDragging`. Rows like `GemEditableFragmentRow` and `ActionItemRow` set `allowsHitTesting(!swipeRevealRowIsOpen)`; including `isDragging` caused `isDragging == true` during gesture recognition to **disable the text field and clear focus** mid-typing. Foreground drag blocking still uses `contentAllowsHitTesting` (`offset != 0 || !isDragging`) on the row.

---
