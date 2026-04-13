## Entry Markdown Rebuild Notes

Purpose: preserve the current entry-editor behavior so the custom markdown implementation can be rebuilt quickly if we temporarily bypass it for crash isolation.

### Entry page structure

- Gratitude section uses `RichTextEditor`.
- Today's Focus section shows theme chips from `EntryViewModel.activeThemes`.
- Prompt flow:
  - `Get Today's Prompt` button stays disabled until at least one theme is selected.
  - Tapping it calls `EntryViewModel.fetchDailyPrompt()`.
  - Prompt persists per entry/day via `UserDefaults`.
  - Once present, prompt replaces the button with a card and refresh action.
- Entry body currently binds to `EntryViewModel.contentText`.

### MarkdownTextEditor behavior to preserve

- Plain body text supports freeform multiline writing.
- Headings:
  - `# ` renders as H1-style Newsreader italic heading.
  - `## ` renders as H2/P1-medium style heading.
- Gems:
  - `> ` creates a gem block.
  - Consecutive `> ` lines are treated as a single gem for persistence.
  - Gem block renders as a card with a gold leading accent bar.
- Actions:
  - Supports `- [ ] `, `- [x] `, `* [ ] `, `* [x] `.
  - Action blocks render as cards with a drawn checkbox.
  - Checkbox tap toggles completion in-place.
  - Completed actions render subdued with strikethrough on body text.
- Keyboard accessory actions:
  - `Gem` inserts `> `
  - `Action` inserts `- [ ] `
  - `H1` inserts `# `
  - `H2` inserts `## `
- Pressing return behavior:
  - On a gem line, return continues with another `> ` line.
  - On an empty gem marker line, return removes that line.
  - On an action line, return exits the action block.
  - On an empty action marker line, return removes that line.

### Persistence / sync behavior to preserve

- `EntryParser.parse(_:)` extracts:
  - gems from consecutive `> ` lines as one logical gem
  - actions from checklist lines
- `EntryViewModel.save()` updates the entry row and then syncs markdown entities:
  - gems table rows
  - action_items table rows
  - `has_gem` on the entry
- New gems are linked to currently selected Today's Focus themes via `gem_themes`.
- Action completion changes from Home/Day views are patched back into open entry content.

### Known implementation hotspots

- `MarkdownLayoutManager.drawBackground`
- `MarkdownGrowingTextView`
- `MarkdownTextEditor.updateUIView`
- repeated `reapplyMarkdownAttributes()` on populated entries
- intrinsic size / TextKit layout feedback loops

### Temporary isolation strategy

- If the entry screen freezes, first swap only the ENTRY body from `MarkdownTextEditor` to a plain `TextEditor`.
- Keep Gratitude, Today's Focus, prompt persistence, and entry loading intact.
- If freeze disappears, root cause is inside markdown editor/layout rather than entry data loading.
