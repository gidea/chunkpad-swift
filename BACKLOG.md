# Chunkpad Development Backlog

**Date:** February 12, 2026
**Status:** Active development

This document tracks all planned work for Chunkpad, organized by epic. Each epic contains high-level goals, detailed tasks, subtasks, and known edge cases. Tasks are prioritized within each epic: **P0** (blocking/critical), **P1** (high), **P2** (medium), **P3** (nice-to-have).

---

## Table of Contents

1. [Epic 1: Persistence & Data Architecture](#epic-1-persistence--data-architecture)
2. [Epic 2: Documents Library](#epic-2-documents-library)
3. [Epic 3: Model Download Management](#epic-3-model-download-management)
4. [Epic 4: Chat & RAG Pipeline](#epic-4-chat--rag-pipeline)
5. [Epic 5: Settings & Configuration](#epic-5-settings--configuration)
6. [Epic 6: Error Handling & Resilience](#epic-6-error-handling--resilience)
7. [Epic 7: Polish & UX](#epic-7-polish--ux)

---

## Epic 1: Persistence & Data Architecture

**Goal:** Establish a clear, documented strategy for what data lives where, fix inconsistencies between storage layers, and ensure no data is silently lost between app sessions.

### Current state

The app uses four storage layers with overlapping and sometimes inconsistent responsibilities:

| Layer | What's stored | Location |
|---|---|---|
| **Main SQLite** (`DatabaseService`) | documents, chunks, vec_chunks (embeddings), chunks_fts, orphaned `messages` table | `~/Library/Application Support/Chunkpad/chunkpad.db` |
| **Chat SQLite** (`ConversationDatabaseService`) | conversations, messages | `~/Library/Application Support/Chunkpad/chunkpad_chat.db` |
| **UserDefaults** | settings, generation mode, chunk size/overlap, indexed folder paths, embedded chunk IDs | Standard defaults domain |
| **Filesystem** | chunk markdown files | `{userFolder}/_chunks/` |

### Tasks

#### 1.1 Remove orphaned `messages` table from main DB schema [P0]

The main `DatabaseService` creates a `messages` table (used for an earlier design) that is never read or written. Conversations are handled by `ConversationDatabaseService` in a separate DB. The orphaned table wastes schema space and confuses future developers.

- [ ] Remove `CREATE TABLE messages` from `DatabaseService.createTables()`
- [ ] Add a migration step: `DROP TABLE IF EXISTS messages` for existing databases
- [ ] Verify no code references `messages` in `DatabaseService`

#### 1.2 Add database migration system [P1]

There is no versioning or migration system. Schema changes require manual intervention or risk breaking existing databases.

- [ ] Add a `schema_version` pragma or `migrations` table to both databases
- [ ] Implement a `migrate()` method in `DatabaseService` that runs versioned migration blocks
- [ ] Implement the same for `ConversationDatabaseService`
- [ ] First migration: remove orphaned `messages` table (see 1.1)
- [ ] Document migration process in ARCHITECTURE.md for future contributors

**Edge cases:**
- App update with schema change on a machine with an existing database
- Migration fails mid-way (need transaction wrapping)
- User downgrades the app (forward-compatible schema)

#### 1.3 Wrap chunk insertion in a transaction [P0]

`DatabaseService.insertChunk()` writes to `chunks`, `vec_chunks`, and triggers FTS5 insertion -- three separate operations. If one fails, the others may succeed, leaving the database in an inconsistent state.

- [ ] Wrap `insertChunk()` in `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK`
- [ ] Wrap `insertDocument()` + all its chunk inserts in a single transaction
- [ ] Add the same for `deleteDocumentByFilePath()` (deletes from multiple tables)

**Edge cases:**
- App crash during embedding (partial chunks inserted)
- Disk full during write (SQLite should handle, but verify)
- Concurrent reads during transaction (WAL mode should handle)

#### 1.4 Add missing database indexes [P1]

Performance-critical queries lack indexes:

- [ ] Add index on `chunks.document_id` (used in joins, cascade deletes, `chunksForDocument`)
- [ ] Add index on `chunks.source_path` (used in `deleteDocumentByFilePath`)
- [ ] Add index on `messages.conversation_id` + `messages.timestamp` in conversation DB (used for ordering)
- [ ] Add these as migrations (see 1.2)

#### 1.5 Move IndexedFolder tracking from UserDefaults to main DB [P1]

Currently, `IndexedFolder` (rootURL + chunksRootURL) is persisted in UserDefaults, and only the most recent folder is remembered. This prevents multi-folder support and loses history.

- [ ] Create `indexed_folders` table in main DB: `id, root_path, chunks_root_path, created_at, last_processed_at, file_count, chunk_count`
- [ ] Migrate existing UserDefaults value to the new table on first run
- [ ] Update `IndexingViewModel` to read/write from the DB instead of UserDefaults
- [ ] Support multiple indexed folders (list of `IndexedFolder` instead of single optional)
- [ ] Remove `IndexingKeys.indexedFolderRoot` and `indexedFolderChunksRoot` from UserDefaults

**Edge cases:**
- Folder path no longer exists (external drive unplugged, folder deleted)
- Folder was moved/renamed since last index
- Two folders with the same name but different paths

#### 1.6 Move embedded chunk IDs from UserDefaults to main DB [P1]

`embeddedChunkIDs` is a `Set<String>` stored as a string array in UserDefaults. For large document sets this becomes unwieldy and is not queryable.

- [ ] Track embedded status in the `chunks` table or a new `embedded_chunks` table: `chunk_id, embedded_at, chunk_hash`
- [ ] Store a content hash alongside each embedded chunk so the app can detect when a chunk file was edited and the content actually changed (vs. just a timestamp change)
- [ ] Migrate existing UserDefaults IDs to the database on first run
- [ ] Remove `IndexingKeys.embeddedChunkIDs` from UserDefaults
- [ ] Update `IndexingViewModel.embeddedChunkIDs` to read from DB

#### 1.7 Fix hybridSearch normalization [P0]

`hybridSearch` divides FTS5 rank by `min(minRank, -0.001)` which can produce negative relevance scores when `minRank` is negative (which it always is for FTS5 rank values). This corrupts the 70/30 weighting.

- [ ] Fix normalization: use `abs(minRank)` or a correct normalization formula
- [ ] Add unit tests with known FTS5 rank values to verify score range is 0.0–1.0
- [ ] Verify that `minScore` threshold filtering works correctly after the fix

#### 1.8 Fix SQL injection risk in ConversationDatabaseService [P1]

`fetchConversations()` uses string interpolation for `LIMIT \(limit)` instead of a parameterized query.

- [ ] Change to parameterized query: `LIMIT ?` with bound parameter
- [ ] Audit all other SQL queries in both database services for string interpolation

#### 1.9 Document the persistence contract [P2]

Write a clear reference for what belongs where, so future contributors don't accidentally put DB data in UserDefaults or vice versa.

- [ ] Add a "Persistence Contract" section to ARCHITECTURE.md defining:
  - Main DB: document metadata, chunk text, embeddings, FTS index, indexed folder registry
  - Chat DB: conversations and messages only
  - UserDefaults: user preferences and settings only (generation mode, chunk size, API model selection)
  - Keychain: API keys only
  - Filesystem (`_chunks/`): editable chunk markdown files (source of truth for chunk content before embedding)
  - In-memory: view model state, UI toggles, model containers

---

## Epic 2: Documents Library

**Goal:** Build a robust document management experience where users can see all their indexed folders, browse chunk files in a grid/list, select chunks for embedding, track what's embedded vs. pending, and manage the full lifecycle of their document library.

### Current state

- Single folder tracked (most recent only)
- Chunk tree sidebar shows files but no visual distinction between embedded/pending chunks
- No way to delete indexed documents or folders
- No way to re-process a folder without the folder picker
- Modified file detection only on app activation
- Flat document list as fallback has no actions

### Tasks

#### 2.1 Multi-folder support [P1]

Users should be able to index multiple folders and see all of them in the Documents view.

- [ ] **2.1.1** Create an `indexed_folders` table (see 1.5) with full metadata
- [ ] **2.1.2** Replace the single `indexedFolder` in `IndexingViewModel` with `indexedFolders: [IndexedFolder]`
- [ ] **2.1.3** Add a folder list/grid above or alongside the chunk tree showing all indexed folders with:
  - Folder name and path
  - File count and chunk count
  - Last processed date
  - Embedded status (fully embedded, partially embedded, not embedded)
  - Status badge (ready, needs re-embed, folder missing)
- [ ] **2.1.4** Tapping a folder loads its chunk tree in the detail area
- [ ] **2.1.5** Persist security-scoped bookmarks for each folder so the app can re-access them across launches without re-prompting the user

**Edge cases:**
- Folder deleted externally → show "Folder not found" badge, disable re-process
- Folder on external drive that's disconnected → same handling
- User indexes the same folder twice → detect by path, ask to re-process or skip
- User indexes a subfolder of an already-indexed folder → warn about overlap
- Very large number of folders (>50) → consider pagination or lazy loading

#### 2.2 Folder lifecycle management [P1]

Users need the ability to remove folders from their library.

- [ ] **2.2.1** Add "Remove Folder" action (swipe-to-delete or context menu) on folder rows
- [ ] **2.2.2** Removing a folder should:
  - Delete all its documents, chunks, and embeddings from the main DB
  - Remove its entry from `indexed_folders`
  - Optionally delete the `_chunks/` directory on disk (ask the user)
  - Update `AppState.indexedDocumentCount`
- [ ] **2.2.3** Add "Re-process Folder" action that re-runs Step 1 (parse + chunk) using the stored path
- [ ] **2.2.4** Add "Re-embed All" action that re-runs Step 2 on all included chunks
- [ ] **2.2.5** Add "Clear All" option in toolbar to wipe the entire document library

**Edge cases:**
- Remove a folder while embedding is in progress → disable or warn
- Re-process a folder whose source files changed → overwrite `_chunks/`, mark embedded chunks as stale
- Re-process when chunk size settings changed → regenerate all chunk files with new settings

#### 2.3 Chunk grid/list view overhaul [P1]

Replace the current chunk-tree-with-detail layout with a more powerful browsing experience.

- [ ] **2.3.1** Add a view mode toggle: tree view (current) vs. flat grid view
- [ ] **2.3.2** In grid view, show chunk file cards in a `LazyVGrid`:
  - File name, source document type icon
  - Chunk count per file
  - Embedded status indicator (badge or icon: fully embedded, partially, none)
  - Last modified date
- [ ] **2.3.3** Tapping a card opens the chunk detail view (current behavior)
- [ ] **2.3.4** Add search/filter bar above the grid:
  - Filter by file name
  - Filter by embedded status (all, embedded, pending, modified)
  - Filter by document type (PDF, DOCX, TXT, etc.)
- [ ] **2.3.5** Add bulk actions toolbar:
  - "Select All" / "Deselect All" for chunk inclusion
  - "Include All in File" / "Exclude All in File"
  - Chunk count summary: "42 chunks selected / 67 total"

#### 2.4 Embedded vs. pending visual distinction [P0]

Users cannot tell which chunks have been embedded and which are pending. This is the most critical UX gap in the Documents view.

- [ ] **2.4.1** In the chunk detail view, show a status badge per chunk:
  - Green checkmark: embedded (in the vector DB)
  - Orange clock: pending (included but not yet embedded)
  - Gray circle: excluded (user toggled off)
  - Orange exclamation: stale (embedded but chunk file was modified since embedding)
- [ ] **2.4.2** In the tree sidebar, show aggregate status per file:
  - All embedded: green dot
  - Partially embedded: orange dot
  - None embedded: gray dot
  - Has stale chunks: orange dot with exclamation
- [ ] **2.4.3** In the folder list (2.1.3), show aggregate status per folder

#### 2.5 Stale chunk detection and re-embedding [P1]

When users edit chunk markdown files externally, the app must detect changes and guide them through re-embedding.

- [ ] **2.5.1** Persist `lastKnownModificationDates` to the database (currently in-memory only, lost on app restart)
- [ ] **2.5.2** On app activation and on Documents view appear, check for modified chunk files
- [ ] **2.5.3** Compare content hash (not just modification date) to detect actual content changes vs. spurious timestamp updates
- [ ] **2.5.4** Show stale chunks with a distinct visual treatment (see 2.4.1)
- [ ] **2.5.5** "Re-embed Modified" button should only re-embed chunks whose content actually changed
- [ ] **2.5.6** After re-embedding, update the stored hash and modification date

**Edge cases:**
- User edits a chunk file to add a new `## Chunk N` section → new chunk appears as pending
- User deletes a `## Chunk N` section → old embedding should be removed from the DB
- User renames a chunk file → treat as delete + create
- Chunk file is deleted entirely → mark all its chunks as orphaned, offer to clean up

#### 2.6 Delete individual documents and chunks [P2]

- [ ] **2.6.1** Add swipe-to-delete or context menu on file nodes in the chunk tree
- [ ] **2.6.2** Deleting a file should:
  - Remove its chunks and embeddings from the DB
  - Optionally delete the `.md` file from disk
  - Update the parent folder's counts
- [ ] **2.6.3** Add "Remove chunk from DB" option on individual chunks (keeps the chunk file, just removes the embedding)

#### 2.7 Security-scoped bookmark persistence [P1]

`NSOpenPanel` grants temporary security-scoped access. To re-access folders across app launches (for re-processing, change detection, etc.), the app must persist security-scoped bookmarks.

- [ ] **2.7.1** When user selects a folder, create a security-scoped bookmark and store it in UserDefaults or the database
- [ ] **2.7.2** On app launch, resolve stored bookmarks and call `startAccessingSecurityScopedResource()`
- [ ] **2.7.3** Call `stopAccessingSecurityScopedResource()` when the folder is removed from the library
- [ ] **2.7.4** Handle bookmark resolution failure (folder moved/deleted) → show "Folder not found" status

**Edge cases:**
- Bookmark becomes stale (folder moved) → prompt user to re-select
- App sandbox restricts bookmark creation → verify entitlement is sufficient
- Too many active bookmarks → macOS may limit; release unused ones

#### 2.8 Cancel processing and embedding [P2]

- [ ] **2.8.1** Add a "Cancel" button that appears during processing (Step 1) and embedding (Step 2)
- [ ] **2.8.2** Use Swift `Task` cancellation to abort the current operation
- [ ] **2.8.3** On cancel during processing: keep already-written chunk files, discard in-progress file
- [ ] **2.8.4** On cancel during embedding: keep already-embedded chunks, mark remaining as pending
- [ ] **2.8.5** Show "Cancelled — N/M files processed" status message

---

## Epic 3: Model Download Management

**Goal:** Make the download lifecycle for both the embedding model and Llama 3.2 transparent, predictable, and resilient. Users should always know what's being downloaded, why, how big it is, and be able to cancel, retry, or clear cached models.

### Current state

- Embedding model downloads on "Embed Selected" (correct) but there's no retry if download fails
- Llama 3.2 downloads on user acceptance of the chat dialog offer, or manually from Settings
- No way to clear model caches from the UI
- No way to see cache sizes
- No resilience for corrupted caches
- Download progress is shown but cannot be cancelled
- No disk space check before downloading

### Tasks

#### 3.1 Document and enforce download triggers [P0]

The rules for when each model downloads must be crystal clear and enforced in code.

**Embedding model (bge-base-en-v1.5, ~438 MB):**
- [ ] **3.1.1** Downloads ONLY when user clicks "Embed Selected" in Documents view (`IndexingViewModel.embedApprovedChunks`)
- [ ] **3.1.2** Add an assertion/guard: `EmbeddingService.ensureModelReady()` must NEVER be called from `ChatViewModel.sendMessage` — it should only call `ensureModelReady()` after checking `indexedDocumentCount > 0` (which guarantees a prior download)
- [ ] **3.1.3** Add code comments at every `ensureModelReady()` call site documenting which rule applies

**Llama 3.2 (~1.7 GB):**
- [ ] **3.1.4** Downloads ONLY when:
  - (a) User clicks "Download Llama" in the chat alert (after sending a message with no provider), OR
  - (b) User clicks "Download Llama" in Settings
- [ ] **3.1.5** NEVER downloads at app launch, NEVER downloads automatically
- [ ] **3.1.6** Add an assertion/guard in `BundledLLMService.downloadAndLoad()` that it's only called from user-initiated actions

#### 3.2 Download progress and cancellation [P1]

- [ ] **3.2.1** Show download progress with: model name, download size, downloaded bytes, speed estimate, ETA
- [ ] **3.2.2** Add "Cancel Download" button for both embedding model and Llama
- [ ] **3.2.3** On cancel, clean up partial downloads (delete temp files)
- [ ] **3.2.4** After cancel, show "Download cancelled" status with a "Retry" button
- [ ] **3.2.5** Ensure UI is not blocked during download (it's already async, but verify)

#### 3.3 Download retry logic [P1]

Neither `EmbeddingService` nor `BundledLLMService` has retry logic. A transient network error permanently fails the download.

- [ ] **3.3.1** Add automatic retry (up to 3 attempts) with exponential backoff for transient errors (timeout, connection reset)
- [ ] **3.3.2** For permanent errors (404, auth failure), fail immediately with a clear error message
- [ ] **3.3.3** Show retry count in progress UI: "Retry 2/3..."
- [ ] **3.3.4** After all retries exhausted, show "Download failed" with manual "Retry" button

**Edge cases:**
- Network disconnects mid-download → detect and retry from where it left off (if HuggingFace supports range requests)
- Device goes to sleep during download → resume on wake
- User switches networks during download → retry

#### 3.4 Disk space validation [P2]

- [ ] **3.4.1** Before downloading, check available disk space against model size
- [ ] **3.4.2** If insufficient space, show an alert: "Not enough disk space. Need X GB, have Y GB available."
- [ ] **3.4.3** Include the check in both `EmbeddingService.ensureModelReady()` and `BundledLLMService.downloadAndLoad()`

#### 3.5 Cache management UI in Settings [P1]

Users should be able to see and manage cached models.

- [ ] **3.5.1** Show cache size for embedding model (compute from `~/.cache/huggingface/hub/` for the specific model)
- [ ] **3.5.2** Show cache size for Llama model
- [ ] **3.5.3** Add "Clear Cache" button for embedding model:
  - Delete cached weights
  - Reset `embeddingModelStatus` to `.notDownloaded`
  - Warn: "You'll need to re-download the model next time you embed documents"
- [ ] **3.5.4** Add "Clear Cache" button for Llama:
  - Delete cached weights
  - Call `unload()` first if loaded
  - Reset `bundledLLMStatus` to `.notDownloaded`
  - Warn: "You'll need to re-download Llama next time you use it"
- [ ] **3.5.5** Show total cache usage at the bottom of each model section

#### 3.6 Cache integrity verification [P2]

If model cache files are corrupted (partial download, disk error), the app should detect and recover.

- [ ] **3.6.1** On app launch, check if the embedding model cache directory exists and has expected files
- [ ] **3.6.2** On app launch, check the same for Llama
- [ ] **3.6.3** If cache exists but is incomplete/corrupted, reset status to `.notDownloaded` and log a warning
- [ ] **3.6.4** Add a "Verify Cache" button in Settings that re-checks integrity
- [ ] **3.6.5** If model loading fails (`.error`), offer "Clear cache and re-download" as a recovery action

**Edge cases:**
- User manually deletes files from `~/.cache/` → app should detect on next use
- Disk corruption → model loading fails → clear and re-download
- Model version mismatch (HuggingFace model updated) → shouldn't happen with pinned model config, but handle gracefully

#### 3.7 Model status callback cleanup [P2]

- [ ] **3.7.1** `EmbeddingService.setStatusCallback` should clear the callback on `deinit` or provide a `clearCallback()` method
- [ ] **3.7.2** `BundledLLMService.setStatusCallback` should do the same
- [ ] **3.7.3** Ensure callbacks don't retain view models (use `[weak self]` consistently)

---

## Epic 4: Chat & RAG Pipeline

**Goal:** Make the chat experience reliable, with proper conversation management, correct RAG retrieval, and resilient streaming.

### Current state

- Conversations are persisted in a separate SQLite DB
- RAG pipeline works: embed query → hybrid search → stream LLM response
- Chunks bar shows results with toggles
- Regenerate replaces the last assistant message
- No auto-scroll, no stop generation, no conversation switching in the UI

### Tasks

#### 4.1 Fix `hasChunkSelectionChanged` logic [P0]

The computed property always returns `true` when chunks exist and the last message is from the assistant, regardless of whether the user actually toggled anything. This makes the Regenerate button always appear.

- [ ] **4.1.1** Track the original inclusion state of each chunk when search results arrive
- [ ] **4.1.2** Compare current inclusion state to original to determine if anything changed
- [ ] **4.1.3** Only show the Regenerate bar when the user has actually toggled a chunk, OR as a deliberate "try again" affordance (document which approach is chosen)

#### 4.2 Auto-scroll to newest message [P1]

- [ ] **4.2.1** Wrap the messages `ScrollView` in a `ScrollViewReader`
- [ ] **4.2.2** Scroll to the bottom when a new message is added
- [ ] **4.2.3** Scroll incrementally as streaming tokens arrive (throttled to avoid jank)
- [ ] **4.2.4** Don't auto-scroll if the user has manually scrolled up (detect scroll position)

#### 4.3 Stop generation button [P1]

- [ ] **4.3.1** Replace the disabled send button with a stop button (square icon) during generation
- [ ] **4.3.2** On tap, cancel the streaming `Task`
- [ ] **4.3.3** Keep the partially generated response as the assistant message (append "[Generation stopped]" or similar)
- [ ] **4.3.4** Persist the partial response to the conversation DB
- [ ] **4.3.5** Re-enable the send button after stopping

#### 4.4 Context window management [P1]

Currently, all included chunks are sent to the LLM regardless of total token count. Large chunk selections can exceed the LLM's context window.

- [ ] **4.4.1** Add a token estimation function (character count / 4 as rough approximation)
- [ ] **4.4.2** Show estimated token count in the Regenerate bar: "3/5 chunks (~2,400 tokens)"
- [ ] **4.4.3** Warn when estimated context exceeds the configured `contextSize`
- [ ] **4.4.4** Optionally auto-truncate: include chunks in order of relevance until the context budget is reached

#### 4.5 Handle zero search results gracefully [P2]

If hybrid search returns 0 chunks (all below `minScore`), the app still tries to generate a response with no context.

- [ ] **4.5.1** When search returns 0 results, show a specific message: "No relevant documents found for this query."
- [ ] **4.5.2** Still allow the user to send to the LLM (without context) if they choose, but make it explicit
- [ ] **4.5.3** Suggest: "Try rephrasing your question, or pin specific documents."

#### 4.6 Persist pinned document IDs [P2]

Pinned documents are in-memory only and lost on app restart.

- [ ] **4.6.1** Store pinned document IDs in UserDefaults (lightweight, session-like persistence)
- [ ] **4.6.2** Load pinned IDs on `ChatViewModel` init
- [ ] **4.6.3** Clear pinned IDs when user explicitly unpins (not on app restart)
- [ ] **4.6.4** Validate that pinned document IDs still exist in the DB (documents may have been deleted)

#### 4.7 Conversation management in Chat UI [P2]

The chat sidebar exists but conversation switching may have UX gaps.

- [ ] **4.7.1** Verify that selecting a conversation in the sidebar loads its messages and previous chunks
- [ ] **4.7.2** Add swipe-to-delete on conversation rows
- [ ] **4.7.3** Add conversation title editing (long press or double click)
- [ ] **4.7.4** Show conversation date and message count in sidebar rows
- [ ] **4.7.5** Add "Delete All Conversations" option

**Edge cases:**
- Delete the currently active conversation → switch to empty state
- Conversation with 0 messages (just created) → show empty state in detail
- Very long conversation (>100 messages) → lazy loading with pagination

---

## Epic 5: Settings & Configuration

**Goal:** Make all configurable parameters accessible, validated, and clearly connected to the features they affect.

### Tasks

#### 5.1 Configurable search parameters [P1]

`k=10` and `minScore=0.1` are hardcoded in `ChatViewModel.sendMessage`.

- [ ] **5.1.1** Add `searchResultCount` (default 10) and `searchMinScore` (default 0.1) to `AppState`
- [ ] **5.1.2** Add a "Search" section in Settings with sliders or text fields for both
- [ ] **5.1.3** Persist to UserDefaults via `saveToUserProfile()`
- [ ] **5.1.4** Pass these values to `hybridSearch()` from `ChatViewModel`

#### 5.2 API key validation [P2]

- [ ] **5.2.1** Add a "Test" button next to each API key field
- [ ] **5.2.2** For Anthropic: send a minimal `messages` request and check for 200
- [ ] **5.2.3** For OpenAI: send a minimal `chat/completions` request and check for 200
- [ ] **5.2.4** Show success (green checkmark) or failure (red X with error message)
- [ ] **5.2.5** For Ollama: test endpoint connectivity and model availability

#### 5.3 Configurable LLM parameters [P2]

Temperature and max tokens are hardcoded in `BundledLLMService`.

- [ ] **5.3.1** Add `temperature` (default 0.6) and `maxTokens` (default 2048) to `AppState`
- [ ] **5.3.2** Add fields in Settings (in the Generation Model section or per-provider)
- [ ] **5.3.3** Pass these to all LLM clients (Anthropic, OpenAI, Ollama, Bundled Llama)

#### 5.4 Database management in Settings [P3]

- [ ] **5.4.1** Show total database file size
- [ ] **5.4.2** Show total chunks count and total documents count
- [ ] **5.4.3** Add "Clear Database" button (deletes all documents, chunks, embeddings) with confirmation
- [ ] **5.4.4** Add "Export Database" option (copy `.db` file to user-chosen location)
- [ ] **5.4.5** Show last indexing date

---

## Epic 6: Error Handling & Resilience

**Goal:** Every error the app can encounter should be visible to the user with a clear recovery path. No silent failures.

### Tasks

#### 6.1 App initialization error handling [P0]

`ChunkpadApp.initializeDatabase()` silently prints errors if either database fails to connect. The user sees a broken app with no explanation.

- [ ] **6.1.1** If main DB connection fails, set `appState.error` with a user-visible message
- [ ] **6.1.2** If conversation DB fails, set a similar error
- [ ] **6.1.3** Show an error banner in the main view on initialization failure
- [ ] **6.1.4** Add a "Retry" button that re-attempts database connection
- [ ] **6.1.5** If both DBs fail, show a full-screen error state (not the normal UI)

#### 6.2 Embedding model error recovery [P1]

If the embedding model fails to load (corrupted cache, incompatible version), the error is shown but there's no recovery path.

- [ ] **6.2.1** On `.error` status, show "Clear cache and re-download" button in the Documents view error banner
- [ ] **6.2.2** Implement cache clearing in `EmbeddingService`: delete model directory, reset status to `.notDownloaded`
- [ ] **6.2.3** On retry after clearing, the next "Embed Selected" will trigger a fresh download

#### 6.3 DocumentProcessor error recovery [P1]

If a single file fails to parse (corrupted PDF, password-protected DOCX, encoding issues), the error is silently logged with `print()` and processing continues. The user never knows a file was skipped.

- [ ] **6.3.1** Collect skipped files and their error reasons into a list
- [ ] **6.3.2** After processing, show a summary: "Processed 12/14 files. 2 files skipped:"
- [ ] **6.3.3** List skipped files with error reasons in a dismissible detail view
- [ ] **6.3.4** Allow the user to retry individual files or ignore them

**Edge cases:**
- Password-protected PDF → show "File is password-protected" (not "Cannot open file")
- File is locked by another process → show "File is in use"
- File encoding is not UTF-8 → try common encodings before failing
- Zero-byte file → skip with "File is empty"
- File larger than memory → warn or limit max file size

#### 6.4 Network error handling for LLM streaming [P2]

- [ ] **6.4.1** Detect network disconnection during streaming and show a specific error
- [ ] **6.4.2** Keep the partially received response visible
- [ ] **6.4.3** Offer "Retry" to resend the same request
- [ ] **6.4.4** Handle rate limiting (429) from cloud providers with appropriate wait-and-retry

---

## Epic 7: Polish & UX

**Goal:** Refine the user experience with quality-of-life improvements.

### Tasks

#### 7.1 Markdown rendering for assistant responses [P2]

Assistant responses render as plain text. Code blocks, lists, headers, and links should render properly.

- [ ] **7.1.1** Add a markdown renderer for assistant messages (consider `AttributedString` or a SwiftUI markdown view)
- [ ] **7.1.2** Support code blocks with syntax highlighting (at least basic)
- [ ] **7.1.3** Support headers, bold, italic, lists, links
- [ ] **7.1.4** Keep `.textSelection(.enabled)` working with rendered markdown

#### 7.2 Distinguish pinned chunks visually [P2]

Pinned document chunks always show 100% relevance, which is misleading.

- [ ] **7.2.1** Show a pin icon instead of a relevance percentage for pinned chunks
- [ ] **7.2.2** Use a distinct card style (e.g., border or tint) for pinned chunks
- [ ] **7.2.3** Group pinned chunks separately at the start of the chunks bar with a label

#### 7.3 Collapsible chunks bar [P3]

The chunks bar takes ~200pt of vertical space. Users should be able to collapse it.

- [ ] **7.3.1** Add a disclosure chevron to toggle the chunks bar visibility
- [ ] **7.3.2** When collapsed, show a compact summary: "5 chunks retrieved (3 selected)"
- [ ] **7.3.3** Persist collapse state for the session

#### 7.4 Pre-query document pinning [P3]

Currently, the pin button only appears after the first search returns results.

- [ ] **7.4.1** Add a "Pin Documents" button in the chat toolbar (always visible)
- [ ] **7.4.2** Show the pin sheet even when no chunks are displayed
- [ ] **7.4.3** When pinned docs exist and user sends first message, include pinned chunks automatically

#### 7.5 Generation mode indicator [P3]

The toolbar picker doesn't indicate which providers are configured.

- [ ] **7.5.1** Show a green dot or checkmark next to providers that have a valid API key configured
- [ ] **7.5.2** Show a gray dot next to unconfigured providers
- [ ] **7.5.3** Disable (or dim) unconfigured providers in the picker to prevent confusion

#### 7.6 Update README.md project structure [P2]

The README.md project structure section is outdated. Missing files:

- [ ] **7.6.1** Add `ChunkFileService.swift`, `ConversationDatabaseService.swift`, `KeychainHelper.swift`, `BundledLLMService.swift` to the project structure
- [ ] **7.6.2** Add `ChunkFileTree.swift`, `IndexedFolder.swift`, `ScoredChunk.swift` to the models section
- [ ] **7.6.3** Add `PinDocumentsSheet.swift`, `GlassIconButton.swift`, `GlassPill.swift` to the views section
- [ ] **7.6.4** Update the TL;DR pipeline diagram to show the two-step indexing flow
- [ ] **7.6.5** Update the Configuration section to mention chunk size/overlap settings

---

## Implementation Order (Recommended)

Suggested sprint order based on dependencies and impact:

### Sprint 1: Data Foundation (Epics 1 + 3)
1. Fix hybridSearch normalization (1.7) — **P0**, quick fix
2. Wrap chunk insertion in transaction (1.3) — **P0**, quick fix
3. Remove orphaned messages table (1.1) — **P0**, quick fix
4. Document and enforce download triggers (3.1) — **P0**, code comments + guards
5. Fix SQL injection (1.8) — **P1**, quick fix
6. Add database migration system (1.2) — **P1**, foundational for everything else
7. Add missing indexes (1.4) — **P1**, runs as first migration

### Sprint 2: Documents Library Core (Epic 2)
1. Embedded vs. pending visual distinction (2.4) — **P0**, critical UX gap
2. Multi-folder support (2.1) — **P1**, depends on 1.5
3. Move IndexedFolder tracking to DB (1.5) — **P1**, blocks 2.1
4. Move embedded chunk IDs to DB (1.6) — **P1**, blocks 2.4
5. Security-scoped bookmark persistence (2.7) — **P1**, blocks reliable multi-folder
6. Folder lifecycle management (2.2) — **P1**, delete/re-process/re-embed

### Sprint 3: Chat Reliability (Epic 4)
1. Fix hasChunkSelectionChanged (4.1) — **P0**, quick fix
2. Auto-scroll (4.2) — **P1**
3. Stop generation (4.3) — **P1**
4. Context window management (4.4) — **P1**

### Sprint 4: Model Management (Epic 3)
1. Download retry logic (3.3) — **P1**
2. Download cancellation (3.2) — **P1**
3. Cache management UI (3.5) — **P1**
4. Cache integrity verification (3.6) — **P2**
5. Disk space validation (3.4) — **P2**

### Sprint 5: Error Handling (Epic 6)
1. App initialization errors (6.1) — **P0**
2. Embedding model error recovery (6.2) — **P1**
3. DocumentProcessor error reporting (6.3) — **P1**
4. Network error handling (6.4) — **P2**

### Sprint 6: Polish (Epics 5 + 7)
1. Configurable search parameters (5.1) — **P1**
2. Chunk grid view overhaul (2.3) — **P1**
3. Stale chunk detection (2.5) — **P1**
4. Markdown rendering (7.1) — **P2**
5. All remaining P2/P3 tasks

---

## Tracking

- [ ] = Not started
- [~] = In progress
- [x] = Done
- [-] = Cancelled/deferred

Update this file as work progresses. Each task ID (e.g., 1.7, 2.4.1) can be referenced in commit messages and PR descriptions.
