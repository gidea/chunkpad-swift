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

## Sprint 11: Final Backlog + Release Prep ✅ Complete

**Goal:** Implement the last remaining backlog item and harden the codebase for first stable release.
**Status:** Complete

### Tasks

#### 2.4.3 Per-folder aggregate status badge [P3] ✅

Folder nodes in the chunk tree sidebar show no embedding status. Only files have status dots.

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
