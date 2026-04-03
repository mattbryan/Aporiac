# Sift — Claude Code Instructions

## Project Overview
Sift is a native iOS journaling app built with SwiftUI. It is the first app in the Aporian suite — a collection of focused thinking tools built around the philosophy that AI should facilitate thinking, not replace it.

**Tagline:** Say everything. Keep what matters.

Sift is a disposable journal. Entries fade after seven days unless a gem is flagged. What remains is only what the user consciously chose to keep. AI prompts thinking without replacing it, and generates a single sentence of connective tissue between gems in an entry.

---

## Critical Rules

### Xcode
- NEVER modify .pbxproj files
- Create new files through code, then add them to Xcode manually
- Always rebuild in simulator after changes to verify UI
- Use XcodeBuildMCP tools to take simulator screenshots and validate UI before considering a task complete

### Architecture
- iOS 17+ minimum deployment target
- Pure SwiftUI only — no UIKit unless wrapping a legacy component with no SwiftUI equivalent
- MVVM architecture — Models, ViewModels, Views clearly separated
- No third party UI libraries — all components are custom built
- Supabase Swift SDK for all data operations
- Anthropic SDK via Swift Package Manager for AI calls

### Code Style
- Swift 6
- Prefer value types (structs) over reference types (classes) where possible
- Use @Observable macro, not ObservableObject
- All async operations use async/await — no completion handlers
- No force unwrapping in production code
- Mark everything with appropriate access control
- All public API must have doc comments

### File Structure

SiftApp/
  App/
    SiftApp.swift
  Models/
    Entry.swift
    Gem.swift
    Theme.swift
    Habit.swift
    HabitLog.swift
    Entitlement.swift
  ViewModels/
    EntryViewModel.swift
    GemViewModel.swift
    ThemeViewModel.swift
    HabitViewModel.swift
  Views/
    Entry/
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
    (custom reusable UI components)
  Resources/
    (assets, fonts)

---

## Backend — Supabase

All data lives in Supabase. Use the Supabase Swift SDK for all operations.

### Schema

**public.entitlements**

user_id: UUID (references auth.users)
source: String — 'apple' | 'stripe'
status: String — 'trial' | 'active' | 'expired'
plan: String — 'monthly' | 'annual'
expires_at: Timestamp

**public.user_settings**

user_id: UUID (references auth.users)
last_theme_review: Timestamp
last_habit_review: Timestamp

**sift.entries**

id: UUID
user_id: UUID (references auth.users)
content: String
created_at: Timestamp
expires_at: Timestamp (created_at + 7 days)
has_gem: Boolean (default false)

**sift.gems**

id: UUID
user_id: UUID (references auth.users)
entry_id: UUID (references sift.entries)
content: String (flagged fragment, verbatim, user's own words)
thread: String? (AI-generated connective tissue, one sentence maximum)
created_at: Timestamp

**sift.gem_themes**

gem_id: UUID (references sift.gems)
theme_id: UUID (references sift.themes)

Junction table. A gem can connect to multiple themes. Optional — never required.

**sift.actions**

id: UUID
user_id: UUID (references auth.users)
entry_id: UUID? (references sift.entries)
content: String
completed: Boolean (default false)
carried_forward: Boolean (default false)
created_at: Timestamp
expires_at: Timestamp (short TTL — actions are temporary by nature)

**sift.action_themes**

action_id: UUID (references sift.actions)
theme_id: UUID (references sift.themes)

Junction table. An action can connect to multiple themes. Optional — never required.

**sift.themes**

id: UUID
user_id: UUID (references auth.users)
title: String
description: String?
active: Boolean (default true)
archived_at: Timestamp?
created_at: Timestamp

**sift.habits**

id: UUID
user_id: UUID (references auth.users)
title: String
full_criteria: String
partial_criteria: String
active: Boolean (default true)
archived_at: Timestamp?
created_at: Timestamp

**sift.habit_logs**

id: UUID
habit_id: UUID (references sift.habits)
date: Date
credit: Float (0, 0.5, or 1)

### Row Level Security
Every table must have RLS policies. Users can only read and write their own rows. Always apply RLS policies when creating tables.

---

## Core Features

### Entries
- Full screen writing surface, minimal chrome
- Entries expire after 7 days unless has_gem is true
- Actions can be flagged inline during writing
- On app open, check review triggers before opening entry

### Gems
- Flagged fragments from entries — verbatim, user's own words
- Optional theme association at moment of flagging — never required
- AI generates one sentence of connective tissue between gems per entry
- Dedicated searchable gems page — browse all gems, filter by theme
- Gems page is not Keep — it is just your saved fragments in one place

### Actions
- Flagged inline during writing
- Optional theme association at moment of creation — never required
- Carry forward mechanic — incomplete actions surface the next day
- Actions are temporary — they expire when completed or after a short TTL
- Actions surface on the Today screen

### Themes
- Focus areas, not goals — orientations, not finish lines
- Title and optional description
- Active and archived states — retire, never delete
- Gems and actions can be optionally connected to themes
- Visible during journaling as quiet context
- 90 day review trigger — opens a standard entry with a pre-written prompt
- Review is conducted entirely by the user — no AI involvement
- Track last_theme_review in public.user_settings

### Habits
- Simple daily habits with flexible credit model
- User defines what earns partial credit (0.5) and full credit (1.0)
- Credit is flexible — can represent staged success or composite behaviors
- Staged example: write anything = partial, write 1000 words = full
- Composite example: read = partial, journal = partial, both = full
- The app does not distinguish between these patterns — the user decides
- Logged daily: 0, 0.5, or 1
- Active and archived states — retire, never delete
- Calendar heat map per habit in habit detail view
- 14 day review trigger — opens a standard entry with a pre-written prompt
- Review is conducted entirely by the user — no AI involvement
- Track last_habit_review in public.user_settings
- If theme review and habit review fall on the same day, combine into one entry prompt that addresses both

### Review Ritual
- Triggered by elapsed time: 90 days for themes, 14 days for habits
- Check on every app open by comparing current date to last review timestamps
- Opens a standard entry with a pre-written, thoughtful prompt at the top
- The prompt is static — not AI generated
- The user writes freely in response — this is their reflection, not the AI's
- After entry is saved, update the relevant timestamp in user_settings
- Combined review: if both are due on the same day, one entry with one combined prompt covering both themes and habits
- No AI involvement in review — the ritual belongs to the user

---

## AI — Anthropic SDK

Use Claude Haiku for all AI tasks. Cost must stay minimal.

### AI jobs in Sift

Gem thread — when an entry has gems flagged, generate one sentence maximum describing the connective tissue between them. This is not a summary. It describes the relationship between gems, not the content of the entry.

### AI jobs explicitly NOT in Sift
- Theme-gem association — this is manual and optional, never inferred
- Review prompts — these are static, pre-written, not AI generated
- Daily prompts — removed from scope
- Any generation of content the user should have written themselves

### AI philosophy
- AI prompts, it never generates the thinking
- AI compresses, it never expands
- One sentence is always enough
- The AI is invisible infrastructure, not a feature to showcase

### AI cost profile

| Task | Model | Frequency |
|---|---|---|
| Gem thread generation | Haiku | Per entry with gems |

---

## Design System

### Philosophy
Sift is a designed artifact, not a native iOS system app. Content first. Space does the work color usually does. Accents are rare and meaningful.

### Typography
- SF Pro exclusively
- SF Pro Text for 19pt and below
- SF Pro Display for 20pt and above
- SwiftUI handles the variant switch automatically via system text styles

| Style | Size | Weight | Use |
|---|---|---|---|
| Title | 28pt | Medium | Screen headers |
| Headline | 20pt | Medium | Section labels |
| Body | 17pt | Regular | Entry text, primary content |
| Callout | 15pt | Regular | Secondary content, metadata |
| Caption | 13pt | Regular | Timestamps, labels |
| Micro | 11pt | Regular | Absolute minimum, use sparingly |

- Line height: 1.5x font size for body text
- Support Dynamic Type — never fix container heights against text

### Color
- Near monochrome palette
- One accent color for gems and meaningful moments only
- Everything else is neutral
- Dark mode primary

### Spacing
- Base unit: 8pt
- All spacing is a multiple of 8
- Screen edge margin: 20pt

| Token | Value |
|---|---|
| xs | 4pt |
| sm | 8pt |
| md | 16pt |
| lg | 24pt |
| xl | 32pt |
| 2xl | 48pt |

### Buttons

| Button | Height | Font | Padding H |
|---|---|---|---|
| Primary | 52pt | 17pt Medium | 24pt |
| Secondary | 44pt | 15pt Regular | 20pt |
| Ghost/Text | 44pt | 15pt Regular | 16pt |
| Icon button | 44×44pt | — | — |

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
- Sift — disposable journal (this app)
- Keep — personal knowledge graph (future)
- Forge — spatial brainstorming and publication (future)

### Shared primitive contract
The gem data shape is shared across all Aporian apps. Do not change the gem model without considering suite-wide implications. A gem in Sift must be recognizable to Keep and Forge when integration is built later.

### Shared identity
All Aporian apps share the same Supabase auth.users table. The user_id in every table is the same identity across the suite. Never create app-specific user tables.

### Keep-light features in Sift
The gems page with search and theme filtering is intentionally Keep-light. This is acceptable for v1. When Keep is built, gems will migrate naturally into the knowledge graph. Do not over-engineer the gems page — it is a simple searchable list, not a graph interface.

---

## Out of Scope for v1
- Web app
- Keep or Forge features
- Full knowledge graph
- Multimedia input
- Push notifications (consider v1.1)
- RevenueCat
- Stripe
- Cross-app data sharing
- AI-inferred theme associations
- AI-generated review prompts

---

## When in Doubt
- Choose simpler over clever
- Choose native Swift patterns over workarounds
- Build the entry screen first — it is the heart of the app
- If something feels like scope creep, it probably is
- The goal of v1 is to prove the feeling, not build every feature
- The user's thinking is always more important than the AI's output