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

## Sprint 13: Table Parsing + Section-Aware Chunking ✅ Complete

**Goal:** Improve document parsing with proper table handling and section-aware chunking for better knowledge extraction.
**Status:** Complete

### Tasks

#### 12.1 DOCX table extraction via HTML [P1] ✅

- [x] Changed `textutil -convert txt` to `textutil -convert html` via new `runTextutilHTML(at:)` method
- [x] Added `htmlToMarkdown(_ html:)` — finds `<table>...</table>` blocks, converts to markdown tables
- [x] Added `parseHTMLTable(_ tableHTML:)` — extracts `<tr>` rows, `<td>`/`<th>` cells, builds pipe-separated markdown
- [x] Non-table HTML content stripped of tags with `stripHTMLTags(_ html:)`, common entities decoded
- [x] Column count normalized across rows; pipes in cell content escaped with `\|`
- [x] v1 scope: skips nested tables and colspan/rowspan (treated as flat text)

#### 12.2 PDF heuristic table detection [P2] ✅

- [x] Added `detectAndConvertTables(in text:)` — scans plain text for tabular patterns
- [x] Tab-separated detection: lines with 1+ tab character grouped into table blocks (min 2 rows)
- [x] Multi-space aligned columns: `detectAlignedColumns(lines:)` finds consistent 3+ space gaps across 60%+ of lines
- [x] `splitByColumnPositions(_:positions:)` splits lines by detected column boundaries
- [x] Integrated into `processPDF` after `page.string` extraction

#### 12.3 Plain text table detection [P3] ✅

- [x] Reuses `detectAndConvertTables(in:)` from 12.2 in `processPlainText`
- [x] Applied before markdown wrapping so tables in .txt files are converted

#### 12.4 Section-aware chunking [P1] ✅

- [x] Added `splitIntoSectionChunks(…)` — splits at markdown heading boundaries (`# / ## / ###`)
- [x] `parseMarkdownSections(_ text:)` — parses headings with level tracking and heading stack
- [x] `containsMarkdownHeadings(_ text:)` — detects headings outside fenced code blocks
- [x] `removeFencedCodeBlocks(_ text:)` — prevents false heading matches inside ``` blocks
- [x] Oversized sections fall back to paragraph splitting via `splitIntoParagraphChunks`
- [x] `splitIntoChunks` now auto-delegates to section-aware path when headings detected
- [x] Original paragraph-splitting logic preserved as `splitIntoParagraphChunks` (unchanged behavior)

#### 12.5 Hierarchical chunk titles [P2] ✅

- [x] `MarkdownSection` struct tracks `headingPath: [String]` — hierarchical heading ancestry
- [x] Heading stack maintained during parsing: pops headings at same or deeper level
- [x] `buildHierarchicalTitle(from:)` joins path as `"Document > Section > Subsection"`
- [x] Oversized sections that fall back to paragraph splitting append `[N]` suffix
