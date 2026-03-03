# Chunkpad — Product Backlog

> **The backlog is intentionally lean.** Each epic lists its goal and tasks at a high level with priorities.
> Detailed subtasks, edge cases, and implementation notes live in `SPRINTS.md` (active sprint) or `DONE.md` (completed sprints).
>
> **Rules:**
> - When planning a sprint: copy epic tasks from here into `SPRINTS.md`, expand with subtasks there.
> - When a sprint completes: move it from `SPRINTS.md` to `DONE.md`.
> - Never add implementation details or `[x]` marks here — this file stays forward-looking.

---

## Priority Legend

| Label | Meaning |
|---|---|
| P0 | Blocking / must ship |
| P1 | High value, do next |
| P2 | Medium value |
| P3 | Nice-to-have / polish |

---

## Epic 2: Documents Library ✅ (Sprint 11 complete)

**Goal:** Robust document management — browsable, searchable, fully lifecycle-managed.

*Tasks 2.3, 2.5.1, 2.6 shipped in Sprint 8. Task 2.4.3 shipped in Sprint 11. See `DONE.md` for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~2.3 Chunk grid/list view overhaul~~ | ~~P1~~ | ✅ Done — View mode toggle, grid cards, filter bar |
| ~~2.5.1 Persist lastKnownModificationDates to DB~~ | ~~P2~~ | ✅ Done — UserDefaults persistence with didSet |
| ~~2.6 Delete individual documents/chunks~~ | ~~P2~~ | ✅ Done — Context menus, confirmation alerts, cascade delete |
| ~~2.4.3 Per-folder aggregate status badge~~ | ~~P3~~ | ✅ Done — Recursive folder status with colored dot in sidebar |

---

## Epic 3: Model Download Management ✅ (Sprint 5 complete)

**Goal:** Transparent, resilient, cancellable model downloads with cache management.

*All Sprint 5 tasks shipped. See `DONE.md` Sprint 5 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~3.1.6 Guard in BundledLLMService.downloadAndLoad~~ | ~~P1~~ | ✅ Done |
| ~~3.2 Download cancellation~~ | ~~P1~~ | ✅ Done — cancelDownload(), Cancel button in Settings |
| ~~3.3 Download retry logic~~ | ~~P1~~ | ✅ Done — 3× backoff, .retrying status |
| ~~3.5 Cache management UI~~ | ~~P1~~ | ✅ Done — size display, Clear Cache buttons |
| ~~3.6 Cache integrity verification~~ | ~~P2~~ | ✅ Done — on-launch check, Verify Cache button |
| ~~3.4 Disk space validation~~ | ~~P2~~ | ✅ Done — pre-check before download |
| ~~3.7.1–3.7.2 Callback cleanup~~ | ~~P2~~ | ✅ Done — clearStatusCallback() on both services |

---

## Epic 4: Chat & RAG Pipeline ✅ (Sprint 9 complete)

**Goal:** Reliable chat with correct RAG, context management, and resilient streaming.

*Tasks 4.6–4.7 shipped in Sprint 8. Tasks 4.2.3, 4.4.4 shipped in Sprint 9. See `DONE.md` for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~4.2.3 Throttled streaming scroll~~ | ~~P1~~ | ✅ Done — Timer.publish(every: 0.3) + onReceive auto-scroll |
| ~~4.4.4 Auto-truncate context to budget~~ | ~~P2~~ | ✅ Done — estimateTokens, drop lowest-relevance non-pinned chunks |
| ~~4.6 Persist pinned document IDs~~ | ~~P2~~ | ✅ Done — AppState persistence, validation on load |
| ~~4.7 Conversation management UX~~ | ~~P2~~ | ✅ Done — Swipe-delete, rename, message count |

---

## Epic 5: Settings & Configuration ✅ (Sprint 10 complete)

**Goal:** All configurable params exposed, validated, clearly connected to features.

*Tasks 5.1–5.3 shipped in Sprint 7. Task 5.4 shipped in Sprint 10. See `DONE.md` for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~5.1 Configurable search parameters (k, minScore)~~ | ~~P1~~ | ✅ Done — Slider + TextField in Settings, clamped in ChatViewModel |
| ~~5.2 API key validation ("Test" button)~~ | ~~P2~~ | ✅ Done — Test buttons for Anthropic, OpenAI, Ollama |
| ~~5.3 Configurable LLM parameters (temp, maxTokens)~~ | ~~P2~~ | ✅ Done — Threaded through all 4 LLM clients |
| ~~5.4 Database management in Settings~~ | ~~P3~~ | ✅ Done — Size, chunk count, clear action with confirmation |

---

## Epic 6: Error Handling & Resilience ✅ (Sprint 6 complete)

**Goal:** Every error visible to user with a clear recovery path. No silent failures.

*All Sprint 6 tasks shipped. See `DONE.md` Sprint 6 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~6.1 App initialization error handling~~ | ~~P0~~ | ✅ Done — AppState.initError, MainView banner + Retry |
| ~~6.2 Embedding model error recovery~~ | ~~P1~~ | ✅ Done — Clear Cache & Retry button in DocumentsView |
| ~~6.3.4 Retry individual parse-failed files~~ | ~~P2~~ | ✅ Done — skippedFiles list with per-file Retry buttons |
| ~~6.4 Network error handling for LLM streaming~~ | ~~P2~~ | ✅ Done — connectionLost/rateLimited classification + Retry |

---

## Epic 7: Polish & UX ✅ (Sprint 10 complete)

**Goal:** Quality-of-life improvements that make the app feel polished.

*Tasks 7.1–7.2 shipped in Sprint 7. Tasks 7.4, 7.6 shipped in Sprint 9. Tasks 7.3, 7.5 shipped in Sprint 10. See `DONE.md` for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~7.1 Markdown rendering for assistant responses~~ | ~~P2~~ | ✅ Done — MarkdownContentView with code block support |
| ~~7.2 Distinguish pinned chunks visually~~ | ~~P2~~ | ✅ Done — Pin icon, orange tint, "Pinned" pill |
| ~~7.4 Pre-query document pinning~~ | ~~P2~~ | ✅ Done — Always-visible pin button in inputBar with badge |
| ~~7.6 Update README.md project structure~~ | ~~P2~~ | ✅ Done — 7 missing files added to structure diagram |
| ~~7.3 Collapsible chunks bar~~ | ~~P3~~ | ✅ Done — Chevron toggle, compact summary with token estimate |
| ~~7.5 Generation mode indicator~~ | ~~P3~~ | ✅ Done — Green/gray dot per provider in toolbar picker |

---

## Epic 8: Code Quality & Cleanup ✅ (Sprint 9 complete)

**Goal:** Eliminate tech debt, remove dead code, fix compiler warnings.

*All tasks shipped in Sprint 9. See `DONE.md` Sprint 9 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~8.1 Extract shared generation task code~~ | ~~P1~~ | ✅ Done — runGeneration() shared method |
| ~~8.2 Fix compiler warnings in ChatView~~ | ~~P1~~ | ✅ Done — Replaced unused let bindings with != nil |
| ~~8.3 Remove dead indexFolder code path~~ | ~~P2~~ | ✅ Done — ~100 lines removed from IndexingViewModel |

---

## Epic 9: UX Robustness & Feedback ✅ (Sprint 10 complete)

**Goal:** Surface hidden state to users, fix edge-case UX gaps, improve feedback loops.

*All tasks shipped in Sprint 10. See `DONE.md` Sprint 10 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~9.1 Surface droppedChunkCount in regenerate bar~~ | ~~P2~~ | ✅ Done — Orange "N trimmed to fit budget" in regenerate bar |
| ~~9.2 Validate pinned docs after delete~~ | ~~P2~~ | ✅ Done — NotificationCenter post + MainView listener |
| ~~9.3 Auto-clear chunk filter on file switch~~ | ~~P3~~ | ✅ Done — onChange(of: selectedNodeID) clears filter |

---

## Recommended Sprint Order

| Sprint | Focus | Key Tasks |
|---|---|---|
| ~~**Sprint 5**~~ | ~~Model Management~~ | ✅ Complete |
| ~~**Sprint 6**~~ | ~~Error Handling~~ | ✅ Complete |
| ~~**Sprint 7**~~ | ~~Settings + Polish~~ | ✅ Complete |
| ~~**Sprint 8**~~ | ~~Documents Polish~~ | ✅ Complete |
| ~~**Sprint 9**~~ | ~~Chat UX + Cleanup~~ | ✅ Complete |
| ~~**Sprint 10**~~ | ~~Final Polish~~ | ✅ Complete |
