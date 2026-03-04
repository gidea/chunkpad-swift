# Chunkpad — Product Backlog

> **Rules:**
> - When planning a sprint: copy epic tasks from here into `SPRINTS.md`, expand with subtasks there.
> - When a sprint completes: move it from `SPRINTS.md` to `DONE.md`.
> - Never add implementation details or `[x]` marks here — this file stays forward-looking.

---

## Product Vision

Chunkpad transforms local documents into a searchable knowledge base that powers retrieval-augmented generation. The next four epics close the loop:

1. **Organize** — Named collections scope retrieval to relevant documents, not the entire knowledge base (Epic 13).
2. **Curate** — Preview and select chunks *before* sending to the LLM. Persistently hide noisy chunks or boost valuable ones so every future query delivers better context (Epics 14 & 16).
3. **Generate with confidence** — See exactly what the model will receive, with token budget visibility and per-chunk control (Epic 14).
4. **Capture outputs** — Save LLM responses as new documents, re-index them, and close the flywheel: documents → chunks → answers → new documents → richer future answers (Epic 15).

These epics are sequenced to avoid modifying the same components repeatedly. See **Implementation Phases** below.

---

## Priority Legend

Priorities encode cross-epic implementation order, not standalone importance.

| Label | Meaning | Phases |
|---|---|---|
| P0 | Data foundations — must land first | Phase 1 (Data Layer) + Phase 2 (Search Pipeline) |
| P1 | Core UI — builds on P0 data layer | Phase 3 (Chunk Display) + Phase 4 (Collection UI) |
| P2 | Major workflows — depends on P1 components | Phase 5 (Context Preview) + Phase 6 (Chat Export) |
| P3 | Polish & advanced — cherry-pick into any sprint | Phase 7 |

---

## Implementation Phases

Tasks are grouped by the source files they modify, not by epic. This prevents reopening the same file in multiple sprints. Each phase builds on the prior one.

### Phase 1: Data Layer Foundation — 1 sprint

Schema v10 → v11 (single migration for both collections and feedback tables), model structs, CRUD methods.

| Task | Epic | What |
|---|---|---|
| 13.1 | 13 | `collections` table + `collection_id` FK on documents, vec_chunks, chunks_fts |
| 16.1 | 16 | `chunk_feedback` table + indexes + CRUD methods |
| 13.3 | 13 | `Collection` model + extend `ScoredChunk` with `collectionName` and `feedbackType` |
| 13.2 | 13 | Collection CRUD methods in DatabaseService |

**Files:** `DatabaseService.swift`, `ScoredChunk.swift`, new `Collection.swift`, new `ChunkFeedback.swift`

### Phase 2: Search Pipeline — ½ sprint

Modify `hybridSearch` once with both collection filter AND feedback multiplier.

| Task | Epic | What |
|---|---|---|
| 13.4 | 13 | Optional `collectionId` parameter; WHERE clause on vec_chunks KNN + FTS5 |
| 16.2 | 16 | Load feedback multipliers after scoring; apply `finalScore = hybridScore × multiplier` |

**Files:** `DatabaseService.swift` (hybridSearch, vectorSearch, fullTextSearch)

### Phase 3: Chunk Display — 1 sprint

Enhance `ChunkPreview` once with all new UI (feedback icons, collection badge, indicators). Then Phase 5 reuses it unchanged.

| Task | Epic | What |
|---|---|---|
| 16.3 | 16 | Hide (eye.slash) and boost (hand.thumbsup) icon buttons on ChunkPreview |
| 16.4 | 16 | Feedback indicators: "Boosted" pill, "Hidden" label, regenerate bar counts |
| 13.8 | 13 | Collection name pill/badge on ChunkPreview |

**Files:** `ChunkPreview.swift`, `ChatViewModel.swift` (feedback methods), `ChatView.swift` (pass callbacks)

### Phase 4: Collection Management UI — 1 sprint

DocumentsView gets collection CRUD; ChatView toolbar gets scope picker.

| Task | Epic | What |
|---|---|---|
| 13.6 | 13 | Collection list/sidebar in DocumentsView with New/Rename/Delete |
| 13.5 | 13 | Collection scope picker in ChatView toolbar |
| 13.7 | 13 | Collection assignment during/after indexing |

**Files:** `DocumentsView.swift`, `ChatView.swift`, `ChatViewModel.swift`, `AppState.swift`, `IndexingViewModel.swift`

### Phase 5: Context Preview — 1–2 sprints

Biggest UI addition. ChunkPreview is reused unchanged from Phase 3.

| Task | Epic | What |
|---|---|---|
| 14.1 | 14 | Search-before-send flow: magnifying glass button, `previewChunks`, "Send with N chunks" |
| 14.2 | 14 | Collapsible search panel UI above input bar |
| 14.3 | 14 | Document-level grouping and per-document removal |
| 14.4 | 14 | Inline retrieval controls: relevance slider, re-search button |
| 14.8 | 14 | Search panel state lifecycle |

**Files:** `ChatView.swift` (search panel, input bar), `ChatViewModel.swift` (previewChunks, searchWithoutSend)

### Phase 6: Chat Export — 1 sprint

Additive — context menus and toolbar buttons, no shared component rework.

| Task | Epic | What |
|---|---|---|
| 15.1 | 15 | Copy single message (context menu on MessageBubble) |
| 15.3 | 15 | Export conversation as markdown file (NSSavePanel, YAML frontmatter) |
| 15.5 | 15 | Save response to knowledge base (re-index through existing pipeline) |
| 15.2 | 15 | Copy full conversation to clipboard |
| 15.4 | 15 | Export conversation as .docx (textutil pipeline) |
| 15.6 | 15 | Save full conversation to knowledge base |

**Files:** `MessageBubble.swift`, `ChatView.swift`, `ChatViewModel.swift`, `IndexingViewModel.swift`

### Phase 7: Polish — ongoing

Cherry-pick into any sprint with capacity.

| Task | Epic | What |
|---|---|---|
| 13.9 | 13 | Persist conversation-collection scope |
| 14.5 | 14 | Collection switcher in search panel |
| 14.6 | 14 | Context budget visualization |
| 14.7 | 14 | Keyboard shortcuts |
| 15.7 | 15 | Export indicators in conversation sidebar |
| 16.5 | 16 | Feedback management view |
| 16.6 | 16 | Feedback preservation across re-indexing |
| 16.7 | 16 | Implicit feedback signals (v2) |
| 16.8 | 16 | Feedback analytics |

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

#### 13.1 Database schema for collections [P0] — Phase 1
Add collections infrastructure to the main database. Combined with 16.1 in a single schema migration (v10 → v11).

- Add `collections` table: `id TEXT PK, name TEXT UNIQUE NOT NULL, created_at TEXT, color TEXT`
- Add `collection_id TEXT` nullable FK to `documents` table (null = uncategorized)
- Add `collection_id TEXT` auxiliary column to `vec_chunks` (for filtered KNN via `WHERE collection_id = ?`)
- Rebuild `chunks_fts` to include `collection_id` column (FTS5 cannot ALTER — drop and recreate with triggers)
- Add index: `CREATE INDEX idx_documents_collection_id ON documents(collection_id)`
- Existing documents get `collection_id = NULL` (backward-compatible)

Files: `Chunkpad/Services/DatabaseService.swift`
Depends on: None (first task in Phase 1)

#### 13.2 Collection CRUD in DatabaseService [P0] — Phase 1
Data access methods for collection management.

- `createCollection(name: String, color: String?) throws -> Collection` — INSERT with UUID
- `fetchCollections() throws -> [Collection]` — SELECT with document count via LEFT JOIN
- `renameCollection(id: String, name: String) throws` — UPDATE with UNIQUE constraint handling
- `deleteCollection(id: String) throws` — SET `documents.collection_id = NULL` for that collection, then DELETE collection row
- `assignDocumentToCollection(documentId: String, collectionId: String?) throws` — UPDATE documents SET collection_id; also UPDATE `collection_id` on that document's `vec_chunks` rows and rebuild its `chunks_fts` entries
- `removeDocumentFromCollection(documentId: String) throws` — alias for `assignDocumentToCollection(documentId:, collectionId: nil)`

Files: `Chunkpad/Services/DatabaseService.swift`
Depends on: 13.1

#### 13.3 Collection model [P0] — Phase 1
Create the Collection struct and extend ScoredChunk with both collection and feedback fields (done once to avoid reopening the model).

- New file `Collection.swift`: `struct Collection: Identifiable, Codable, Sendable { id: String, name: String, createdAt: Date, color: String?, documentCount: Int }`
- Add `collectionName: String? = nil` to `ScoredChunk` — populated during hybridSearch chunk fetch (LEFT JOIN through documents → collections)
- Add `feedbackType: FeedbackType? = nil` to `ScoredChunk` — populated during feedback-aware scoring (see 16.2)
- Both new fields are optional with nil defaults so all existing callers remain unchanged

Files: new `Chunkpad/Models/Collection.swift`, `Chunkpad/Models/ScoredChunk.swift`
Depends on: 13.1, 16.1 (model references both schemas)

#### 13.4 Filtered hybrid search [P0] — Phase 2
Extend hybridSearch to support collection-scoped queries. Combined with 16.2 in a single modification pass.

- Add parameter: `collectionId: String? = nil` to `hybridSearch` signature
- When non-nil: vector search adds `WHERE collection_id = ?` (vec0 supports WHERE on auxiliary columns); FTS5 search adds subquery: `AND rowid IN (SELECT rowid FROM chunks WHERE document_id IN (SELECT id FROM documents WHERE collection_id = ?))`
- When nil: no filter (current behavior preserved exactly)
- In chunk fetch step, populate `collectionName` via JOIN: `LEFT JOIN documents d ON c.document_id = d.id LEFT JOIN collections col ON d.collection_id = col.id`

Files: `Chunkpad/Services/DatabaseService.swift`
Depends on: 13.1, 13.3

#### 13.5 Collection picker in Chat toolbar [P1] — Phase 4
Add UI control to scope chat searches to a collection.

- Add `Picker` in ChatView toolbar alongside generation mode picker: "All Documents" + each collection
- New `ChatViewModel.selectedCollectionId: String? = nil` bound to picker
- New `ChatViewModel.collections: [Collection]` loaded via `database.fetchCollections()` on init
- `sendMessage` passes `selectedCollectionId` to `hybridSearch(... collectionId: selectedCollectionId)`
- Persist `selectedCollectionId` in `AppState` (UserDefaults) so it survives restarts

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`, `Chunkpad/App/AppState.swift`
Depends on: 13.4 (filtered search), 13.2 (fetchCollections)

#### 13.6 Collection management UI in Documents view [P1] — Phase 4
Collection CRUD surface in DocumentsView.

- New section at top of DocumentsView (above chunk tree): "Collections" header with list of collection rows
- Each row: colored circle, collection name, document count badge
- "New Collection" button opens inline form or sheet (name TextField + optional color picker)
- Context menu on each row: Rename, Delete (with confirmation "Documents will be moved to Uncategorized")
- Drag-and-drop or context menu on document rows: "Move to Collection →" submenu

Files: `Chunkpad/Views/Documents/DocumentsView.swift`, `Chunkpad/ViewModels/IndexingViewModel.swift`
Depends on: 13.2 (CRUD methods)

#### 13.7 Collection assignment during indexing [P1] — Phase 4
Assign newly processed documents to a collection after indexing.

- After `selectAndProcessFolder()` completes, show sheet: "Assign these N documents to a collection?"
- Picker: existing collections + "None (Uncategorized)" + "New Collection..."
- Bulk assignment: call `assignDocumentToCollection` for each document in the folder
- Optional: if `AppState.defaultCollectionId` is set, auto-assign without prompting

Files: `Chunkpad/Views/Documents/DocumentsView.swift`, `Chunkpad/ViewModels/IndexingViewModel.swift`
Depends on: 13.6 (collection UI context)

#### 13.8 Collection metadata in chunk display [P1] — Phase 3
Show collection information on ChunkPreview cards. Done alongside 16.3 and 16.4 to modify ChunkPreview once.

- Add `GlassPill` to ChunkPreview header showing `scoredChunk.collectionName` when non-nil
- Use collection's `color` for pill background tint (fallback to `.secondary`)
- Position: after title, before relevance score pill
- In regenerate bar summary: show collection name if all visible chunks belong to the same collection

Files: `Chunkpad/Views/Chat/ChunkPreview.swift`
Depends on: 13.3 (collectionName on ScoredChunk)

#### 13.9 Persist conversation-collection scope [P3] — Phase 7
Store collection scope on conversations for recall.

- Add `collection_id TEXT` column to `conversations` table in `chunkpad_chat.db` (ConversationDatabaseService migration)
- On `createConversation`, store `selectedCollectionId` if set
- On `loadConversation(id:)`, restore `selectedCollectionId` from record
- Show scoped collection name pill in conversation sidebar row (MainView)

Files: `Chunkpad/Services/ConversationDatabaseService.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`, `Chunkpad/Views/MainView.swift`
Depends on: 13.5

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

#### 14.1 Search-before-send flow [P2] — Phase 5
Add a search trigger that runs hybridSearch without sending to the LLM.

- Add "Search" button (`magnifyingglass` icon) to the left of the send button in `inputBar`
- On tap: run the same embed → hybridSearch pipeline as `sendMessage` steps 1–5, but stop before context building / LLM call
- Store results in new `ChatViewModel.previewChunks: [ScoredChunk]` (separate from `retrievedChunks` which holds post-response chunks)
- New `ChatViewModel.searchWithoutSend(query:)` method — reuses `embedQuery` + `hybridSearch` + `addPinnedChunks`
- When `previewChunks` is non-empty, send button label changes to "Send with N chunks" (N = `previewChunks.filter(\.isIncluded).count`)
- Pressing Enter with no active preview runs the old atomic flow (backward-compatible)
- Pressing Enter with an active preview calls `sendWithPreview()` which uses `previewChunks` directly (skips re-search, goes straight to `buildContext` → LLM)
- Add `ChatViewModel.isPreviewActive: Bool` computed from `!previewChunks.isEmpty`

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: Phase 3 (ChunkPreview enhancements), Phase 2 (search pipeline with collection+feedback)

#### 14.2 Search panel UI [P2] — Phase 5
Build the collapsible preview panel above the input bar.

- New `searchPanel` view in ChatView, inserted into `bottomBar` between `chunksBar` and `inputBar`
- `@State isSearchPanelExpanded = false`, toggled by chevron button
- When expanded, shows:
  - Summary header: "N documents · M chunks · ~X tokens" (computed from `previewChunks`)
  - Horizontal ScrollView of `ChunkPreview` cards (reuses the Phase 3–enhanced component with feedback icons + collection badge — no ChunkPreview changes needed)
  - Each card has include/exclude toggle plus hide/boost icons (all from Phase 3)
  - Token budget indicator bar (green/orange/red)
- Max height: 200pt (taller than chunksBar's 120pt since this is pre-send curation)
- Auto-expands when search results arrive; auto-collapses on send

Files: `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 14.1 (previewChunks data source)

#### 14.3 Document-level grouping and removal [P2] — Phase 5
Group chunks by source document in the search panel for faster curation.

- Compute groups: `Dictionary(grouping: previewChunks, by: \.chunk.sourcePath)`
- Document header row: file name (last path component), chunk count, total token estimate, "Remove" button
- "Remove document" sets `isIncluded = false` on all that document's chunks
- Collapsed view: just document names + chunk counts; tap to expand to individual ChunkPreview cards
- Toggle between flat and grouped view with segmented control in panel header

Files: `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 14.2

#### 14.4 Inline retrieval controls [P2] — Phase 5
Adjust search parameters without navigating to Settings.

- Mini `Slider` for minimum relevance score (range 0.0–1.0, step 0.05) in search panel header
- Changes apply immediately as client-side filter: `previewChunks.filter { $0.relevanceScore >= threshold }` — does NOT re-run hybridSearch
- Show current value label: "Min relevance: 0.40"
- "Re-search" button: re-runs `searchWithoutSend(query:)` with current inputText for fresh results
- Default value sourced from `appState.searchMinScore`

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 14.2

#### 14.5 Collection switcher in search panel [P3] — Phase 7
Inline collection picker when Epic 13 collections exist.

- Compact collection picker (dropdown) in search panel header
- Switching collection triggers `searchWithoutSend()` with new `collectionId`
- Visual indicator: colored dot matching collection color

Files: `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 14.2, 13.5

#### 14.6 Context budget visualization [P3] — Phase 7
Token usage indicator with clear visual feedback.

- Progress bar or ring in search panel header: `estimatedTokens / (contextSize × 0.8)`
- Color coding: green (<50%), orange (50–80%), red (>80%)
- Exact numbers: "~3,200 / 3,277 tokens (80% of 4,096 budget)"
- Warning text when over budget: "N chunks will be auto-trimmed on send"

Files: `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 14.2

#### 14.7 Keyboard shortcuts [P3] — Phase 7
Accelerators for the search-then-send workflow.

- `Cmd+K` to focus search panel and trigger search (if inputText non-empty)
- `Cmd+Enter` to send with current preview
- `Escape` to dismiss/collapse search panel and clear previewChunks
- Tab navigation through chunk toggles

Files: `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 14.1, 14.2

#### 14.8 Search panel state management [P2] — Phase 5
Lifecycle rules for search panel state.

- `previewChunks` cleared on send (search panel collapses; post-response chunksBar takes over)
- Switching conversations clears `previewChunks` and collapses panel
- Adjusting relevance slider or toggling chunks preserves `previewChunks` (no re-search)
- Re-search replaces `previewChunks` with fresh results
- `isSearchPanelExpanded` auto-set to true on populate, false on send/clear
- All in-memory state — no persistence needed

Files: `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 14.1

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

#### 15.1 Copy single message to clipboard [P2] — Phase 6
Context menu export on assistant message bubbles.

- Add `.contextMenu` to assistant message content in `MessageBubble`
- "Copy as Markdown": copy `message.content` to `NSPasteboard.general` as both `public.utf8-plain-text` and `public.html`
- "Copy as Plain Text": strip markdown formatting (remove `#`, `*`, `` ` ``, `[]()`), copy plain text
- Visual confirmation: briefly show "Copied" overlay or checkmark animation on the bubble
- Create a static `MessageExporter` helper with `copyMarkdown(_:)` and `copyPlainText(_:)` methods (reused by 15.2–15.6)

Files: `Chunkpad/Views/Chat/MessageBubble.swift`
Depends on: None

#### 15.2 Copy full conversation to clipboard [P2] — Phase 6
Export all messages as formatted text to clipboard.

- Add "Copy Conversation" to ChatView toolbar (or "Export" dropdown menu)
- Format: conversation title + date header, then sequential messages with `## You` / `## Assistant` headings and timestamps
- Exclude system messages (internal RAG context not user-visible)
- Reuse `MessageExporter` helper from 15.1

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 15.1 (MessageExporter helper)

#### 15.3 Export conversation as markdown file [P2] — Phase 6
Save conversation to disk as `.md` with metadata.

- Add "Export as Markdown..." to ChatView toolbar or Export dropdown
- `NSSavePanel` with default filename `{conversation-title}.md` (sanitize title for filesystem)
- Format: YAML frontmatter (`title`, `date`, `model`, `chunk_count`, `collection`) followed by messages with `## You` / `## Assistant` headings
- Include `## Sources` section at end listing `referencedChunkIDs` and source document paths from all assistant messages
- Handle no-title conversations: date-based fallback `Chat-YYYY-MM-DD.md`
- `ChatViewModel.exportAsMarkdown() -> String` formats content; view handles NSSavePanel

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: None

#### 15.4 Export conversation as .docx [P2] — Phase 6
Word format conversion using macOS textutil.

- Add "Export as Word Document..." to Export dropdown
- Pipeline: `exportAsMarkdown()` → write to temp file → `textutil -convert html` → `textutil -convert docx` (two-step, same approach `DocumentProcessor` uses in reverse)
- `NSSavePanel` with `.docx` default extension
- Basic formatting: headings for role labels, monospace for code blocks

Files: `Chunkpad/Views/Chat/ChatView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 15.3 (reuses markdown export as intermediate)

#### 15.5 Save response to knowledge base [P2] — Phase 6
Re-index a single assistant response into the knowledge base — closes the knowledge flywheel.

- Add "Save to Knowledge Base" to assistant message context menu in `MessageBubble`
- Create designated exports directory: `~/Library/Application Support/Chunkpad/exports/`
- Write response as `{conversation-title}-{timestamp}.md` with YAML frontmatter:
  ```yaml
  source: chat-export
  conversation: {title}
  date: {ISO8601}
  query: {user message that prompted this response}
  referenced_chunks: [{chunk IDs}]
  ```
  followed by `message.content`
- Run through existing pipeline: `DocumentProcessor.processFile()` → `DatabaseService.insertDocumentWithChunks()` → embed via `EmbeddingService`
- Coordinate with `IndexingViewModel`'s embedding infrastructure: `ChatViewModel.saveToKnowledgeBase(message:, query:)` creates the file and triggers embedding
- Show progress indicator during embedding (reuse existing embedding progress UI)
- On success: confirmation toast with "View in Documents" link

Files: `Chunkpad/Views/Chat/MessageBubble.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`, `Chunkpad/ViewModels/IndexingViewModel.swift`
Depends on: 15.1 (context menu pattern)

#### 15.6 Save full conversation to knowledge base [P2] — Phase 6
Export all messages as a single document and re-index.

- Same infrastructure as 15.5 but exports all Q&A pairs as one markdown document
- Format: each Q&A pair as `## Question: {first line of user message}` section
- Section-aware chunking in `DocumentProcessor` will naturally split by `##` headings
- User can review chunks before embedding via existing two-step pipeline (process → review → embed)

Files: `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 15.5 (save-to-KB infrastructure)

#### 15.7 Export indicators and management [P3] — Phase 7
Track which conversations have been exported or saved to KB.

- Add `exported_at TEXT` column to `conversations` table in `chunkpad_chat.db` (ConversationDatabaseService migration)
- Set `exported_at` when conversation saved to KB via 15.5 or 15.6
- Show small document icon or "Indexed" badge on conversation sidebar rows where `exported_at` is non-nil
- Prevent duplicate re-indexing: check `exported_at` before saving, warn if already exported
- "View in Documents" link navigates to Documents tab filtered to the exported document

Files: `Chunkpad/Services/ConversationDatabaseService.swift`, `Chunkpad/Views/MainView.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 15.5

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

#### 16.1 Feedback data model and storage [P0] — Phase 1
Create feedback table and CRUD methods. Combined with 13.1 in a single schema migration (v10 → v11).

- Create `chunk_feedback` table in `chunkpad.db`:
  - `id TEXT PRIMARY KEY` (UUID)
  - `chunk_id TEXT NOT NULL` (FK to chunks.id, ON DELETE CASCADE)
  - `source_path TEXT NOT NULL` (for surviving re-indexing; matches `chunks.source_path`)
  - `title_hash TEXT NOT NULL` (SHA-256 of chunk title, for re-matching after re-index)
  - `feedback_type TEXT NOT NULL` CHECK (`boost`, `hide`, `neutral`)
  - `multiplier REAL NOT NULL DEFAULT 1.0` (1.5 for boost, 0.5 for hide, 1.0 for neutral)
  - `created_at TEXT NOT NULL`
  - `updated_at TEXT NOT NULL`
- Indexes: `idx_chunk_feedback_chunk_id ON chunk_feedback(chunk_id)`, `idx_chunk_feedback_source_title ON chunk_feedback(source_path, title_hash)`
- New enum `FeedbackType: String, Codable { case boost, hide, neutral }` in new `ChunkFeedback.swift` model
- New struct `ChunkFeedback: Identifiable { id, chunkId, sourcePath, titleHash, feedbackType, multiplier, createdAt, updatedAt }`
- DatabaseService methods:
  - `setChunkFeedback(chunkId: String, type: FeedbackType) throws` — UPSERT with computed multiplier
  - `getChunkFeedback(chunkIds: [String]) throws -> [String: (type: FeedbackType, multiplier: Double)]` — batch fetch
  - `clearChunkFeedback(chunkId: String) throws` — DELETE
  - `allFeedback() throws -> [ChunkFeedback]` — for management view (16.5)

Files: `Chunkpad/Services/DatabaseService.swift`, new `Chunkpad/Models/ChunkFeedback.swift`
Depends on: None (Phase 1, combined with 13.1 migration)

#### 16.2 Feedback-aware hybrid search [P0] — Phase 2
Apply feedback multipliers to the hybrid scoring pipeline. Combined with 13.4 in a single modification pass.

- After computing `scores` dict in `hybridSearch` (after normalization, before filtering):
  1. Collect all candidate chunk IDs from `scores.keys`
  2. Call `getChunkFeedback(chunkIds:)` to batch-load multipliers
  3. Apply: `scores[id] = scores[id]! * (feedback?.multiplier ?? 1.0)`
  4. Cap at 1.0: `scores[id] = min(1.0, scores[id]!)`
- In chunk fetch step, populate `ScoredChunk.feedbackType` from the feedback lookup
- Hidden chunks (0.5×) are dampened but NOT filtered — they can still pass `minScore` if raw score is high enough (e.g. `0.9 × 0.5 = 0.45`)
- Boosted chunks (1.5×) capped at 1.0 to avoid artificial inflation
- Chunks with no feedback record default to 1.0× (no change — backward-compatible)

Files: `Chunkpad/Services/DatabaseService.swift`
Depends on: 16.1, 13.4 (combined modification)

#### 16.3 Hide and boost icons on ChunkPreview [P1] — Phase 3
Add persistent feedback controls to chunk cards. Done alongside 13.8 and 16.4 to modify ChunkPreview once.

- Add two `GlassIconButton` to ChunkPreview header, between include/exclude toggle and title:
  - **Hide** (`eye.slash`): tap sets `feedback_type = 'hide'`. Dampened visual: 60% opacity + muted title color
  - **Boost** (`hand.thumbsup`): tap sets `feedback_type = 'boost'`. Enhanced visual: green tint on icon
- Icons show current state: SF Symbol filled variant when active (e.g. `hand.thumbsup.fill`), outline when neutral
- Tapping an active icon reverts to neutral (undo) via `clearChunkFeedback`
- New callbacks on ChunkPreview: `onHide: () -> Void`, `onBoost: () -> Void`
- New `ChatViewModel.setChunkFeedback(chunkId: String, type: FeedbackType)` method that calls DatabaseService and updates local `retrievedChunks`/`previewChunks` state
- Brief scale pulse animation via `withAnimation(.spring)` on state change

Files: `Chunkpad/Views/Chat/ChunkPreview.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`, `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 16.1 (feedback storage)

#### 16.4 Feedback indicators in chunk display [P1] — Phase 3
Visual indicators showing feedback state on chunks.

- Boosted chunks: green `GlassPill { Label("Boosted", systemImage: "arrow.up") }` next to relevance score pill
- Hidden chunks: gray "Hidden" label with muted styling. Hidden chunks rarely appear in search (dampened score) but show in management view (16.5)
- In regenerate bar summary (ChatView): append "N boosted · M hidden" count when any chunks have feedback
- Subtle indicator so users know their signal is being applied

Files: `Chunkpad/Views/Chat/ChunkPreview.swift`, `Chunkpad/Views/Chat/ChatView.swift`
Depends on: 16.3 (feedback icons must exist)

#### 16.5 Feedback management view [P3] — Phase 7
Dedicated view for reviewing and managing all feedback decisions.

- New section in DocumentsView (or standalone sheet from Documents toolbar): "Chunk Feedback"
- List of all chunks with active feedback (boosted or hidden), grouped by source document
- Each row: chunk title, source document name, feedback type pill, date set
- Actions: change feedback type (dropdown/toggle), clear feedback (revert to neutral)
- Bulk actions: "Clear All Feedback", "Clear Hidden", "Clear Boosts"
- Search/filter within feedback list by title or document name
- Data source: `DatabaseService.allFeedback()` joined with chunk titles

Files: `Chunkpad/Views/Documents/DocumentsView.swift` (or new `FeedbackManagementView.swift`)
Depends on: 16.1, 16.3

#### 16.6 Feedback preservation across re-indexing [P3] — Phase 7
Ensure feedback survives when documents are re-processed.

- When `DocumentProcessor.processFile()` runs on a previously-indexed document, chunks get new UUIDs
- After inserting new chunks, run re-matching pass: for each new chunk, compute `SHA256(chunk.title)` and look up `chunk_feedback` by `(source_path, title_hash)`
- If match found: update feedback record's `chunk_id` to the new chunk's ID
- If no match (title changed): feedback record becomes orphaned
- Periodic cleanup: `DatabaseService.cleanOrphanedFeedback() throws` — DELETE where `chunk_id NOT IN (SELECT id FROM chunks)`
- Call cleanup after re-indexing completes

Files: `Chunkpad/Services/DatabaseService.swift`, `Chunkpad/ViewModels/IndexingViewModel.swift`
Depends on: 16.1

#### 16.7 Implicit feedback signals (deferred — v2) [P3] — Phase 7
Track toggle behavior to auto-adjust chunk rankings.

- New `chunk_toggle_stats` table: `chunk_id, exclude_count, include_count`
- Increment on each toggle in `ChatViewModel.toggleChunk`
- Compute implicit multiplier: `1.0 - (excludeRate × 0.5)` — chunks excluded 80%+ get dampened to 0.6×
- Blend: explicit feedback always overrides implicit
- Show implicit signal in feedback management view: "Excluded 4/5 times"

Files: `Chunkpad/Services/DatabaseService.swift`, `Chunkpad/ViewModels/ChatViewModel.swift`
Depends on: 16.5

#### 16.8 Feedback analytics [P3] — Phase 7
Dashboard showing feedback impact on retrieval quality.

- Summary card in Settings or Documents: total boosted, total hidden, total neutral
- "Feedback improved relevance by ~X%" — compare average included-chunk scores before/after feedback
- Most-boosted and most-hidden documents (top 5 lists)
- Exportable as part of Epic 15 exports

Files: `Chunkpad/Views/Settings/SettingsView.swift` (or `Chunkpad/Views/Documents/DocumentsView.swift`)
Depends on: 16.5, 16.1

---

*Add new epics below as they are identified.*
