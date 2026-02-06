# Chunkpad Architecture

**Local-First RAG on Apple Silicon**

Date: February 6, 2026
Status: **CURRENT ARCHITECTURE**

---

## Executive Summary

Chunkpad is a native macOS app that turns your local documents into a searchable, AI-queryable knowledge base. The core design principles:

- **Embedded database** -- SQLite + sqlite-vec. No external servers, no Docker, no PostgreSQL. The database is a single file.
- **On-device embeddings** -- MLX Swift running BAAI/bge-base-en-v1.5 on Apple Silicon. Documents never leave your Mac during indexing.
- **Lazy model download** -- The embedding model is not bundled with the app. It's downloaded from HuggingFace only when the user first indexes documents or searches. If you just want the UI, no download happens.
- **Flexible generation** -- User chooses between cloud LLMs (Anthropic Claude, OpenAI GPT-4) and local LLMs (Ollama, planned bundled llama.cpp). User is always in control.
- **Liquid Glass UI** -- macOS 26 native design with `.glassEffect()` throughout.

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

The embedding model is ~438 MB. Bundling it would:
- Bloat the app download from ~10 MB to ~450+ MB
- Force every user to download model weights even if they never index documents
- Require app updates to change the model

Instead, the model is downloaded on demand:
1. User installs Chunkpad -- small, fast download
2. User explores the UI, configures settings -- no model needed
3. User clicks "Index Folder" or sends first chat -- model downloads from HuggingFace
4. Cached in `~/.cache/huggingface/hub/` -- instant loads on subsequent launches

**Decision:** Lazy download respects users' bandwidth and storage. The app is useful immediately, and the model is only fetched when actually needed.

### Why Flexible LLM (not Cloud-Only or Local-Only)

Users have different priorities:

| Priority | Best Option |
|---|---|
| Maximum privacy | Local (Ollama or bundled llama.cpp) |
| Best quality | Cloud (Claude or GPT-4) |
| Cost-sensitive | Local (free) |
| Speed-sensitive | Cloud (fast) or Local (no network) |

**Decision:** Let the user choose. The `GenerationMode` enum provides four options: Anthropic, OpenAI, Ollama, and Bundled. The architecture is pluggable -- adding new providers is a single `LLMClient` protocol conformance.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  User's Documents                                               │
│  ~/Documents/proposals/, ~/Downloads/reports/, etc.             │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  User clicks "Index Folder"
┌─────────────────────────────────────────────────────────────────┐
│  DocumentProcessor (Swift, synchronous)                         │
│  ├─ PDFKit         → .pdf                                       │
│  ├─ NSAttributedString (textutil) → .docx, .rtf, .pptx, .doc  │
│  └─ String(contentsOf:)          → .txt, .md, .markdown        │
│                                                                 │
│  Output: [ProcessedChunk] with title, content, metadata         │
│  Chunking: ~500 words per chunk, 50-word overlap                │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  First time? Download model from HuggingFace
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
│  Cache: ~/.cache/huggingface/hub/                               │
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
│  ├─ documents        Regular table (metadata: name, path, type) │
│  ├─ chunks           Regular table (content, title, metadata)   │
│  ├─ vec_chunks       vec0 virtual table (float[768] cosine)     │
│  ├─ chunks_fts       FTS5 virtual table (full-text search)      │
│  └─ messages         Regular table (chat history)               │
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
│                             → Top 10 chunks                     │
│  3. buildContext()        → System prompt + chunks + question    │
│  4. LLM stream            → Selected provider streams answer    │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  ↓  Query + retrieved chunks
┌─────────────────────────────────────────────────────────────────┐
│  LLM Service (User's Choice)                                    │
│                                                                 │
│  ┌─── Cloud ──────────────────────────────────────────────┐     │
│  │  AnthropicClient  → Claude (streaming via SSE)         │     │
│  │  OpenAIClient     → GPT-4 (streaming via SSE)          │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
│  ┌─── Local ──────────────────────────────────────────────┐     │
│  │  OllamaClient     → Ollama HTTP API (streaming)        │     │
│  │  (Planned)        → Bundled llama.cpp                   │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
│  Protocol: LLMClient { chat(), chatStream() }                   │
│  Factory:  LLMServiceFactory.client(for: LLMProvider)           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Indexing Pipeline

```
User selects folder
    → IndexingViewModel.selectAndIndexFolder()
        → EmbeddingService.ensureModelReady()
            → First time: download bge-base-en-v1.5 from HuggingFace (~438 MB)
            → Subsequent: load from ~/.cache/huggingface/hub/ (instant)
        → DocumentProcessor.processDirectory(at: url)
            → For each file: parse → chunk (500 words, 50 overlap)
            → Returns [URL: [ProcessedChunk]]
        → For each file:
            → DatabaseService.insertDocument(metadata)
            → For each chunk:
                → EmbeddingService.embed(chunk.content)     // no query prefix
                → DatabaseService.insertChunk(chunk, embedding)
                    → INSERT into chunks (text)
                    → INSERT into vec_chunks (float[768] vector)
                    → FTS5 trigger auto-syncs chunks_fts
```

### Search Pipeline (RAG)

```
User sends message
    → ChatViewModel.sendMessage(text, provider)
        → EmbeddingService.ensureModelReady()           // download if needed
        → EmbeddingService.embedQuery(text)             // WITH BGE prefix
        → DatabaseService.hybridSearch(embedding, text, k=10)
            → vec_chunks KNN: SELECT ... ORDER BY distance LIMIT k
            → chunks_fts:    SELECT ... WHERE chunks_fts MATCH query
            → Merge: 0.7 * vector_score + 0.3 * fts_score
            → Return top k chunks
        → buildContext(chunks, query)                   // system prompt + chunks + question
        → LLMServiceFactory.client(for: provider)
        → client.chatStream(messages)                   // stream tokens
        → UI updates incrementally as tokens arrive
```

---

## Embedding Model Lifecycle

The embedding model follows a strict state machine:

```
┌───────────────┐     ensureModelReady()     ┌──────────────────┐
│ .notDownloaded │ ─────────────────────────→ │ .downloading(0%) │
└───────────────┘                            └────────┬─────────┘
                                                      │ HuggingFace
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
- Download triggers only on `IndexingViewModel.indexFolder()` or `ChatViewModel.sendMessage()`
- After download, files are cached in `~/.cache/huggingface/hub/` and persist across app launches
- The `AppState.embeddingModelStatus` property is updated globally so the Settings view always reflects the current state

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
| **Local LLMs** | Ollama HTTP API | User installs separately |
| **PDF Parsing** | PDFKit | System framework |
| **Rich Text** | NSAttributedString | textutil-backed (DOCX/RTF/PPTX) |
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

-- Full-text search index
CREATE VIRTUAL TABLE chunks_fts USING fts5(
    chunk_id UNINDEXED,
    title,
    content
);

-- Auto-sync FTS with chunks table
CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
    INSERT INTO chunks_fts(chunk_id, title, content)
    VALUES (new.id, new.title, new.content);
END;

-- Chat history
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    referenced_chunk_ids TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);
```

---

## LLM Provider Configuration

```swift
// The user picks a GenerationMode in Settings/Chat UI:
enum GenerationMode: String, CaseIterable {
    case anthropic  // Cloud: Claude API (bring your own key)
    case openai     // Cloud: OpenAI API (bring your own key)
    case ollama     // Local: Ollama HTTP API
    case bundled    // Local: Bundled llama.cpp (planned)
}

// Resolved to a concrete provider with config:
enum LLMProvider {
    case cloud(CloudConfig)    // provider + API key + model
    case local(LocalConfig)    // provider + endpoint + model + context size
}
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
| **API keys** | Stored in app state (future: macOS Keychain). |
| **App Sandbox** | Enabled. Network client access + user-selected file read-only. |
| **Model download** | HTTPS from HuggingFace. Cached locally. |

---

## Performance Expectations

### Embedding Model

| Operation | Time | Notes |
|---|---|---|
| First download | 1-5 min | ~438 MB from HuggingFace (one-time) |
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
| Cloud (Claude) | ~25ms | ~500ms-2s | ~1-3s |
| Cloud (GPT-4) | ~25ms | ~1-3s | ~1-4s |

---

## Future Work

- **Bundled llama.cpp** -- Run a small LLM directly in-process for offline generation (no Ollama needed)
- **Incremental indexing** -- Detect changed files and re-index only those
- **Model selection** -- Let users pick from multiple embedding models (bge-small for speed, bge-large for quality)
- **Keychain storage** -- Store API keys in macOS Keychain instead of UserDefaults
- **Export/import** -- Export the SQLite database for backup or sharing
- **Multi-language** -- Switch to bge-m3 for multilingual document support
