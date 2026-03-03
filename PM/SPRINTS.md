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

## Sprint 9: Chat UX + Cleanup ✅ Complete

**Goal:** Fix streaming scroll, add context budget enforcement, always-visible pinning, and clean up tech debt.
**Status:** Complete

### Tasks

#### 4.2.3 Throttled streaming scroll [P1] ✅

Scroll only fires once at the start of generation. As the assistant response grows token by token, new text appears below the fold.

- [x] **4.2.3.1** Add a throttled scroll-to-bottom during streaming — Timer.publish(every: 0.3) + onReceive scrolls to "bottom" anchor
- [x] **4.2.3.2** Guard on `isGenerating` — timer fires continuously but only scrolls when generating
- [x] **4.2.3.3** Stop the timer when `isGenerating` flips to false — guard statement in onReceive

#### 4.4.4 Auto-truncate context to budget [P2] ✅

No token estimation or budget enforcement. Oversized context causes API errors.

- [x] **4.4.4.1** Add `estimateTokens(_:)` helper (chars / 4 approximation)
- [x] **4.4.4.2** In `buildContext`, calculate total tokens for included chunks; drop lowest-relevance non-pinned chunks until under `contextSize × 0.8`
- [x] **4.4.4.3** Track dropped chunk count via `droppedChunkCount` property
- [x] **4.4.4.4** Always keep at least 1 chunk; never drop pinned chunks

#### 7.4 Pre-query document pinning [P2] ✅

Pin button is hidden until first query because it's inside `chunksBar`, which only renders when `retrievedChunks` is non-empty.

- [x] **7.4.1** Add persistent pin button in `inputBar` — always visible, uses `pin`/`pin.fill` icon
- [x] **7.4.2** Opens PinDocumentsSheet same as current flow (loadIndexedDocuments → sheet)
- [x] **7.4.3** Show pinned document count badge (orange circle) on the button when pins are active

#### 8.1 Extract shared generation task code [P1] ✅

`sendMessage` and `regenerate` duplicate ~40 lines of streaming, cancellation, error classification, and DB persistence logic.

- [x] **8.1.1** Extract `runGeneration(client:contextMessages:assistantIndex:)` private method
- [x] **8.1.2** Both `sendMessage` and `regenerate` call the shared method
- [x] **8.1.3** Error handling, cancellation, and DB persistence remain identical

#### 8.2 Fix compiler warnings in ChatView [P1] ✅

Two unused `provider` bindings in `retryLastMessage()` generate compiler warnings.

- [x] **8.2.1** Replace `if let provider = viewModel.pendingRetryProvider` with `if viewModel.pendingRetryProvider != nil`
- [x] **8.2.2** Replace `if let provider = appState.resolvedProvider()` with `if appState.resolvedProvider() != nil`

#### 8.3 Remove dead indexFolder code path [P2] ✅

`selectAndIndexFolder()` and `indexFolder()` are never called from any View. The current flow is process → review → embed.

- [x] **8.3.1** Remove `selectAndIndexFolder()` and `indexFolder()` from IndexingViewModel (~100 lines)
- [x] **8.3.2** Verified no remaining references

#### 7.6 Update README.md project structure [P2] ✅

7 files missing from the structure diagram: ChunkFileTree, IndexedFolder, BookmarkService, ChunkFileService, ConversationDatabaseService, KeychainHelper, ChunkStatusBadge.

- [x] **7.6.1** Add all 7 missing files to the project structure diagram with brief descriptions; alphabetize entries within each section
