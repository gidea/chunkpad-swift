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

## Completed Epics

All epics through Epic 12 (Sprints 1–13) are complete. See `DONE.md` for full history.

| Epic | Focus | Sprints |
|---|---|---|
| Epic 2 | Documents Library | Sprints 2, 8, 11 |
| Epic 3 | Model Download Management | Sprint 5 |
| Epic 4 | Chat & RAG Pipeline | Sprints 4, 8, 9 |
| Epic 5 | Settings & Configuration | Sprints 7, 10 |
| Epic 6 | Error Handling & Resilience | Sprint 6 |
| Epic 7 | Polish & UX | Sprints 7, 9, 10 |
| Epic 8 | Code Quality & Cleanup | Sprint 9 |
| Epic 9 | UX Robustness & Feedback | Sprint 10 |
| Epic 10 | Embedding Model Upgrade | Sprint 12 |
| Epic 11 | Chunk File Naming Fix | Sprint 12 |
| Epic 12 | Document Parsing & Chunking | Sprint 13 |

---

## Epic 13: Document Collections

> **Goal:** Let users organize indexed documents into named collections (e.g. "Q1 Sales Materials", "Marketing Assets") and scope chat sessions to a specific collection so retrieval only pulls from relevant documents.

### Problem

Today all indexed documents live in a single flat pool. When a user searches, `hybridSearch` queries every chunk in the database. A sales team member asking about proposal pricing gets chunks from marketing drafts, internal memos, and customer success playbooks mixed in — diluting relevance and wasting context budget. There is no way to partition the knowledge base.

### Inspiration

- **ChatGPT Projects** — scoped conversations with attached files
- **Slack channel scoping** — each channel has its own context

### User Stories

1. As a user, I want to create a named collection (e.g. "Sales 2025") so I can group related documents together.
2. As a user, I want to assign documents to a collection when indexing (or move them later) so my knowledge base is organized.
3. As a user, I want to scope a chat conversation to a collection so retrieval only searches within that collection's documents.
4. As a user, I want chunks to carry collection metadata so I can see which collection a chunk belongs to in search results.
5. As a user, I want to switch collections mid-session or search across all collections when I need broader context.

### Design Decisions

- A collection is a lightweight label, not a filesystem concept. Documents can belong to one collection (simplest model) or optionally multiple (deferred to v2).
- The default collection is "All Documents" — the current behavior, so the feature is backward-compatible.
- Collection metadata is stored in the database and propagated to `vec_chunks` and `chunks_fts` for filtered search.
- Conversations can be scoped to a collection via `AppState` or per-conversation metadata.

### Tasks

#### 13.1 Database schema for collections [P0]
- Add `collections` table (`id TEXT PK, name TEXT UNIQUE NOT NULL, created_at TEXT, color TEXT`)
- Add `collection_id TEXT` foreign key to `documents` table (nullable — null means "uncategorized")
- Add `collection_id TEXT` column to `vec_chunks` and `chunks_fts` for filtered search
- Schema migration (bump version) with backward-compatible defaults (existing docs get NULL collection)

#### 13.2 Collection CRUD in DatabaseService [P0]
- `createCollection(name:, color:)` → `Collection`
- `fetchCollections()` → `[Collection]`
- `renameCollection(id:, name:)`
- `deleteCollection(id:)` — moves documents to uncategorized, does not delete documents
- `assignDocumentToCollection(documentId:, collectionId:)`
- `removeDocumentFromCollection(documentId:)` — sets collection_id to NULL

#### 13.3 Collection model [P1]
- `Collection` struct (`id`, `name`, `createdAt`, `color`, `documentCount`)
- Add to `ScoredChunk` or `Chunk`: optional `collectionName` for display in ChunkPreview

#### 13.4 Filtered hybrid search [P0]
- Extend `hybridSearch` with optional `collectionId: String?` parameter
- When set: add `WHERE collection_id = ?` clause to both vec_chunks KNN and FTS5 queries
- When nil: search all documents (current behavior preserved)

#### 13.5 Collection picker in Chat toolbar [P1]
- Add a collection scope picker alongside the generation mode picker in the ChatView toolbar
- Options: "All Documents" (default) + each user collection
- Bind to `ChatViewModel` so `sendMessage` passes the selected collection to `hybridSearch`
- Show collection name in the conversation sidebar for scoped conversations

#### 13.6 Collection management UI in Documents view [P1]
- Collection list/sidebar in Documents view (above or alongside folder list)
- "New Collection" button with name + optional color input
- Drag-and-drop or context menu to assign documents to collections
- Badge showing document count per collection
- Context menu: rename, delete collection

#### 13.7 Collection assignment during indexing [P2]
- After "Add Folder" processing, prompt user to assign the new documents to a collection
- Optional: auto-assign if a default collection is set
- Bulk assignment for all documents from a folder

#### 13.8 Collection metadata in chunk display [P2]
- Show collection name pill/badge in `ChunkPreview` cards (chunks bar)
- Show collection name in the regenerate bar summary
- Color-code chunks by collection for visual differentiation

#### 13.9 Persist conversation-collection scope [P3]
- Store `collection_id` on the conversation record in `chunkpad_chat.db`
- When loading a past conversation, restore its collection scope
- Show scoped collection name in conversation sidebar row

---

## Epic 14: Context Preview Before Send

> **Goal:** Give the user full visibility and control over which documents and chunks will be sent to the LLM *before* the message is dispatched, preventing accidental context overload and giving confidence in what the model will see.

### Problem

Today the user types a question and presses Enter — then the RAG pipeline runs (embed query → search → build context → send to LLM) as a single atomic operation. The user has no opportunity to review, filter, or adjust the retrieved context before it reaches the model. They only see the chunks bar *after* the response arrives, at which point the tokens are already spent. For users with large knowledge bases, this can lead to irrelevant context flooding the prompt, wasted API tokens, and poor response quality.

### Inspiration

- Pre-flight context preview cards (similar to email attachment previews)
- Search-then-compose workflows (search first, then write the prompt with selected results)

### User Stories

1. As a user, I want to preview which documents and chunks will be used *before* I send my message so I can remove irrelevant ones.
2. As a user, I want to see a summary like "This question will use 6 documents (14 chunks, ~3,200 tokens)" before sending.
3. As a user, I want to search my knowledge base independently from sending a message so I can curate the context.
4. As a user, I want to adjust retrieval strictness (min relevance score) on the fly without going to Settings.
5. As a user, I want to remove entire documents from the preview (not just individual chunks) for faster curation.

### Design Decisions

- The new flow is: **type query → search preview → review/adjust → send**. This replaces the current atomic send.
- A collapsible **search panel** sits above the text input. The user can trigger a search without sending, review results, then send when satisfied.
- The existing chunks bar (post-response) remains for regeneration. The search panel is for pre-send curation.
- The search panel reuses `hybridSearch` and the existing `ScoredChunk` model.
- Quick-adjust controls (retrieval strictness slider, document removal) live inline in the panel — no Settings navigation needed.

### Tasks

#### 14.1 Search-before-send flow [P0]
- Add a "Search" button (magnifying glass) next to the text input that triggers `hybridSearch` without sending to the LLM
- Populate a new `previewChunks: [ScoredChunk]` array in `ChatViewModel` (separate from `retrievedChunks`)
- Show results in a collapsible search panel above the input bar
- "Send" button changes to "Send with N chunks" when preview chunks are loaded
- Pressing Enter with no preview runs the old atomic flow (backward-compatible); pressing Enter with an active preview sends with the curated chunks

#### 14.2 Search panel UI [P0]
- Expandable/collapsible panel above the input bar (default: collapsed)
- When expanded, shows:
  - Summary header: "6 documents · 14 chunks · ~3,200 tokens"
  - Horizontal or vertical list of chunk cards (reuse `ChunkPreview` component)
  - Each chunk has include/exclude toggle (same as current chunks bar)
  - Token budget indicator (green/orange/red based on context size)
- Collapse/expand chevron toggle
- Panel auto-expands when search results arrive; auto-collapses on send

#### 14.3 Document-level grouping and removal [P1]
- Group chunks by source document in the search panel
- Show document header row: file name, chunk count, total tokens, remove button
- "Remove document" excludes all its chunks at once (sets `isIncluded = false`)
- Collapsed view: just document names + chunk counts (expandable to individual chunks)

#### 14.4 Inline retrieval controls [P1]
- Mini slider for minimum relevance score (within the search panel, not in Settings)
- Changes apply immediately — re-filter `previewChunks` by new threshold (client-side filter, no re-search)
- Show current value: "Min relevance: 0.40"
- "Re-search" button to re-run `hybridSearch` if the user wants fresh results with different params

#### 14.5 Collection switcher in search panel [P2]
- If Epic 13 (Document Collections) is implemented, show collection picker inline in the search panel
- Switching collection triggers a new search within that scope
- Visual indicator of which collection is active

#### 14.6 Context budget visualization [P2]
- Progress bar or ring showing token usage vs. budget (80% of `contextSize`)
- Color coding: green (<50%), orange (50-80%), red (>80% — will trigger auto-truncation)
- Show exact numbers: "~3,200 / 3,277 tokens (80% of 4,096 budget)"
- Warning text when over budget: "N chunks will be auto-trimmed"

#### 14.7 Keyboard shortcuts [P3]
- `Cmd+K` or `Cmd+Shift+F` to focus the search panel and trigger a search
- `Cmd+Enter` to send with current preview (already exists as backup submit)
- `Escape` to dismiss/collapse the search panel
- Tab navigation through chunk toggles

#### 14.8 Search panel state management [P2]
- `previewChunks` cleared on send (search panel collapses, chunks bar takes over post-response)
- Search panel state is per-conversation (switching conversations clears preview)
- Search panel preserves state during collection/strictness adjustments (no re-search unless explicit)

---

*Add new epics below as they are identified.*
