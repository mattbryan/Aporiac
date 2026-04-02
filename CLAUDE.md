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