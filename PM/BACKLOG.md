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

## Epic 2: Documents Library (partial — Sprint 8 complete)

**Goal:** Robust document management — browsable, searchable, fully lifecycle-managed.

*Tasks 2.3, 2.5.1, 2.6 shipped in Sprint 8. See `DONE.md` Sprint 8 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~2.3 Chunk grid/list view overhaul~~ | ~~P1~~ | ✅ Done — View mode toggle, grid cards, filter bar |
| ~~2.5.1 Persist lastKnownModificationDates to DB~~ | ~~P2~~ | ✅ Done — UserDefaults persistence with didSet |
| ~~2.6 Delete individual documents/chunks~~ | ~~P2~~ | ✅ Done — Context menus, confirmation alerts, cascade delete |
| 2.4.3 Per-folder aggregate status badge | P3 | Depends on 2.3 folder list |

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

## Epic 4: Chat & RAG Pipeline (partial — Sprint 8 complete)

**Goal:** Reliable chat with correct RAG, context management, and resilient streaming.

*Tasks 4.6–4.7 shipped in Sprint 8. See `DONE.md` Sprint 8 for details.*

| Task | Priority | Notes |
|---|---|---|
| 4.2.3 Throttled streaming scroll | P2 | Per-token auto-scroll throttle |
| 4.4.4 Auto-truncate context to budget | P2 | Chunk by relevance until contextSize |
| ~~4.6 Persist pinned document IDs~~ | ~~P2~~ | ✅ Done — AppState persistence, validation on load |
| ~~4.7 Conversation management UX~~ | ~~P2~~ | ✅ Done — Swipe-delete, rename, message count |

---

## Epic 5: Settings & Configuration (partial — Sprint 7 complete)

**Goal:** All configurable params exposed, validated, clearly connected to features.

*Tasks 5.1–5.3 shipped in Sprint 7. See `DONE.md` Sprint 7 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~5.1 Configurable search parameters (k, minScore)~~ | ~~P1~~ | ✅ Done — Slider + TextField in Settings, clamped in ChatViewModel |
| ~~5.2 API key validation ("Test" button)~~ | ~~P2~~ | ✅ Done — Test buttons for Anthropic, OpenAI, Ollama |
| ~~5.3 Configurable LLM parameters (temp, maxTokens)~~ | ~~P2~~ | ✅ Done — Threaded through all 4 LLM clients |
| 5.4 Database management in Settings | P3 | Size, count, clear, export |

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

## Epic 7: Polish & UX (partial — Sprint 7 complete)

**Goal:** Quality-of-life improvements that make the app feel polished.

*Tasks 7.1–7.2 shipped in Sprint 7. See `DONE.md` Sprint 7 for details.*

| Task | Priority | Notes |
|---|---|---|
| ~~7.1 Markdown rendering for assistant responses~~ | ~~P2~~ | ✅ Done — MarkdownContentView with code block support |
| ~~7.2 Distinguish pinned chunks visually~~ | ~~P2~~ | ✅ Done — Pin icon, orange tint, "Pinned" pill |
| 7.5 Generation mode indicator (dot per provider) | P3 | Green = configured, gray = not |
| 7.3 Collapsible chunks bar | P3 | Chevron toggle, compact summary |
| 7.4 Pre-query document pinning | P3 | Always-visible pin button |
| 7.6 Update README.md project structure | P2 | Add new files to structure diagram |

---

## Recommended Sprint Order

| Sprint | Focus | Key Tasks |
|---|---|---|
| ~~**Sprint 5**~~ | ~~Model Management~~ | ✅ Complete |
| ~~**Sprint 6**~~ | ~~Error Handling~~ | ✅ Complete |
| ~~**Sprint 7**~~ | ~~Settings + Polish~~ | ✅ Complete |
| ~~**Sprint 8**~~ | ~~Documents Polish~~ | ✅ Complete |
