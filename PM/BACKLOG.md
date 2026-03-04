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

## Epic 15: Turn Chat Into Asset

> **Goal:** Transform any chat response from disposable conversation into a reusable knowledge artifact — exportable as a document and indexable back into the knowledge base for future retrieval.

### Problem

Today, chat responses are trapped inside the conversation database. A user who drafts a proposal, summarizes a document set, or builds a comparison table in chat has no way to extract that work as a standalone file. The output dies in the conversation list. Worse, that generated knowledge can never feed back into future queries — the user's own synthesized insights are invisible to the RAG pipeline.

This creates a one-way flow: documents → chunks → answers → nowhere. Turning chat into an asset closes the loop: documents → chunks → answers → new documents → richer future answers.

### Inspiration

- **ChatGPT "Save as"** — export conversations to markdown/PDF
- **Notion AI** — AI-generated content becomes part of the workspace, queryable alongside other pages
- **Knowledge management flywheel** — outputs become inputs for future queries

### User Stories

1. As a user, I want to copy a single assistant response as clean markdown to my clipboard so I can paste it into an email or document.
2. As a user, I want to export an entire conversation as a markdown file so I have a standalone record of the Q&A session.
3. As a user, I want to export a conversation as a .docx file so I can share it with colleagues who use Word.
4. As a user, I want to save an assistant response directly into my indexed knowledge base so future searches can find and reference it.
5. As a user, I want to see which chat exports are already indexed so I know my knowledge base is growing from my own work.

### Design Decisions

- **Three export targets**: clipboard (instant), file (markdown or docx), and knowledge base (re-index).
- **Single-message and full-conversation exports** are both supported. Single-message is the common case (copy one good answer); full-conversation is for archival.
- **Re-indexing into the knowledge base** writes a markdown file to a designated exports folder, then processes and embeds it through the existing indexing pipeline. This reuses `DocumentProcessor` and `IndexingViewModel` — no new indexing code needed.
- **Markdown is the canonical format** since assistant responses are already stored as markdown in `message.content` and rendered via `MarkdownContentView`. Export is essentially writing the raw content to a file.
- **DOCX conversion** uses macOS `textutil` (the same tool `DocumentProcessor` already uses for import, but in reverse — markdown → HTML → DOCX).
- **Provenance metadata** (conversation title, date, source chunks) is included as frontmatter or a header section in exports so the origin is traceable.

### Tasks

#### 15.1 Copy single message to clipboard [P0]
- Add context menu "Copy as Markdown" on assistant message bubbles (`MessageBubble`)
- Use `NSPasteboard.general` to copy `message.content` as both plain text and markdown
- Also add "Copy as Plain Text" option that strips markdown formatting
- Visual confirmation: brief "Copied" toast or checkmark animation

#### 15.2 Copy full conversation to clipboard [P1]
- Add toolbar button or menu item "Copy Conversation" in ChatView
- Format: sequential messages with role headers (`## You`, `## Assistant`) and timestamps
- Include conversation title and date as a header
- Exclude system messages (internal RAG context)

#### 15.3 Export conversation as markdown file [P0]
- Add "Export as Markdown…" menu item or toolbar button in ChatView
- Use `NSSavePanel` for user-selected save location (default filename: `{conversation-title}.md`)
- Format: YAML frontmatter (`title`, `date`, `model`, `chunk_count`) followed by message content
- Include a "Sources" section at the end listing referenced chunk IDs and source document paths
- Handle conversations with no title gracefully (use date-based fallback name)

#### 15.4 Export conversation as .docx [P2]
- Add "Export as Word Document…" option alongside markdown export
- Pipeline: render conversation as markdown → convert to HTML → use `textutil -convert docx` (same tool used by `DocumentProcessor` for import)
- Include basic formatting: headings for role labels, monospace for code blocks
- `NSSavePanel` with `.docx` default extension

#### 15.5 Save response to knowledge base [P1]
- Add context menu "Save to Knowledge Base" on assistant message bubbles
- Create a designated exports folder: `~/Library/Application Support/Chunkpad/exports/`
- Write the response as `{conversation-title}-{timestamp}.md` with metadata header
- Metadata header includes: conversation title, date, query that produced it, source chunk IDs
- Run through existing `DocumentProcessor.processFile()` → `DatabaseService.insertDocumentWithChunks()` → `EmbeddingService.embed()` pipeline
- Show progress indicator during embedding (reuse existing embedding progress UI)
- On success: show confirmation with link to view in Documents tab

#### 15.6 Save full conversation to knowledge base [P2]
- Same as 15.5 but exports all messages (user questions + assistant responses)
- Format: each Q&A pair as a section with heading (`## Question: {first line}`)
- Chunking naturally splits by Q&A sections (existing section-aware chunking handles `##` headings)
- User can review chunks before embedding (existing two-step pipeline)

#### 15.7 Export indicators and management [P2]
- Track exported/saved-to-KB conversations with a marker in the conversation sidebar (e.g. small document icon or "Indexed" badge)
- Store export state in conversation metadata (new column `exported_at TEXT` in conversations table, or a separate `conversation_exports` table)
- Prevent duplicate re-indexing: warn if the same conversation was already saved to KB
- Show "View in Documents" link when a conversation has been indexed

#### 15.8 Batch export [P3]
- Multi-select conversations in the sidebar for bulk export
- "Export Selected as Markdown" writes individual `.md` files or a single combined file
- "Save Selected to Knowledge Base" processes all selected conversations through the indexing pipeline
- Progress bar for multi-conversation operations

#### 15.9 Export settings [P3]
- Settings section: "Exports"
- Configurable exports folder path (default: `~/Library/Application Support/Chunkpad/exports/`)
- Toggle: include source chunk references in exports (default: on)
- Toggle: include timestamps in exports (default: on)
- Toggle: auto-assign exports to a collection (depends on Epic 13)

---

## Epic 16: Retrieval Feedback Loop

> **Goal:** Let users permanently mark chunks as irrelevant (hide) or valuable (boost) so the retrieval system learns from usage patterns and improves over time — delivering better context with less manual curation on every future query.

### Problem

Today, chunk relevance is calculated fresh on every query using a static formula (70% vector similarity + 30% FTS5 keyword match). The system has no memory of past interactions. A user who repeatedly excludes the same noisy chunk from marketing boilerplate must toggle it off every single time. Conversely, a chunk that consistently produces great answers gets no advantage over one that never helps.

The toggle system (`isIncluded`) is ephemeral — it resets on every new query. Users are doing the work of teaching the system what's useful, but that signal is discarded immediately.

### Inspiration

- **Spotify's like/dislike** — simple binary signals that shape future recommendations
- **Google Search feedback** — "Not helpful" signals that suppress results
- **Retrieval-Augmented Generation research** — relevance feedback loops for improving retrieval quality

### User Stories

1. As a user, I want to mark a chunk as irrelevant so it stops appearing in future searches (or appears with much lower priority).
2. As a user, I want to boost a chunk so it ranks higher in future searches, since I know it's consistently useful.
3. As a user, I want to see which chunks I've boosted or hidden so I can manage my feedback decisions.
4. As a user, I want the system to learn from my toggle behavior over time — chunks I frequently exclude should naturally rank lower.
5. As a user, I want to undo a hide or boost decision if my needs change.

### Design Decisions

- **Explicit feedback** via hide/boost icons on `ChunkPreview` cards. This extends the existing toggle (include/exclude per query) with persistent signals.
- **Feedback is stored per-chunk, not per-query**. A hidden chunk is hidden across all future queries; a boosted chunk is boosted everywhere. This is simpler than per-query or per-collection feedback (which can come in v2).
- **Score multiplier model**: feedback applies as a multiplier to the hybrid search score. Boosted chunks get a `1.5×` multiplier; hidden chunks get `0.5×` (heavily dampened but still retrievable if highly relevant). Neutral chunks remain at `1.0×`. These multipliers are applied after the hybrid score is computed but before the `minScore` filter and top-k selection. A hidden chunk with a strong match (e.g. `0.9 × 0.5 = 0.45`) can still surface — it just needs to earn its place.
- **Implicit learning (v2, deferred)**: tracking which chunks users toggle off frequently and auto-dampening them. The explicit hide/boost is the MVP; implicit signals can layer on top later.
- **No re-embedding needed**: feedback modifies the scoring formula, not the embeddings themselves. The vector space stays unchanged.
- **Feedback survives re-indexing**: feedback is stored by a content-based key (source path + chunk title hash), not by chunk UUID. When a document is re-processed, feedback for matching chunks is preserved.

### Tasks

#### 16.1 Feedback data model and storage [P0]
- Create `chunk_feedback` table in the main database:
  - `id TEXT PRIMARY KEY`
  - `chunk_id TEXT NOT NULL` (FK to chunks.id, ON DELETE CASCADE)
  - `source_path TEXT NOT NULL` (for surviving re-indexing)
  - `title_hash TEXT NOT NULL` (SHA-256 of chunk title, for re-matching after re-index)
  - `feedback_type TEXT NOT NULL` (`boost`, `hide`, `neutral`)
  - `multiplier REAL NOT NULL DEFAULT 1.0` (1.5 for boost, 0.5 for hide, 1.0 for neutral)
  - `created_at TEXT NOT NULL`
  - `updated_at TEXT NOT NULL`
- Schema migration (bump version)
- Index on `chunk_id` and on `(source_path, title_hash)` for re-matching
- DatabaseService methods: `setChunkFeedback(chunkId:, type:)`, `getChunkFeedback(chunkIds:) → [String: Double]`, `clearChunkFeedback(chunkId:)`

#### 16.2 Feedback-aware hybrid search [P0]
- Load feedback multipliers for candidate chunks after hybrid scoring
- Apply multipliers: `finalScore = hybridScore × feedbackMultiplier`
- Hidden chunks (`multiplier = 0.5`) are dampened but still retrievable when highly relevant to the query
- Boosted chunks (`multiplier = 1.5`) get capped at `1.0` after multiplication to avoid artificial inflation beyond maximum
- Add `feedbackType` property to `ScoredChunk` (optional, for UI display)
- Preserve backward compatibility: chunks with no feedback record default to `1.0×`

#### 16.3 Hide and boost icons on ChunkPreview [P0]
- Add two new icon buttons to the `ChunkPreview` header, alongside the existing toggle:
  - **Hide** (eye.slash icon): marks chunk as irrelevant. Tapping sets `feedback_type = 'hide'`, chunk gets a dampened visual treatment and will rank significantly lower in future searches (0.5× multiplier)
  - **Boost** (hand.thumbsup icon): marks chunk as valuable. Tapping sets `feedback_type = 'boost'`, chunk gets a subtle upward-arrow badge or green highlight
- Icons show current state: filled when active (boosted/hidden), outlined when neutral
- Tapping an active icon reverts to neutral (undo)
- Visual feedback: brief animation on state change (scale pulse or color flash)

#### 16.4 Feedback indicators in chunk display [P1]
- Boosted chunks: green upward-arrow pill or "Boosted" label next to relevance score
- Hidden chunks: should not normally appear (filtered in search), but if shown in management UI, display with strikethrough and "Hidden" label
- Chunks with feedback show a subtle indicator so users know their signal is being applied
- In the regenerate bar summary: "N boosted · M hidden" count if any feedback exists

#### 16.5 Feedback management view [P1]
- New section in Settings or Documents view: "Chunk Feedback"
- List of all chunks with active feedback (boosted or hidden), grouped by document
- Each row shows: chunk title, source document, feedback type, date set
- Actions: change feedback type, clear feedback (revert to neutral)
- Bulk actions: "Clear All Feedback", "Clear Hidden", "Clear Boosts"
- Search/filter within the feedback list

#### 16.6 Feedback preservation across re-indexing [P2]
- When a document is re-processed (re-embedded), match old feedback to new chunks by `(source_path, title_hash)`
- `title_hash` uses SHA-256 of the chunk title string for stable matching
- If a chunk's content changes but title stays the same, feedback carries over
- If both title and content change (different chunk), feedback is orphaned (left in table but no longer matched)
- Periodic cleanup: remove orphaned feedback records where `chunk_id` no longer exists in `chunks` table

#### 16.7 Implicit feedback signals (deferred — v2) [P3]
- Track toggle-off frequency per chunk across queries (how often users exclude it)
- Track which chunks were included in responses the user continued the conversation after (positive signal)
- Compute an implicit multiplier: `1.0 - (excludeRate × 0.5)` — chunks excluded 80%+ of the time get dampened to 0.6×
- Blend implicit and explicit: explicit always wins (hide/boost override implicit)
- Show implicit feedback strength in the management view: "Excluded 4/5 times"

#### 16.8 Feedback analytics [P3]
- Dashboard or summary in Settings showing feedback impact:
  - Total boosted chunks, total hidden chunks
  - "Feedback improved relevance by ~X%" (compare average included-chunk scores before/after feedback)
  - Most-boosted documents, most-hidden documents
- Exportable as part of Epic 15 (Turn Chat Into Asset) — feedback data included in knowledge base metadata

---

*Add new epics below as they are identified.*
