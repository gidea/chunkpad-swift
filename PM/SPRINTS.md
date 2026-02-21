# Chunkpad — Active Sprint

> **One sprint at a time.** This file contains only the current sprint.
> When the sprint is done, move its entire content block to `DONE.md` and paste the next sprint here.
>
> **Rules:**
> - Expand tasks from `BACKLOG.md` here with full subtasks, edge cases, and implementation notes.
> - Mark subtasks `[x]` as they complete.
> - Mark tasks ✅ when all subtasks are done.
> - Mark the sprint ✅ Complete when all tasks are done, then move it to `DONE.md`.

---

## Sprint 7: Settings + Polish

**Goal:** Expose configurable search and generation parameters; add markdown rendering and pinned-chunk polish.
**Status:** ← Next (not started)

### Tasks

#### 5.1 Configurable search parameters [P1]

`hybridSearch` uses hardcoded `k: 10` and `minScore: 0.1` — no way to tune retrieval quality.

- [ ] **5.1.1** Add `searchResultCount: Int` (default 10) and `searchMinScore: Double` (default 0.1) to `AppState`
- [ ] **5.1.2** Persist both to `UserDefaults` via `saveToUserProfile` / `loadFromUserProfile`
- [ ] **5.1.3** Pass both through `ChatViewModel.sendMessage` → `database.hybridSearch`
- [ ] **5.1.4** Add sliders in SettingsView: "Results returned (k)" 5–20, "Min relevance score" 0.0–0.5
- [ ] **5.1.5** Show current value inline next to each slider

**Edge cases:**
- k = 0 → guard against empty results; k > 20 → cap at 20 to avoid context overflow
- minScore = 0 → return all results including very low relevance

#### 5.2 API key validation ("Test" button) [P2]

No feedback when a key is wrong until the first chat attempt fails.

- [ ] **5.2.1** Add "Test" button next to Anthropic API key field in SettingsView
- [ ] **5.2.2** Button calls a lightweight API ping (e.g. list models or minimal chat completion)
- [ ] **5.2.3** Show inline ✅ or ❌ with error message; spinner while pending
- [ ] **5.2.4** Repeat for OpenAI key
- [ ] **5.2.5** For Ollama: ping `{endpoint}/api/tags` and show model count or error

**Edge cases:**
- Network unavailable → clear error message, not crash
- Empty key → button disabled

#### 7.1 Markdown rendering for assistant responses [P2]

Assistant responses use monospace plain text — headers, bold, lists look broken.

- [ ] **7.1.1** Render `Message.content` with SwiftUI's `.init(_ attributedContent:)` or `Text` with markdown support
- [ ] **7.1.2** Ensure code blocks use monospaced font with background
- [ ] **7.1.3** Test with headers, bullet lists, bold, inline code

**Edge cases:**
- Very long responses with many headers → layout performance
- Malformed markdown → graceful fallback to plain text

#### 5.3 Configurable LLM parameters [P2]

Temperature and max tokens are hardcoded in BundledLLMService.

- [ ] **5.3.1** Add `llmTemperature: Float` (default 0.7) and `llmMaxTokens: Int` (default 2048) to AppState
- [ ] **5.3.2** Persist both to UserDefaults
- [ ] **5.3.3** Pass through `LocalConfig` / `CloudConfig` to each LLM client
- [ ] **5.3.4** Add controls in SettingsView under each provider section

#### 7.2 Distinguish pinned chunks visually [P2]

Pinned chunks look identical to retrieved chunks — no visual cue.

- [ ] **7.2.1** Add `isPinned: Bool` to `ScoredChunk`
- [ ] **7.2.2** Set `isPinned = true` for chunks added via `addPinnedChunks`
- [ ] **7.2.3** Show pin icon badge on `ChunkPreview` when `isPinned`
- [ ] **7.2.4** Optionally use distinct background tint for pinned cards
