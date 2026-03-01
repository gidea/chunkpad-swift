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

## Sprint 7: Settings + Polish ✅ Complete

**Goal:** Expose configurable search and generation parameters; add markdown rendering and pinned-chunk polish.
**Status:** ✅ Complete

### Tasks

#### 5.1 Configurable search parameters [P1] ✅

`hybridSearch` uses hardcoded `k: 10` and `minScore: 0.1` — no way to tune retrieval quality.

- [x] **5.1.1** Add `searchResultCount: Int` (default 10) and `searchMinScore: Double` (default 0.1) to `AppState`
- [x] **5.1.2** Persist both to `UserDefaults` via `saveToUserProfile` / `loadFromUserProfile`
- [x] **5.1.3** Pass both through `ChatViewModel.sendMessage` → `database.hybridSearch` (with clamping: k ∈ [1,20], minScore ∈ [0,1])
- [x] **5.1.4** Add Search section in SettingsView: TextField for max results, Slider for min relevance score 0.0–1.0
- [x] **5.1.5** Show current value inline next to each control

**Edge cases:**
- k = 0 → clamped to 1 in ChatViewModel before calling hybridSearch
- k > 20 → clamped to 20 to avoid context overflow
- minScore = 0 → returns all results including very low relevance

#### 5.2 API key validation ("Test" button) [P2] ✅

No feedback when a key is wrong until the first chat attempt fails.

- [x] **5.2.1** Add "Test API Key" button next to Anthropic API key field in SettingsView
- [x] **5.2.2** Anthropic: POST `/v1/messages` with `max_tokens: 1` — checks 200 vs 401
- [x] **5.2.3** Show inline checkmark/X with error message; ProgressView spinner while pending
- [x] **5.2.4** OpenAI: GET `/v1/models` — lightweight auth-only check
- [x] **5.2.5** Ollama: GET `{endpoint}/api/tags` with 5s timeout
- [x] **5.2.6** Validation resets to idle when key/endpoint changes

**Edge cases:**
- Network unavailable → error.localizedDescription shown inline
- Empty key → Test button disabled

#### 7.1 Markdown rendering for assistant responses [P2] ✅

Assistant responses use monospace plain text — headers, bold, lists look broken.

- [x] **7.1.1** Replace `Text(message.content)` with `MarkdownContentView` for assistant messages only
- [x] **7.1.2** Code blocks render in `.system(.body, design: .monospaced)` with `.quaternary.opacity(0.3)` background and optional language label
- [x] **7.1.3** Inline markdown (bold, italic, code, links) via `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)`

**Edge cases:**
- Malformed markdown → graceful fallback to plain `AttributedString(text)`
- Unclosed code fences → treated as regular text
- User messages remain plain text (no markdown parsing)

#### 5.3 Configurable LLM parameters [P2] ✅

Temperature and max tokens are hardcoded in BundledLLMService.

- [x] **5.3.1** Add `llmTemperature: Double` (default 0.7) and `llmMaxTokens: Int` (default 4096) to AppState
- [x] **5.3.2** Persist both to UserDefaults
- [x] **5.3.3** Add `temperature` and `maxTokens` to `CloudConfig` and `LocalConfig`; thread through factory to all 4 clients (Anthropic, OpenAI, Ollama, BundledLLM)
- [x] **5.3.4** Add "LLM Parameters" section in SettingsView: Slider for temperature (0–1), TextField for max tokens
- [x] **5.3.5** Thread through `AppState.resolvedProvider()` and `ChatViewModel.makeBundledProvider()`

#### 7.2 Distinguish pinned chunks visually [P2] ✅

Pinned chunks look identical to retrieved chunks — no visual cue.

- [x] **7.2.1** Add `isPinned: Bool = false` to `ScoredChunk`
- [x] **7.2.2** Set `isPinned = true` for chunks added via `addPinnedChunks`
- [x] **7.2.3** Show pin icon badge on `ChunkPreview` header when `isPinned`; "Pinned" pill replaces score percentage
- [x] **7.2.4** Orange-tinted glass effect background for pinned cards
