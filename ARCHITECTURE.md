# Chunkpad Architecture

**Local-First RAG on Apple Silicon**

Date: February 12, 2026
Status: **CURRENT ARCHITECTURE**

---

## Executive Summary

Chunkpad is a native macOS app that turns your local documents into a searchable, AI-queryable knowledge base. The core design principles:

- **Embedded database** -- SQLite + sqlite-vec. No external servers, no Docker, no PostgreSQL. The database is a single file.
- **On-device embeddings** -- MLX Swift running BAAI/bge-base-en-v1.5 on Apple Silicon. Documents never leave your Mac during indexing.
- **Two-step indexing** -- Documents are processed in two explicit steps: (1) parse and chunk into editable markdown files on disk, (2) review and embed into the vector database. This gives users full control over what gets indexed.
- **Lazy model downloads** -- Neither the embedding model nor the local LLM is bundled with the app. The embedding model (~438 MB) is downloaded from HuggingFace only when the user clicks "Embed Selected" (Step 2 of indexing). Llama 3.2 (~1.7 GB) is downloaded only when the user explicitly accepts the offer (no cloud API key configured). If you just want the UI, no downloads happen.
- **Flexible generation** -- User chooses between cloud LLMs (Claude, ChatGPT), local LLMs (Ollama), or bundled Llama 3.2. Both cloud API keys can be configured simultaneously for easy switching. If no API key is set, the app offers to download Llama for free local generation. User is always in control.
- **Liquid Glass UI** -- macOS 26 native design with `.glassEffect()` throughout. Design values (corner radii, spacing, padding) are centralized in `GlassTokens` to maintain accessibility control, since Liquid Glass has known legibility and contrast issues in its initial release. Reusable glass components (`GlassCard`, `GlassIconButton`, `GlassPill`) keep styling consistent.

---

## Architecture Decisions

### Why SQLite + sqlite-vec (not PostgreSQL + pgvector)

The original plan called for local PostgreSQL + pgvector. We changed to SQLite + sqlite-vec because:

| Factor | PostgreSQL + pgvector | SQLite + sqlite-vec |
|---|---|---|
| **Distribution** | Requires Postgres install (Docker/Homebrew) | Ships with the app (single file DB) |
| **User experience** | Complex first-run setup | Zero setup |
| **App size impact** | None (external) | ~1 MB (vendored C source) |
| **Concurrency** | Full server | WAL mode (sufficient for single-user) |
| **Vector search** | HNSW index | KNN with cosine distance |
| **Full-text search** | Built-in tsvector | FTS5 (built into macOS system SQLite) |
| **macOS integration** | Needs PostgreSQL running | Uses system sqlite3 library |

**Decision:** SQLite + sqlite-vec is the right choice for a single-user desktop app. No external dependencies, zero setup, and the database is a portable file.

### Why MLX Swift (not Ollama for embeddings)

The original plan used Ollama's embedding API. We changed to MLX Swift because:

| Factor | Ollama Embeddings | MLX Swift |
|---|---|---|
| **Dependency** | Requires Ollama running | None (framework in app) |
| **Performance** | HTTP API overhead | Direct Metal GPU compute |
| **Privacy** | Local but external process | In-process, fully sandboxed |
| **Apple Silicon** | Generic (CPU or GPU) | Optimized for M-series chips |
| **User setup** | Install Ollama + pull model | Automatic (model auto-downloads) |

**Decision:** MLX Swift provides the best UX -- zero setup, native Apple Silicon performance, and no external processes.

### Why bge-base-en-v1.5 (not MiniLM or nomic-embed)

| Factor | all-MiniLM-L6-v2 | nomic-embed-text | **bge-base-en-v1.5** |
|---|---|---|---|
| **Dimensions** | 384 | 768 | **768** |
| **Parameters** | 22M | 137M | **109M** |
| **MTEB Retrieval** | 41.95 | 55.12 | **53.25** |
| **Download size** | ~90 MB | ~548 MB | **~438 MB** |
| **RAG quality** | Good | Best | **Excellent** |
| **MLXEmbedders** | Supported | Supported | **Pre-registered** |

**Decision:** bge-base-en-v1.5 offers the best balance of retrieval quality, model size, and out-of-the-box support in MLXEmbedders (`ModelConfiguration.bge_base`). It uses CLS pooling and a query instruction prefix for optimal retrieval.

### Why Lazy Download (not Bundled)

Neither the embedding model nor the local LLM is bundled with the app. Bundling them would:
- Bloat the app download from ~10 MB to ~2+ GB
- Force every user to download weights even if they never use those features
- Require app updates to change models

Instead, models are downloaded on demand with explicit user consent:

**Embedding model (bge-base-en-v1.5, ~438 MB):**
1. User installs Chunkpad -- small, fast download
2. User explores the UI, configures settings -- no model needed
3. User adds a folder → documents are parsed and chunked to disk -- no model needed
4. User reviews chunks, clicks "Embed Selected" -- embedding model downloads from HuggingFace
5. Cached locally in `~/.cache/` -- instant loads on subsequent launches
6. Chat uses the cached model for query embedding -- NEVER triggers a new download

**Llama 3.2 (~1.7 GB, for local text generation):**
1. User sends a chat message without a Claude or ChatGPT API key
2. App shows dialog: "Would you like to download Llama 3.2 for free local generation?"
3. User accepts -- Llama downloads from HuggingFace
4. Cached locally in `~/.cache/` -- used for all subsequent chats until a cloud key is added

**Decision:** Lazy downloads respect users' bandwidth and storage. The app is useful immediately, and each model is only fetched when actually needed with explicit user action.

### Why Flexible LLM (not Cloud-Only or Local-Only)

Users have different priorities:

| Priority | Best Option |
|---|---|
| Maximum privacy | Local (Ollama or bundled Llama 3.2) |
| Best quality | Cloud (Claude or ChatGPT) |
| Cost-sensitive | Local (free) |
| Speed-sensitive | Cloud (fast) or Local (no network) |
| Zero-config | Bundled Llama 3.2 (no external services) |

**Decision:** Let the user choose. The `GenerationMode` enum provides three user-facing options in Settings: Anthropic, OpenAI, and Ollama. Both cloud API keys can be configured upfront so users can switch freely without re-entering credentials. When no API key is configured, the app offers to download Llama 3.2 for free local generation. The architecture is pluggable -- adding new providers is a single `LLMClient` protocol conformance.

**Separation of concerns:** The embedding model (bge-base-en-v1.5 via MLXEmbedders) is NEVER used for text generation. All generative LLMs (Claude, ChatGPT, Ollama, Llama 3.2) are NEVER used for embeddings. These are completely separate models with separate download triggers and separate lifecycles.

### Why Two-Step Indexing (Process → Review → Embed)

The original design indexed documents in a single pass: select folder → parse → chunk → embed → store. We changed to a two-step pipeline:

| Step | What Happens | Model Needed? |
|---|---|---|
| **Step 1: Process** | Parse documents → chunk text → write markdown files to `_chunks/` | No |
| **Step 2: Embed** | User reviews chunks → clicks "Embed Selected" → download model → embed → store in DB | Yes |

**Why the split:**

1. **User control** -- Users can review, include/exclude, and edit chunk files before committing to the expensive embedding step. This is critical for quality: garbage chunks produce garbage retrieval.
2. **Fast iteration** -- Re-processing a folder (Step 1) takes seconds and requires no model download. Users can adjust chunk size/overlap in Settings and re-process to compare results before embedding.
3. **Edit-friendly** -- Chunk files are plain markdown on disk (`## Chunk 1`, `## Chunk 2`, ...). Users can open them in any text editor to fix extraction errors, add context, or split/merge chunks. The app detects modified chunk files and offers to re-embed.
4. **Deferred model download** -- The ~438 MB embedding model is only downloaded when the user explicitly clicks "Embed Selected", not when they first add a folder. This respects bandwidth and lets users explore the UI without triggering large downloads.

**Decision:** Two-step indexing gives users transparency and control over what goes into their knowledge base, at the cost of one extra click ("Embed Selected") compared to one-shot indexing.

### Why Chunks Inside the Selected Folder (not Sibling)

Chunk markdown files are stored at `{selectedFolder}/_chunks/` (inside the user-selected folder), not at `{selectedFolder}_chunks/` (a sibling folder alongside it).

**Why:** macOS App Sandbox grants security-scoped access only to the folder the user selects in `NSOpenPanel`. Writing to a sibling folder (e.g. `Documents/RAG Docs_chunks/` when the user selected `Documents/RAG Docs/`) requires access to the parent directory, which the sandbox does not grant. Storing chunks inside the selected folder stays within the granted access scope.

**Entitlement:** The app uses `com.apple.security.files.user-selected.read-write` (not read-only) because it must create the `_chunks/` subdirectory and write markdown files into it.

**Important:** `DocumentProcessor.processDirectory` explicitly skips `_chunks/` directories during file enumeration to avoid re-processing chunk markdown files as documents.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  User's Documents                                               │
│  ~/Documents/proposals/, ~/Downloads/reports/, etc.             │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  User clicks "Add Folder" (Step 1: Process)
┌─────────────────────────────────────────────────────────────────┐
│  DocumentProcessor (Swift, async)                               │
│  ├─ PDFKit         → .pdf                                       │
│  ├─ textutil CLI   → .docx, .rtf, .doc, .odt                   │
│  └─ String(contentsOf:)          → .txt, .md, .markdown        │
│                                                                 │
│  Output: [ProcessedChunk] with title, content, metadata         │
│  Chunking: configurable (default ~1000 tokens, ~100 overlap)   │
│  Skips: _chunks/ directories during enumeration                 │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  Chunk markdown files written to disk
┌─────────────────────────────────────────────────────────────────┐
│  ChunkFileService (struct, synchronous)                         │
│                                                                 │
│  Writes: {selectedFolder}/_chunks/{relative-path}.md            │
│  Format: ## Chunk 1\ncontent...\n\n## Chunk 2\n...              │
│  Reads:  Parses .md files back into [ProcessedChunk]            │
│  Discovery: Recursively finds all .md files in _chunks/         │
│                                                                 │
│  ChunkFileTree:  Tree structure for sidebar display             │
│  ReviewableChunk: Chunk + include/exclude toggle for embedding  │
│  IndexedFolder:  Persisted rootURL + chunksRootURL pair         │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  User reviews chunks, clicks "Embed Selected" (Step 2)
                  ↓  First time? Download embedding model (~438 MB)
┌─────────────────────────────────────────────────────────────────┐
│  EmbeddingService (actor, MLX Swift)                            │
│                                                                 │
│  Model: BAAI/bge-base-en-v1.5                                   │
│  ├─ Architecture: BERT (12 layers, 12 heads, 768 hidden)       │
│  ├─ Tokenizer: BERT WordPiece                                   │
│  ├─ Pooling: CLS token (from 1_Pooling/config.json)            │
│  ├─ Normalization: L2                                           │
│  └─ Output: 768-dimensional float32 vector                     │
│                                                                 │
│  Status: .notDownloaded → .downloading(%) → .loading → .ready  │
│  Cache: ~/.cache/ (local, persistent)                            │
│                                                                 │
│  embed(text)      → document embedding (no prefix)              │
│  embedQuery(text) → query embedding (with BGE instruction)      │
│                                                                 │
│  BGE query prefix:                                              │
│  "Represent this sentence for searching relevant passages: "    │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  768-dim float32 vectors
┌─────────────────────────────────────────────────────────────────┐
│  DatabaseService (actor, system SQLite3 C API)                  │
│                                                                 │
│  Database: ~/Library/Application Support/Chunkpad/chunkpad.db   │
│  Mode: WAL (Write-Ahead Logging)                                │
│                                                                 │
│  Tables:                                                        │
│  ├─ documents          Regular table (metadata: name, path, type)│
│  ├─ chunks             Regular table (content, title, metadata)  │
│  ├─ vec_chunks         vec0 virtual table (float[768] cosine)    │
│  ├─ chunks_fts         FTS5 virtual table (full-text search)     │
│  ├─ indexed_folders    Regular table (folder paths, counts)      │
│  ├─ embedded_chunk_refs Regular table (embed tracking)           │
│  └─ schema_version     Migration version tracking                │
│                                                                 │
│  sqlite-vec: Vendored C source, compiled with SQLITE_CORE,     │
│              linked against system libsqlite3                   │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  User asks a question in Chat
┌─────────────────────────────────────────────────────────────────┐
│  ChatViewModel (RAG Pipeline)                                   │
│                                                                 │
│  1. embedQuery(question)  → 768-dim query vector (with prefix)  │
│  2. hybridSearch()        → vec_chunks KNN (70% weight)         │
│                             + chunks_fts MATCH (30% weight)     │
│                             + minScore filter (default 0.1)     │
│                             → Top 10 ScoredChunks               │
│  2b. addPinnedChunks()    → Merge pinned doc chunks (score 1.0) │
│  3. UI: show chunks bar   → Relevance %, toggle on/off          │
│  4. buildContext()        → Only isIncluded chunks + question    │
│  5. LLM stream            → Selected provider streams answer    │
│  6. (opt) Regenerate      → Re-run steps 4-5 with new selection │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  Query + retrieved chunks
┌─────────────────────────────────────────────────────────────────┐
│  LLM Service (User's Choice)                                    │
│                                                                 │
│  ┌─── Cloud ──────────────────────────────────────────────┐     │
│  │  AnthropicClient  → Claude (streaming via SSE)         │     │
│  │  OpenAIClient     → ChatGPT (streaming via SSE)         │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
│  ┌─── Local ──────────────────────────────────────────────┐     │
│  │  OllamaClient     → Ollama HTTP API (streaming)        │     │
│  │  BundledLLMClient  → Llama 3.2 via MLX (streaming)     │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
│  Protocol: LLMClient { chat(), chatStream() }                   │
│  Factory:  LLMServiceFactory.client(for: LLMProvider)           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Indexing Pipeline (Two-Step)

**Step 1: Process (no model download, no DB writes)**

```
User clicks "Add Folder"
    → NSOpenPanel (directories only, single selection)
    → IndexingViewModel.selectAndProcessFolder()
        → DocumentProcessor.processDirectory(at: url)
            → Enumerate files (skips _chunks/ directories)
            → For each supported file: parse → chunk
            → Chunk size/overlap from AppState (configurable in Settings)
            → Returns [URL: [ProcessedChunk]]
        → ChunkFileService.writeChunks() for each file
            → Creates {selectedFolder}/_chunks/ directory
            → Writes one .md file per source file
            → Format: ## Chunk 1\ncontent\n\n## Chunk 2\n...
        → ChunkFileService.discoverChunkFiles() → [ChunkFileInfo]
        → ChunkFileTree(chunkFiles:chunksRootURL:) → tree for sidebar
        → IndexedFolder persisted to DB (rootURL + chunksRootURL)
```

**Step 2: Embed (user reviews, then commits)**

```
User reviews chunks in tree sidebar
    → Toggles include/exclude per chunk
    → Optionally edits .md files externally (app detects modifications)
    → Clicks "Embed Selected"
    → IndexingViewModel.embedApprovedChunks()
        → EmbeddingService.ensureModelReady()
            → First time: download bge-base-en-v1.5 (~438 MB)
            → Subsequent: load from local cache (instant)
        → For each included chunk:
            → EmbeddingService.embed(chunk.content)     // no query prefix
            → DatabaseService.insertChunk(chunk, embedding)
                → INSERT into chunks (text)
                → INSERT into vec_chunks (float[768] vector)
                → FTS5 trigger auto-syncs chunks_fts
        → embeddedChunkIDs updated and persisted to DB (embedded_chunk_refs)
        → AppState.indexedDocumentCount updated
```

### Search Pipeline (RAG)

```
User sends message
    → ChatViewModel.sendMessage(text, provider)
        → EmbeddingService.ensureModelReady()           // load from cache (never downloads)
        → EmbeddingService.embedQuery(text)             // WITH BGE prefix
        → DatabaseService.hybridSearch(embedding, text, k=10, minScore=0.1)
            → vec_chunks KNN: SELECT ... ORDER BY distance LIMIT k
            → chunks_fts:    SELECT ... WHERE chunks_fts MATCH query
            → Merge: 0.7 * vector_score + 0.3 * fts_score
            → Filter: discard chunks with combined score < minScore (0.1)
            → Return top k ScoredChunks (chunk + relevanceScore)
        → addPinnedChunks()                             // merge pinned doc chunks at score 1.0
        → UI: chunks bar shows each chunk with relevance % and toggle
        → buildContext(scoredChunks, query)              // only isIncluded chunks
        → LLMServiceFactory.client(for: provider)
        → client.chatStream(messages)                   // stream tokens
        → UI updates incrementally as tokens arrive

User toggles chunks on/off → taps Regenerate
    → ChatViewModel.regenerate(provider)
        → buildContext(scoredChunks, query)              // re-reads isIncluded flags
        → client.chatStream(messages)                   // new generation with updated context
```

#### ScoredChunk Model

```swift
struct ScoredChunk: Identifiable, Sendable {
    let chunk: Chunk
    let relevanceScore: Double  // 0.0 – 1.0
    var isIncluded: Bool = true // user toggle
}
```

`Chunk` stays clean for database storage; `ScoredChunk` wraps it with search metadata for the chat UI.

---

## Embedding Model Lifecycle

The embedding model follows a strict state machine:

```
┌───────────────┐     ensureModelReady()     ┌──────────────────┐
│ .notDownloaded │ ─────────────────────────→ │ .downloading(0%) │
└───────────────┘                            └────────┬─────────┘
                                                      │ Download
                                                      │ progress
                                                      ↓
                                             ┌──────────────────┐
                                             │ .downloading(N%) │
                                             └────────┬─────────┘
                                                      │ 100%
                                                      ↓
                                             ┌──────────────────┐
                                             │    .loading       │ ← weights into MLX
                                             └────────┬─────────┘
                                                      │
                                                      ↓
                                             ┌──────────────────┐
                                             │     .ready        │ ← embed() works
                                             └──────────────────┘

On error at any stage → .error(message)
Subsequent calls to ensureModelReady() when .ready → instant no-op
```

**Key behaviors:**
- Model is never downloaded at app install or app launch
- Download triggers ONLY when the user clicks "Embed Selected" in the Documents view (`IndexingViewModel.embedApprovedChunks()`). Processing a folder (Step 1) does NOT download the model.
- `ChatViewModel` NEVER triggers a download — it only loads the model from local cache after checking `indexedDocumentCount > 0`
- After download, model weights are cached locally in `~/.cache/` and persist across app launches
- The `AppState.embeddingModelStatus` property is updated globally so the Settings view always reflects the current state
- The embedding model is NEVER used for text generation — only for creating vector embeddings for search

---

## Technology Stack

| Layer | Technology | Why |
|---|---|---|
| **Language** | Swift 6.2 | Native macOS, modern concurrency |
| **UI Framework** | SwiftUI (macOS 26) | Liquid Glass, declarative |
| **Concurrency** | Swift Concurrency (async/await, actors) | Safe, structured |
| **State** | @Observable + @MainActor | SwiftUI best practices |
| **Database** | System SQLite3 (C API) | Ships with macOS, no dependencies |
| **Vector Search** | sqlite-vec (vendored) | KNN with cosine distance |
| **Full-Text Search** | FTS5 | Built into system SQLite on macOS |
| **Embeddings** | MLXEmbedders (mlx-swift-lm) | On-device BERT on Apple Silicon |
| **Embedding Model** | BAAI/bge-base-en-v1.5 | High-quality RAG embeddings |
| **Cloud LLMs** | URLSession + SSE streaming | No SDK dependencies |
| **Local LLMs** | Ollama HTTP API + MLXLLM (Llama 3.2) | Ollama user-installed; Llama downloaded on demand via MLX |
| **PDF Parsing** | PDFKit | System framework |
| **Rich Text** | textutil CLI | macOS built-in (DOCX/RTF/DOC/ODT) |
| **Chunk Files** | ChunkFileService | Markdown files on disk for review/edit |
| **Build (CLI)** | Swift Package Manager | swift build |
| **Build (Xcode)** | XcodeGen → .xcodeproj | project.yml → xcodegen generate |

---

## Database Schema

```sql
-- Document metadata
CREATE TABLE documents (
    id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    document_type TEXT NOT NULL,
    chunk_count INTEGER DEFAULT 0,
    file_size INTEGER DEFAULT 0,
    indexed_at TEXT DEFAULT (datetime('now'))
);

-- Text chunks with metadata
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    document_type TEXT,
    slide_number INTEGER,
    source_path TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Vector index (sqlite-vec virtual table)
CREATE VIRTUAL TABLE vec_chunks USING vec0(
    chunk_id TEXT PRIMARY KEY,
    embedding float[768] distance_metric=cosine,
    document_type TEXT,
    +title TEXT,
    +source_path TEXT
);

-- Full-text search index (content-sync with chunks table)
CREATE VIRTUAL TABLE chunks_fts USING fts5(
    title,
    content,
    content='chunks',
    content_rowid='rowid'
);

-- Auto-sync FTS with chunks table
CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
    INSERT INTO chunks_fts(rowid, title, content)
    VALUES (new.rowid, new.title, new.content);
END;

-- Indexed folders (persisted folder paths and counts)
CREATE TABLE indexed_folders (
    id TEXT PRIMARY KEY,
    root_path TEXT NOT NULL UNIQUE,
    chunks_root_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_processed_at TEXT,
    file_count INTEGER DEFAULT 0,
    chunk_count INTEGER DEFAULT 0
);

-- Embedded chunk tracking (which chunks have been embedded)
CREATE TABLE embedded_chunk_refs (
    chunk_ref_id TEXT PRIMARY KEY,
    chunk_id TEXT,
    embedded_at TEXT NOT NULL
);

-- Schema migration version tracking
CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY
);
```

---

## LLM Provider Configuration

```swift
// The user picks a GenerationMode in Settings UI:
enum GenerationMode: String, CaseIterable {
    case anthropic  // Cloud: Claude API (bring your own key)
    case openai     // Cloud: OpenAI API (bring your own key)
    case ollama     // Local: Ollama HTTP API
    // Llama 3.2 is NOT in GenerationMode — it's offered automatically
    // when the user tries to chat without a cloud API key.
}

// Resolved to a concrete provider with config:
enum LLMProvider {
    case cloud(CloudConfig)    // provider + API key + model
    case local(LocalConfig)    // provider + endpoint + model + context size
}

// Both API keys are always configurable in Settings.
// When no key is set, ChatView offers to download Llama 3.2.
// Llama uses BundledLLMService (singleton) via BundledLLMClient.
```

Cloud providers use streaming Server-Sent Events (SSE) via `URLSession`. Local providers use Ollama's streaming JSON API. All conform to the `LLMClient` protocol:

```swift
protocol LLMClient {
    func chat(messages: [ChatMessage]) async throws -> String
    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}
```

---

## Security & Privacy

| Concern | How It's Handled |
|---|---|
| **Document storage** | Documents are read from disk, never copied. Only chunks are stored in SQLite. |
| **Embeddings** | Generated 100% on-device via MLX. Never sent to any server. |
| **Vector search** | Runs locally in SQLite. No network calls. |
| **Cloud LLM** | Only the user's question + small text chunks are sent. Full documents are never sent. User explicitly opts in. |
| **Local LLM** | Everything stays on-device. Zero network traffic. |
| **API keys** | Stored in macOS Keychain via `KeychainHelper` (service: "Chunkpad"). |
| **Chunk files** | Markdown files written to `_chunks/` inside the user-selected folder. Editable by the user. |
| **App Sandbox** | Enabled. Network client access + user-selected file read-write (needed for `_chunks/` output). |
| **Model download** | HTTPS download, cached locally in `~/.cache/`. |

---

## Performance Expectations

### Embedding Model

| Operation | Time | Notes |
|---|---|---|
| First download | 1-5 min | ~438 MB download (one-time) |
| Model load (cached) | 2-5s | Loading weights into MLX |
| Single embed | ~10-30ms | One chunk on M-series GPU |
| Batch of 100 | ~1-3s | Sequential, memory-bounded |

### Database

| Catalog Size | Vector Search | Hybrid Search | Notes |
|---|---|---|---|
| 100 chunks | <10ms | <15ms | Tiny |
| 1,000 chunks | ~15ms | ~25ms | Typical |
| 10,000 chunks | ~30ms | ~50ms | Large |
| 100,000 chunks | ~80ms | ~120ms | Very large |

### End-to-End Chat

| LLM Choice | Search | Generation | Total |
|---|---|---|---|
| Local (Ollama Llama 3.3) | ~25ms | ~2-5s | ~2-5s |
| Local (Bundled Llama 3.2) | ~25ms | ~3-8s | ~3-8s |
| Cloud (Claude) | ~25ms | ~500ms-2s | ~1-3s |
| Cloud (ChatGPT) | ~25ms | ~1-3s | ~1-4s |

---

## Chunk File Format

Chunk files are plain markdown stored at `{selectedFolder}/_chunks/`, mirroring the source folder structure. Each source file produces one `.md` file:

```
Selected Folder/
├── report.pdf
├── notes.txt
├── subdir/
│   └── memo.docx
└── _chunks/                    ← created by Chunkpad
    ├── report.pdf.md
    ├── notes.txt.md
    └── subdir/
        └── memo.docx.md
```

Each chunk file contains sections delimited by `## Chunk N` headers:

```markdown
## Chunk 1
First chunk content here...

## Chunk 2
Second chunk content here...
```

**Key properties:**
- **Editable** -- Users can open chunk files in any text editor to fix extraction errors, add context, or split/merge chunks. The app detects modifications via file modification dates and prompts "Re-embed".
- **Deterministic structure** -- `ChunkFileService.readChunkFile()` uses a regex to parse `## Chunk N` sections back into `ProcessedChunk` values.
- **Source path inference** -- `_chunks/subdir/memo.docx.md` is inferred back to `subdir/memo.docx` relative to the root folder.

### Related Types

| Type | Role |
|---|---|
| `ChunkFileService` | Reads/writes chunk markdown files, discovers files in `_chunks/` |
| `ChunkFileInfo` | One discovered chunk file: URL, source path, parsed chunks, modification date |
| `ChunkFileTree` | Tree structure built from `[ChunkFileInfo]` for the sidebar `OutlineGroup` |
| `ChunkFolderNode` / `ChunkFileNode` | Tree nodes (folders and files) |
| `ReviewableChunk` | Chunk + stable ID + `isIncluded` toggle for selective embedding |
| `IndexedFolder` | Persisted pair of `rootURL` + `chunksRootURL` (stored in main DB) |

---

## Persistence Contract

| Storage | Contents | Notes |
|--------|----------|-------|
| Main SQLite (chunkpad.db) | documents, chunks, vec_chunks, chunks_fts, indexed_folders, embedded_chunk_refs, schema_version | Source of truth for indexing |
| Chat SQLite (chunkpad_chat.db) | conversations, messages | Chat history only |
| UserDefaults | generation mode, model selections, chunk size/overlap | User preferences only |
| Keychain | API keys | Via KeychainHelper |
| Filesystem | {folder}/_chunks/*.md | Editable chunk files before embedding |
| In-memory | ViewModels, model containers | Session-only |

**Do not:**
- Store document metadata or indexed folder paths in UserDefaults — use the main DB
- Store API keys in UserDefaults — use Keychain via `KeychainHelper`
- Store embedded chunk IDs in UserDefaults — use `embedded_chunk_refs` table

---

## Future Work

- **Incremental indexing** -- Detect changed source files and re-process only those (currently re-processes all)
- **Model selection** -- Let users pick from multiple embedding models (bge-small for speed, bge-large for quality)
- **Export/import** -- Export the SQLite database for backup or sharing
- **Multi-language** -- Switch to bge-m3 for multilingual document support
- **Chunk file editing UI** -- In-app chunk editor instead of requiring external text editor
