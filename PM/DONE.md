# Chunkpad — Completed Sprints

> Completed sprints are moved here from `SPRINTS.md` in their entirety.
> This is an **append-only archive** — never edit past sprints.
> Read this file only when you need historical context about what was built and why.

---

## Sprint 12: Model Upgrade + File Naming Fix ✅ Complete

**Goal:** Upgrade embedding model to bge-large-en-v1.5 (1024 dims), tie chunk size defaults to model token window, and fix chunk file naming bug.
**Status:** Complete

### Tasks

#### 10.1 Upgrade EmbeddingService to bge-large [P0] ✅
- [x] Changed `modelConfiguration` from `.bge_base` to `.bge_large`
- [x] Changed `embeddingDimension` from 768 to 1024
- [x] Updated `modelDisplayName`, `modelID`, `modelSize` (~1.3 GB)
- [x] Updated doc comment block for 1024 dims / 1.3 GB

#### 10.2 Update DatabaseService schema (768→1024) [P0] ✅
- [x] Bumped `currentSchemaVersion` from 9 to 10
- [x] Changed CREATE TABLE `float[768]` to `float[1024]`
- [x] Migration case 10: DROP + recreate vec_chunks with 1024 dims
- [x] Clear `embedded_chunk_refs` in migration (all embeddings invalidated)

#### 10.3 Add maxTokenWindow to EmbeddingService [P1] ✅
- [x] `static let maxTokenWindow: Int = 512` (BERT max_position_embeddings)

#### 10.4 Update AppState chunk size defaults [P1] ✅
- [x] Default `chunkSizeTokens` from 1000 to 512
- [x] `loadFromUserProfile()` fallback uses `EmbeddingService.maxTokenWindow`
- [x] `DocumentProcessor.defaultChunkSizeChars` derived from `EmbeddingService.maxTokenWindow * 4`

#### 10.5 Model-aware chunk size in SettingsView [P2] ✅
- [x] "Embedding model" and "Model token limit" labels
- [x] Orange warning when `chunkSizeTokens > maxTokenWindow`

#### 11.1 Fix chunkFileURL extension stripping [P0] ✅
- [x] `deletingPathExtension` before `appendingPathExtension("md")` in both code paths
- [x] Example: `report.pdf` → `report.md` (was `report.pdf.md`)

#### 11.2 Update inferSourcePath for new naming [P1] ✅
- [x] Updated doc comments to reflect extensionless inferred paths

#### Stale reference cleanup ✅
- [x] Updated doc comments in BundledLLMService, ChatViewModel, IndexingViewModel from bge-base to bge-large

---

## Sprint 11: Final Backlog + Release Prep ✅ Complete

**Goal:** Implement the last remaining backlog item and harden the codebase for first stable release.
**Status:** Complete

### Tasks

#### 2.4.3 Per-folder aggregate status badge [P3] ✅

- [x] **2.4.3.1** Add `folderAggregateStatus(for:)` to IndexingViewModel — recursively collects file statuses
- [x] **2.4.3.2** Logic: all files `.allEmbedded` → green; any embedded → orange; none → gray
- [x] **2.4.3.3** Display colored dot on folder rows in the sidebar (same style as file rows)

#### Release hardening ✅

Full codebase audit and fixes for v1.0 stability.

- [x] Fix 2 compiler warnings: unused `withUnsafeBufferPointer` / `withUnsafeBytes` results in DatabaseService
- [x] Fix force unwrap on `FileManager.urls().first!` in DatabaseService and ConversationDatabaseService — replaced with `guard let` + `fatalError`
- [x] Fix force unwrap on `buffer.baseAddress!` in `embeddingToBlob` — replaced with `guard let`
- [x] Replace 8 silent `try?` conversation DB writes with logged `persistMessage`/`persistConversationTitle` helpers using `os.log`
- [x] Build: zero errors, zero warnings

---

## Sprint 10: Final Polish ✅ Complete

**Goal:** Surface hidden state, fix UX edge cases, add database management, and close out remaining polish tasks.
**Status:** Complete

### Tasks

#### 9.3 Auto-clear chunk filter on file switch [P3] ✅
- [x] `.onChange(of: selectedNodeID) { _, _ in chunkFilter = "" }`

#### 9.1 Surface droppedChunkCount in regenerate bar [P2] ✅
- [x] Orange "N trimmed to fit budget" text in regenerate bar when `droppedChunkCount > 0`

#### 9.2 Validate pinned docs after delete [P2] ✅
- [x] `documentDeletedNotification` static property on IndexingViewModel
- [x] MainView `.onReceive` listener calls `chatViewModel.validatePinnedDocuments()`

#### 7.3 Collapsible chunks bar [P3] ✅
- [x] `isChunksBarCollapsed` state with chevron toggle
- [x] Compact summary: "N/M chunks · ~X tokens"

#### 5.4 Database management in Settings [P3] ✅
- [x] Stats display: document count, chunk count, formatted file size
- [x] "Clear All Data…" destructive button with confirmation dialog
- [x] `totalChunkCount()` and `databaseFileSize()` methods on DatabaseService

#### 7.5 Generation mode indicator [P3] ✅
- [x] Green/gray dot per provider in toolbar picker
- [x] `isProviderConfigured(_:)` checks API key / endpoint presence

---

## Sprint 9: Chat UX + Cleanup ✅ Complete

**Goal:** Fix streaming scroll, add context budget enforcement, always-visible pinning, and clean up tech debt.
**Status:** Complete

### Tasks

#### 4.2.3 Throttled streaming scroll [P1] ✅

- [x] Timer.publish(every: 0.3) + onReceive scrolls to "bottom" anchor
- [x] Guard on `isGenerating` — timer fires continuously but only scrolls when generating
- [x] Stop the timer when `isGenerating` flips to false — guard statement in onReceive

#### 4.4.4 Auto-truncate context to budget [P2] ✅

- [x] `estimateTokens(_:)` helper (chars / 4 approximation)
- [x] In `buildContext`, drop lowest-relevance non-pinned chunks until under `contextSize × 0.8`
- [x] Track dropped chunk count via `droppedChunkCount` property
- [x] Always keep at least 1 chunk; never drop pinned chunks

#### 7.4 Pre-query document pinning [P2] ✅

- [x] Persistent pin button in `inputBar` — always visible, `pin`/`pin.fill` icon
- [x] Opens PinDocumentsSheet same as current flow
- [x] Orange count badge when pins are active

#### 8.1 Extract shared generation task code [P1] ✅

- [x] `runGeneration(client:contextMessages:assistantIndex:)` private method
- [x] Both `sendMessage` and `regenerate` call the shared method
- [x] Error handling, cancellation, and DB persistence remain identical

#### 8.2 Fix compiler warnings in ChatView [P1] ✅

- [x] Replaced unused `if let provider =` with `!= nil` checks

#### 8.3 Remove dead indexFolder code path [P2] ✅

- [x] Removed `selectAndIndexFolder()` and `indexFolder()` (~100 lines)

#### 7.6 Update README.md project structure [P2] ✅

- [x] Added 7 missing files; alphabetized entries within each section

---

## Sprint 8: Documents Polish ✅ Complete

**Goal:** Robust document lifecycle — delete documents/chunks, persist pinned docs and modification dates, conversation management UX, and chunk view overhaul.
**Status:** ✅ Complete

### Tasks

#### 4.6 Persist pinned document IDs [P2] ✅

Pinned document IDs are in-memory only (`ChatViewModel.pinnedDocumentIDs`). After app restart, all pins are lost.

- [x] **4.6.1** Add `pinnedDocumentIDs` ProfileKey in `AppState` and `Set<String>` property with load/save via UserDefaults
- [x] **4.6.2** In `ChatViewModel`, computed property backed by `appState.pinnedDocumentIDs`; saves on toggle
- [x] **4.6.3** Validate pinned IDs on load — `validatePinnedDocuments()` removes IDs for deleted documents

**Edge cases:**
- Pinned doc deleted between sessions → silently removed from set on validation
- Empty set → UserDefaults key removed

#### 2.5.1 Persist lastKnownModificationDates to DB [P2] ✅

`IndexingViewModel.lastKnownModificationDates` is in-memory only. After restart, modification detection always reports no changes.

- [x] **2.5.1.1** Persist as `[String: TimeInterval]` in UserDefaults (key: `indexing_last_known_modification_dates`)
- [x] **2.5.1.2** Load in `IndexingViewModel.init()`; auto-save via `didSet` on property
- [x] **2.5.1.3** Clear persisted data on removeFolder() and clearAllData() (via property reset triggering didSet)

**Edge cases:**
- Loading bypass: `isLoadingPersistedDates` flag prevents re-persisting during load

#### 2.6 Delete individual documents/chunks [P2] ✅

No UI to delete individual documents or chunks. Users can only "Clear All Data".

- [x] **2.6.1** Add `deleteChunk(id:)` to `DatabaseService` — cascades vec_chunks → embedded_chunk_refs → chunks
- [x] **2.6.2** Add `deleteDocument(id:)` and `deleteChunk(id:)` methods to `IndexingViewModel`
- [x] **2.6.3** Context menu "Delete Document" on document rows in DocumentsView flat list
- [x] **2.6.4** Context menu "Delete Chunk" on chunk rows in DocumentsView detail
- [x] **2.6.5** Confirmation alerts before deletion
- [x] **2.6.6** Refresh document list / chunk tree after deletion; update AppState.indexedDocumentCount

**Edge cases:**
- Delete while indexing → disabled via `viewModel.isIndexing` guard

#### 4.7 Conversation management UX [P2] ✅

No way to rename, delete, or manage conversations from the sidebar.

- [x] **4.7.1** Added `messageCount(conversationId:)` to `ConversationDatabaseService`
- [x] **4.7.2** Added `messageCount` field to `Conversation` struct; populated in `refreshConversations()`
- [x] **4.7.3** Message count displayed in sidebar row (e.g. "· 5 msgs")
- [x] **4.7.4** Context menu on conversation rows: "Rename" and "Delete"
- [x] **4.7.5** Swipe-to-delete on conversation rows
- [x] **4.7.6** Delete confirmation alert; switches to "New Chat" if deleting active conversation
- [x] **4.7.7** Rename alert with TextField; calls `updateConversation(id:title:updatedAt:)`

**Edge cases:**
- Rename to empty string → no-op (trimmed, guard !isEmpty)
- Delete active conversation → clears messages and currentConversationId

#### 2.3 Chunk grid/list view overhaul [P1] ✅

Chunk display is a plain list only. No view mode toggle, no grid cards, no filter bar.

- [x] **2.3.1** Added `ChunkViewMode` enum (`.list`, `.grid`) with segmented picker in toolbar
- [x] **2.3.2** Grid view: `LazyVGrid` with adaptive columns (min 260), cards showing status, title, content preview, char count
- [x] **2.3.3** Filter bar: TextField for searching chunks by title/content with clear button
- [x] **2.3.4** Persisted view mode in UserDefaults (`documents_chunk_view_mode`)
- [x] **2.3.5** Grid cards use Liquid Glass design (glassEffect, GlassTokens, ChunkStatusBadge)
- [x] **2.3.6** Empty filter state shows `ContentUnavailableView.search`

---

## Sprint 7: Settings + Polish ✅ Complete

**Goal:** Expose configurable search and generation parameters; add markdown rendering and pinned-chunk polish.

### 5.1 Configurable search parameters [P1] ✅
- [x] `searchResultCount: Int` (default 10) and `searchMinScore: Double` (default 0.1) in AppState
- [x] Persisted to UserDefaults via `saveToUserProfile` / `loadFromUserProfile`
- [x] Passed through `ChatViewModel.sendMessage` → `database.hybridSearch` with clamping (k ∈ [1,20], minScore ∈ [0,1])
- [x] Search section in SettingsView: TextField for max results, Slider for min relevance score

### 5.2 API key validation ("Test" button) [P2] ✅
- [x] "Test API Key" button for Anthropic (POST `/v1/messages` with `max_tokens: 1`)
- [x] "Test API Key" button for OpenAI (GET `/v1/models`)
- [x] "Test Connection" button for Ollama (GET `{endpoint}/api/tags` with 5s timeout)
- [x] Inline spinner/checkmark/error indicators; validation resets on key change

### 5.3 Configurable LLM parameters [P2] ✅
- [x] `llmTemperature: Double` (default 0.7) and `llmMaxTokens: Int` (default 4096) in AppState
- [x] `temperature` and `maxTokens` added to `CloudConfig` and `LocalConfig`
- [x] Threaded through `LLMServiceFactory` to all 4 clients (Anthropic, OpenAI, Ollama, BundledLLM)
- [x] "LLM Parameters" section in SettingsView: Slider for temperature, TextField for max tokens

### 7.1 Markdown rendering for assistant responses [P2] ✅
- [x] `MarkdownContentView` replaces plain `Text` for assistant messages
- [x] Fenced code blocks render in monospace with `.quaternary.opacity(0.3)` background
- [x] Inline markdown via `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)`
- [x] Graceful fallback to plain text for malformed markdown

### 7.2 Distinguish pinned chunks visually [P2] ✅
- [x] `isPinned: Bool = false` on `ScoredChunk`; set `true` in `addPinnedChunks`
- [x] Pin icon badge + "Pinned" orange pill in `ChunkPreview` header
- [x] Orange-tinted glass effect background for pinned cards

---

## Sprint 6: Error Handling ✅ Complete

**Goal:** Every error the app can encounter is visible to the user with a clear recovery path. No silent failures.

### 6.1 App initialization error handling [P0] ✅
- [x] `AppState.initError: String?` — set when main DB connect fails
- [x] `AppState.conversationDBError: String?` — set when chat DB connect fails
- [x] `AppState.retryDatabaseInit: (() async -> Void)?` — callback wired in ChunkpadApp
- [x] `MainView` persistent error banner (red background, DB icon, message, Retry button)
- [x] Chat and Documents sidebar entries disabled/greyed when DB unavailable
- [x] `ChunkpadApp.initializeDatabase()` promoted to `@MainActor func` (was private)
- [x] Retry button calls `appState.retryDatabaseInit?()` — no App reference needed

### 6.2 Embedding model error recovery [P1] ✅
- [x] `DocumentsView.errorBanner` detects `embeddingModelStatus == .error`
- [x] "Clear Cache & Retry" button shown alongside Dismiss when in error state
- [x] `IndexingViewModel.clearEmbeddingCacheForRecovery()` — deletes HuggingFace hub cache dir, resets status to `.notDownloaded`
- [x] Next "Embed Selected" triggers fresh download automatically

### 6.4 Network error handling for LLM streaming [P2] ✅
- [x] `StreamingErrorKind` enum: `.connectionLost`, `.rateLimited(retryAfter: Int?)`, `.other(String)`
- [x] `ChatViewModel.streamingError: StreamingErrorKind?` — set on streaming failure
- [x] `ChatViewModel.classify(_ error:)` — detects URLError.networkConnectionLost and HTTP 429 messages; parses Retry-After value
- [x] Both `sendMessage` and `regenerate` classify errors, set `streamingError`, keep partial response
- [x] `ChatView.errorBanner` accepts `streamingError:` param; shows "Retry" button when `kind.canRetryNow`
- [x] `ChatViewModel.retryLastMessage()` — re-runs generation with stored `pendingRetryProvider` + existing chunks
- [x] `lastUserQuery` and `pendingRetryProvider` stored on each send/regenerate

### 6.3.4 Retry individual parse-failed files [P2] ✅
- [x] `DocumentProcessor.processDirectory(skipped:)` — new overload captures `(url, reason)` pairs; backward-compatible no-`skipped` overload preserved
- [x] `IndexingViewModel.skippedFiles: [(url: URL, reason: String)]` — populated after `processFolder`
- [x] `IndexingViewModel.retrySkippedFile(at:)` — re-runs `processFile`, writes chunks, refreshes tree on success; updates reason on failure; handles missing file
- [x] `DocumentsView.skippedFilesBanner` — lists each failed file with name, reason, and per-file "Retry" button
- [x] Banner shown below error banner when `!viewModel.skippedFiles.isEmpty`

**Implementation notes:**
- Main repo doesn't have Sprint 5 `EmbeddingService`/`BundledLLMService` extensions — `clearEmbeddingCacheForRecovery` uses direct `FileManager` deletion instead
- `StreamingErrorKind.canRetryNow` returns false for `.rateLimited` so no retry button appears on 429 (user must wait)
- `@ObservationIgnored` used on `retryDatabaseInit` to prevent the `@Observable` macro from tracking the closure

---

## Sprint 1: Data Foundation ✅ Complete

**Goal:** Clean persistence architecture, versioned migrations, no data loss.

### Completed Tasks

#### 1.1 Remove orphaned `messages` table from main DB schema ✅
- [x] Remove `CREATE TABLE messages` from `DatabaseService.createTables()`
- [x] Add migration: `DROP TABLE IF EXISTS messages` for existing databases
- [x] Verify no code references `messages` in `DatabaseService`

#### 1.2 Add database migration system ✅
- [x] `schema_version` pragma in both databases
- [x] Versioned `migrate()` in `DatabaseService` and `ConversationDatabaseService`
- [x] Each migration runs in `BEGIN`/`COMMIT`/`ROLLBACK`
- [x] Documented in ARCHITECTURE.md

#### 1.3 Wrap chunk insertion in a transaction ✅
- [x] `insertDocumentWithChunks` uses `performTransaction`
- [x] `deleteDocument(id:)` wrapped in `performTransaction`; also cascades `embedded_chunk_refs`

#### 1.4 Add missing database indexes ✅
- [x] `idx_chunks_document_id` (migration 2)
- [x] `idx_chunks_source_path` (migration 9+)
- [x] `messages.conversation_id` + `messages.timestamp` indexes in chat DB

#### 1.5 Move IndexedFolder tracking to main DB ✅
- [x] `indexed_folders` table with `id, root_path, chunks_root_path, created_at, last_processed_at, file_count, chunk_count, bookmark_data`
- [x] Migrated from UserDefaults (migration 4)
- [x] Multi-folder support in `IndexingViewModel`

#### 1.6 Move embedded chunk IDs to main DB ✅
- [x] `embedded_chunk_refs` table: `chunk_ref_id, chunk_id, embedded_at, content_hash`
- [x] `content_hash TEXT` column (schema v10) for stale detection
- [x] Migrated from UserDefaults (migration 6)
- [x] `IndexingViewModel.embeddedChunkRefs` reads from DB with cache-generation counter

#### 1.7 Fix hybridSearch normalization ✅
- [x] Normalization: `result.rank / minRank` (both negative → positive 0–1)
- [x] Guard + clamping; `minScore` threshold filtering verified

#### 1.8 Fix SQL injection in ConversationDatabaseService ✅
- [x] `LIMIT ?` parameterized query
- [x] Full audit of both services

#### 1.9 Document the persistence contract ✅
- [x] "Persistence Contract" section added to ARCHITECTURE.md

---

## Sprint 2: Documents Library Core ✅ Complete

**Goal:** Multi-folder support, security bookmarks, stale detection, full folder lifecycle.

### Completed Tasks

#### 2.1 Multi-folder support ✅
- [x] `indexedFolders: [IndexedFolder]` + `selectedFolderID` + `selectFolder(id:)` in `IndexingViewModel`
- [x] Folder switcher Section in Documents sidebar
- [x] `selectFolder(id:)` guards `!folder.isAccessible` — surfaces error, leaves selection unchanged
- [x] Security-scoped bookmarks per folder (see 2.7)

#### 2.2 Folder lifecycle management ✅
- [x] "Remove Folder" with cascade delete + optional `_chunks/` removal + stops bookmark access
- [x] `removeFolder` / `clearAllData` nil `selectedFolderID` when it matches
- [x] "Re-process Folder" (`reprocessFolder`) with `isAccessible` guard
- [x] "Re-embed All Chunks" (`reembedAllChunks`)
- [x] "Clear All Data…" with two-option confirmation

#### 2.4 Embedded vs. pending visual distinction ✅
- [x] Per-chunk status badges: green ✓ (embedded), orange ⚠ (stale), orange ⏱ (pending), gray ○ (excluded)
- [x] Per-file aggregate status in tree sidebar

#### 2.5 Stale chunk detection (core) ✅
- [x] SHA-256 content hash (CRLF-normalised `\r\n→\n`) stored in `embedded_chunk_refs.content_hash`
- [x] On app activation + Documents view appear: check modified chunk files
- [x] Stale chunks shown with orange ⚠ badge
- [x] Re-embed only stale/pending chunks; updates `content_hash` after embedding
- [x] `cacheGeneration` counter invalidates computed `reviewableChunks` cache

#### 2.7 Security-scoped bookmark persistence ✅
- [x] `BookmarkService.createBookmark(for:)` stored as BLOB in `indexed_folders.bookmark_data`
- [x] On launch: resolves all bookmarks, starts scoped access; stale bookmarks auto-refreshed
- [x] `stopAccessingSecurityScopedResource()` on remove/clear/shutdown
- [x] Inaccessible folder banner with "Re-select" and "Remove" actions

#### 2.8 Cancel processing and embedding ✅
- [x] "Cancel" button during processing and embedding
- [x] `cancelCurrentOperation()` cancels `currentTask: Task<Void, Never>?`
- [x] `resetProgressState()` atomically resets all progress fields on cancel

#### Batch UI (subset of 2.3) ✅
- [x] "Select All / Deselect All" per file
- [x] "Expand All / Collapse All" per file
- [x] `expandedChunks: Set<String>` state

#### Onboarding pill indicator ✅
- [x] 3-step pill indicator in DocumentsView (hidden once all embedded)

---

## Sprint 3: Correctness & Architectural Cleanup ✅ Complete

**Goal:** Decouple view models from AppState, fix orphan data, enforce invariants.

### Completed Tasks

#### IndexingStateDelegate protocol ✅
- [x] `IndexingStateDelegate` protocol in `AppState.swift` (4 requirements: `chunkSizeChars`, `chunkOverlapChars`, `updateEmbeddingModelStatus`, `updateIndexedDocumentCount`)
- [x] `IndexingViewModel.delegate: (any IndexingStateDelegate)?` (replaces `appState: AppState?`)
- [x] `DocumentsView.onAppear` assigns `viewModel.delegate = appState`

#### ChatStateDelegate protocol ✅
- [x] `ChatStateDelegate` protocol (3 requirements: `indexedDocumentCount`, `bundledLLMStatus`, `conversationDatabase`)
- [x] `ChatViewModel.delegate: (any ChatStateDelegate)?`
- [x] `MainView.onAppear` assigns `chatViewModel.delegate = appState`

#### deleteDocument orphan cleanup ✅
- [x] `deleteDocument(id:)` also deletes `embedded_chunk_refs WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)`

#### defer { isIndexing = false } ✅
- [x] `processFolder`, `indexFolder`, `_embedApprovedChunksBody` all use `defer { isIndexing = false }`
- [x] Empty-folder early-return calls `resetProgressState()` instead of bare `isIndexing = false`

#### deleteEmbeddedChunkRefs rename ✅
- [x] `deleteEmbeddedChunkRefs(forChunkFilePath:)` — `::` separator baked in internally

#### selectFolder accessibility guard ✅
- [x] `selectFolder(id:)` guards `!folder.isAccessible`, surfaces error, leaves selection unchanged

#### SHA-256 CRLF normalization ✅
- [x] `sha256` normalises `\r\n → \n` before hashing (false-stale prevention)

#### selectFolder modification date reseeding ✅
- [x] `selectFolder(id:)` resets `lastKnownModificationDates` + `hasModifiedChunkFiles` and reseeds from new tree

#### Parse warnings UI ✅
- [x] `processDirectory` returns `(results, skipped)` tuple
- [x] `parseWarnings: [(fileName, reason)]` surfaced in Documents view after processing

---

## Sprint 4: Chat Reliability ✅ Complete

**Goal:** Correct chunk selection tracking, auto-scroll, stop button, context awareness.

### Completed Tasks

#### 4.1 Fix hasChunkSelectionChanged logic ✅
- [x] `originalChunkInclusions: [String: Bool]` — snapshot at search result arrival
- [x] `hasChunkSelectionChanged` diffs current vs snapshot; only `true` when user toggled
- [x] Snapshot reset after `regenerate()`, on conversation load/create, on `clearConversation()`

#### 4.2 Auto-scroll ✅ (4.2.3 throttle deferred)
- [x] `ScrollViewReader` with `"bottom"` anchor
- [x] Scroll on new message count — guarded by `!userHasScrolledUp`
- [x] `ScrollOffsetKey: PreferenceKey` via `GeometryReader`; `userHasScrolledUp = offset < -40`
- [x] Reset `userHasScrolledUp = false` when generation starts

#### 4.3 Stop generation button ✅
- [x] `cancelGeneration()` cancels streaming `Task`
- [x] Partial response appended with `\n\n(Stopped)`, persisted to DB
- [x] Send button shows `stop.circle.fill` + calls `cancelGeneration()` during `isGenerating`

#### 4.4 Context window management ✅ (4.4.4 auto-truncate deferred)
- [x] `estimatedIncludedTokens: Int` — sum of included chunk content lengths / 4
- [x] Regenerate bar: "N/M chunks (~X,XXX tokens)" — orange when over `contextSize`
- [x] Orange ⚠ triangle with tooltip when over budget

#### 4.5 Zero search results handling ✅
- [x] When `scoredChunks.isEmpty`: assistant message with rephrase/pin hint, persisted to DB, early return

---

## Sprint 5: Model Management ✅ Complete

**Goal:** Make model downloads transparent, resilient, and manageable.

### Completed Tasks

#### 3.1.6 Assert download is user-initiated in BundledLLMService ✅
- [x] `downloadAndLoad()` has a doc-comment listing the only 2 valid call sites: `ChatViewModel.downloadLlamaAndSend()` and the Settings "Download Llama" button
- [x] Comment explicitly states the function MUST NOT be called automatically or at launch

#### 3.2 Download cancellation ✅
- [x] `cancelDownload()` added to both `BundledLLMService` and `EmbeddingService` — cancels the active `downloadTask: Task` and resets status to `.cancelled`
- [x] "Cancel Download" button appears in Settings embeddings section and Llama section while `isDownloading` is true
- [x] On cancel: `downloadTask?.cancel()`, status set to `.cancelled`, all pending continuations resumed with failure
- [x] After cancel: Settings shows "Download cancelled. Tap Download / Re-index to retry." hint

#### 3.3 Download retry logic ✅
- [x] `downloadAndLoad()` in both services retries up to 3 attempts with exponential backoff (1s, 2s, 4s)
- [x] Permanent errors (404, unauthorized, forbidden) fail immediately — no retry
- [x] Status shows "Retry N/M…" between attempts via `.retrying(attempt:of:)` case
- [x] Progress label includes "(Retry N/M)" suffix during retry downloads via `retryLabel` param
- [x] After 3 failures: status set to `.error(msg)`, Settings shows error text with "Clear Cache and Reset" recovery

#### 3.4 Disk space validation ✅
- [x] Before download: `availableDiskSpaceBytes()` checks `NSHomeDirectory` free space
- [x] Embedding model: aborts if < 438 MB available; Llama: aborts if < 1.7 GB available
- [x] Error message: "Not enough disk space. Need X GB, have Y GB available."
- [x] Status set to `.error(msg)` so the UI surfaces the message

#### 3.5 Cache management UI in Settings ✅
- [x] `cacheSize() -> Int64?` added to `EmbeddingService` and `BundledLLMService` — walks cache directory via `fileSizeKey`
- [x] Settings shows "Cache Size: X MB" for both models (refreshed on `.onAppear` and after actions)
- [x] "Clear Embedding Cache" button (visible when cache is present): calls `deleteCache()`, resets status to `.notDownloaded`
- [x] "Clear Cache from Disk" button for Llama (visible when ready): calls `unloadAndDeleteCache()` — unloads first, then deletes
- [x] "Clear Cache and Reset" recovery button shown when status is `.error`

#### 3.6 Cache integrity verification ✅
- [x] `verifyCacheIntegrity()` in both services: checks for at least one `.safetensors` file in cache dir
- [x] `checkCacheIntegrityOnLaunch()` called from `ChunkpadApp.initializeDatabase()` for `BundledLLMService`; resets to `.notDownloaded` if incomplete
- [x] "Verify Cache" button in Settings for both models: runs check, shows green "✓ cache looks good" or orange warning; resets status if incomplete
- [x] `.error` status shows "Clear cache and re-download" recovery text + button in Settings (3.6.4)

#### BundledLLMStatus / EmbeddingModelStatus enum updates ✅
- [x] Added `.cancelled` case to both enums
- [x] Added `.retrying(attempt: Int, of: Int)` case to both enums
- [x] `BundledLLMStatus.downloading` now has `(progress, attempt, of)` params
- [x] `EmbeddingModelStatus.downloading` now has `(progress, bytesReceived, totalBytes, retryLabel)` params
- [x] `isDownloading: Bool` computed var added to both (covers `.downloading`, `.retrying`, `.loading`)
- [x] All call sites updated: `ChatViewModel` (`.downloading(let p, _, _)`), `IndexingViewModel` (`.downloading(let p, _, _, _)`)
- [x] `clearStatusCallback()` added to both services (3.7.1–3.7.2)
