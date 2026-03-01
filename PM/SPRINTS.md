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
