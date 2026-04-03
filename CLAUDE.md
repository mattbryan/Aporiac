# Sift — Claude Code Instructions

## Project Overview
Sift is a native iOS journaling app built with SwiftUI. It is the first app in the Aporian suite — a collection of focused thinking tools built around the philosophy that AI should facilitate thinking, not replace it.

**Tagline:** Say everything. Keep what matters.

Sift is a disposable journal. Entries fade after seven days unless a gem is flagged. What remains is only what the user consciously chose to keep. AI prompts thinking without replacing it, and generates a single sentence of connective tissue between gems in an entry.

---

## Critical Rules

### Xcode
- NEVER modify .pbxproj files
- Create new files through code, then run `xcodegen generate` to add them to the project
- Always rebuild in simulator after changes to verify UI
- Use XcodeBuildMCP tools to take simulator screenshots and validate UI before considering a task complete

### Architecture
- iOS 17+ minimum deployment target
- Pure SwiftUI only — no UIKit unless wrapping a legacy component with no SwiftUI equivalent
- The rich text editor (highlights, gems, actions) requires a `UITextView` wrapped in `UIViewRepresentable` — this is the sanctioned UIKit exception
- MVVM architecture — Models, ViewModels, Views clearly separated
- No third party UI libraries — all components are custom built
- Supabase Swift SDK for all data operations
- Anthropic SDK via Swift Package Manager for AI calls

### Performance & Feel
- **Responsiveness and animation quality are more important than visual styling.**
- Every interaction must be animated. Every transition must be considered.
- The app must feel native and immediate — no jank, no lag, no jarring cuts.
- Keyboard appearance/dismissal must be perfectly smooth.
- Highlight application must feel instant and satisfying.
- The fading calendar grid must animate gracefully.

### Code Style
- Swift 6
- Prefer value types (structs) over reference types (classes) where possible
- Use @Observable macro, not ObservableObject
- All async operations use async/await — no completion handlers
- No force unwrapping in production code
- Mark everything with appropriate access control
- All public API must have doc comments

### File Structure
```
Sift/
  App/
    SiftApp.swift
  Models/
    Entry.swift
    Gem.swift
    ActionItem.swift
    Theme.swift
    Habit.swift
    HabitLog.swift
    Entitlement.swift
  ViewModels/
    EntryViewModel.swift
    GemViewModel.swift
    ActionItemViewModel.swift
    ThemeViewModel.swift
    HabitViewModel.swift
  Views/
    Home/           ← today screen + action items
    Entry/          ← full-screen writing surface
    DayPicker/      ← calendar grid navigation
    Gems/
    Themes/
    Habits/
    Onboarding/
    Settings/
  Services/
    SupabaseService.swift
    AIService.swift
    EntitlementService.swift
  Components/
    RichTextEditor.swift   ← UITextView wrapper, core of the app
    (other custom reusable UI components)
  Resources/
    (assets, fonts)
```

---

## App Structure & Navigation

### Home Screen (today)
- Date at top
- Entry summary card → taps into today's entry
- If no entry exists: "Start Today's Entry" (inviting, not clinical)
- Below the entry card: rotating action items list
- Back from home → Day Picker

### Day Picker
- Calendar skeleton grid: squares with rounded corners representing days
- Today = darkest. Each prior day progressively lighter. Day 7 = most subtle.
- Days with gems = blue square, never fades
- Tapping a day opens that day's entry

### Entry Screen
- Full-screen, distraction-free writing surface
- Two sections rendered as one continuous editor:
  1. **Gratitude** — bulleted, placeholder: "Today, I'm grateful for..."
  2. **Mind dump** — AI-generated prompt as placeholder text
- Placeholder disappears on type, returns if section is emptied
- Visual partition between sections (subtle divider or spacing — not a label)
- No modal feel — the user is immediately in a writing state

### Action Items (Todos)
- Accessible via tab and gesture
- Revolving list — carries over day to day, never expires
- Actions: complete (gesture + tap), delete/dismiss (gesture + tap), edit text
- Completed items are retained (no decision yet on what to do with them)
- No archive — dismiss is a hard delete

---

## Highlights

Two highlight types, applied by text selection:

| Type | Color | Persists after 7 days |
|------|-------|----------------------|
| Gem | Blue (accent) | Yes — forever |
| Action item | Warm amber/orange | Yes — in the todo list |

### Highlight behavior on old entries
- Highlighted text retains its original color regardless of entry age
- Unhighlighted text in entries older than today renders noticeably lighter (a couple shades)
- Editing unhighlighted text in an old entry does not restore its original color — it remains lighter
- Adding a new highlight to an old entry restores the entry's initial color values

### After 7 days
- All unhighlighted text is permanently deleted
- Gems and action item highlights remain visible in the entry view
- AI generates minimal connective tissue — just enough to frame the gems and make them make sense
- The AI thread must never recreate content the user wrote through to reach the gems (people may write through hard things — the hard things disappearing is a relief, not a loss)

---

## Backend — Supabase

All data lives in Supabase. Use the Supabase Swift SDK for all operations.

### Schema

**public.entitlements**
```
user_id: UUID (references auth.users)
source: String — 'apple' | 'stripe'
status: String — 'trial' | 'active' | 'expired'
plan: String — 'monthly' | 'annual'
expires_at: Timestamp
```

**sift.entries**
```
id: UUID
user_id: UUID (references auth.users)
gratitude_content: String
content: String          ← mind dump
created_at: Timestamp
expires_at: Timestamp    ← created_at + 7 days
has_gem: Boolean         ← default false
```

**sift.gems**
```
id: UUID
user_id: UUID (references auth.users)
entry_id: UUID (references sift.entries)
content: String          ← flagged fragment, verbatim, user's own words
range_start: Int         ← character offset in combined entry text
range_end: Int           ← character offset in combined entry text
thread: String?          ← AI connective tissue, one sentence maximum
created_at: Timestamp
```

**sift.action_items**
```
id: UUID
user_id: UUID (references auth.users)
entry_id: UUID (references sift.entries)
content: String          ← verbatim text from highlight
completed: Boolean       ← default false
created_at: Timestamp
```

**sift.themes**
```
id: UUID
user_id: UUID (references auth.users)
title: String
description: String?
active: Boolean (default true)
created_at: Timestamp
```

**sift.habits**
```
id: UUID
user_id: UUID (references auth.users)
title: String
full_criteria: String
partial_criteria: String
created_at: Timestamp
```

**sift.habit_logs**
```
id: UUID
habit_id: UUID (references sift.habits)
date: Date
credit: Float (0, 0.5, or 1)
```

### Row Level Security
Every table must have RLS policies. Users can only read and write their own rows. Always apply RLS policies when creating tables.

---

## AI — Anthropic SDK

Use Claude Haiku for all AI tasks. Cost must stay minimal.

### AI jobs in Sift
1. **Daily prompt** — one well-timed question per session to open thinking. Appears as placeholder text in the mind dump section. Should feel personal, not generic. Reference active themes when relevant.
2. **Gem thread** — when an entry has gems flagged, generate one sentence maximum describing the connective tissue between them. This is not a summary. It describes the relationship between gems, not the content of the entry. Never recreate what was written through to reach the gems.

### AI philosophy
- AI prompts, it never generates the thinking
- AI compresses, it never expands
- One sentence is always enough
- Never produce something the user should have written themselves

---

## Design System

### Philosophy
Sift is a designed artifact, not a native iOS system app. Content first. Space does the work color usually does. Accents are rare and meaningful. **Feel and responsiveness come before visual polish.**

### Typography
- SF Pro exclusively
- Two weights only: Regular and Medium
- Three sizes maximum per screen

### Color
- Near monochrome base palette
- **Gem accent: mint** — `oklch(84.5% 0.143 164.978)` → sRGB `(0.373, 0.914, 0.709)` — used for gem highlights and gem-day squares in the calendar
- **Action accent: warm amber/orange** — used for action item highlights
- Everything else is neutral

### Spacing
- Base unit: 8pt
- All spacing is a multiple of 8

### Components
- All components are custom built
- No system chrome where it can be avoided
- Custom buttons, cards, navigation

---

## Subscription

- 14 day free trial — full experience, no feature gates
- $4.99/month or $49.99/year
- StoreKit 2 for in-app purchase
- Entitlement status checked against public.entitlements in Supabase
- Apple webhooks update entitlement on subscription events

---

## Aporian Suite Context

Sift is the first of three apps:
- **Sift** — disposable journal (this app)
- **Keep** — personal knowledge graph (future)
- **Forge** — spatial brainstorming and publication (future)

### Shared primitive contract
The gem data shape is shared across all Aporian apps. Do not change the gem model without considering suite-wide implications. A gem in Sift must be recognizable to Keep and Forge when integration is built later.

### Shared identity
All Aporian apps share the same Supabase auth.users table. The user_id in every table is the same identity across the suite. Never create app-specific user tables.

---

## Out of Scope for v1
- Web app
- Keep or Forge features
- Search
- Multimedia input
- Push notifications (consider v1.1)
- RevenueCat
- Stripe
- Cross-app data sharing

---

## Project Setup

### Generating the Xcode Project
The project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to generate `Sift.xcodeproj` from `project.yml`.

```bash
# Homebrew is at /opt/homebrew — add to PATH if needed
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install xcodegen (one time)
brew install xcodegen

# Generate the project (run from repo root whenever project.yml or new files are added)
xcodegen generate
```

**Never edit `Sift.xcodeproj/project.pbxproj` manually.** All project config lives in `project.yml`.

When adding new Swift files:
1. Create the file in the correct folder on disk
2. Run `xcodegen generate` to add it to the project automatically

---

## Build Order (v1)
1. `DesignSystem.swift` — color, type, and spacing tokens
2. `RichTextEditor.swift` — UITextView wrapper (core of the app)
3. Entry screen — two-section writing surface
4. Home screen — date, entry card, action items
5. Day picker — calendar grid with fading
6. Action items list / tab
7. Supabase data layer
8. AI integration

---

## When in Doubt
- Choose simpler over clever
- Choose native Swift patterns over workarounds
- If it doesn't feel right in the simulator, it's not done
- If something feels like scope creep, it probably is
- The goal of v1 is to prove the feeling, not build every feature
