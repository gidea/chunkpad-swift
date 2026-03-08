# Chunkpad

**A native macOS app for local document search and AI-assisted Q&A, built with Swift and SwiftUI.**

Chunkpad indexes your local documents (PDF, DOCX, TXT, Markdown, RTF), generates semantic embeddings on-device using Apple Silicon, stores them in an embedded SQLite database with vector search, and lets you query your knowledge base using the LLM of your choice -- cloud or local.

---

## Key Features

- **100% local indexing** -- Documents are chunked and embedded on your Mac. Nothing leaves your machine during indexing.
- **On-device embeddings** -- Uses [BAAI/bge-large-en-v1.5](https://huggingface.co/BAAI/bge-large-en-v1.5) via MLX Swift on Apple Silicon. No external API calls.
- **Embedded database** -- SQLite + [sqlite-vec](https://github.com/asg017/sqlite-vec) for vector search + FTS5 for keyword search. No server to install.
- **Hybrid search** -- Combines vector similarity (70%) and full-text matching (30%) with a relevance threshold. Irrelevant chunks are automatically filtered out.
- **Transparent retrieval** -- Retrieved chunks are shown with relevance scores. Toggle individual chunks on/off and regenerate with your selection. Pin documents to always include them in context.
- **Flexible LLM** -- Choose between cloud providers (Claude, ChatGPT) or the bundled Llama 3.2 running on-device via MLX. Both cloud API keys can be configured upfront. If no API key is set, the app offers to download Llama 3.2 for free local generation.
- **Liquid Glass UI** -- macOS 26 native design language with `.glassEffect()` throughout. Design values are centralized in `GlassTokens` for accessibility control, since Liquid Glass has known legibility and contrast issues in its initial release.
- **Lazy model downloads** -- Neither the embedding model (~1.3 GB) nor the local LLM (~1.7 GB) is bundled with the app. The embedding model downloads only when you index documents. Llama 3.2 downloads only if you accept the offer. Cached locally for instant loads afterwards.

---

## Requirements

- **macOS 26** (Tahoe) or later
- **Apple Silicon** (M1/M2/M3/M4) -- required for MLX
- **Xcode 26** with **Metal Developer Tools 26** installed (Xcode will prompt you, or install via Xcode > Settings > Components)
- **Internet connection** -- only for first-time embedding model download and cloud LLM usage

---

## Build

### Command Line (Swift Package Manager)

```bash
swift build
```

### Xcode

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. Generate the Xcode project: `xcodegen generate`
3. Open `Chunkpad.xcodeproj`
4. Build and run (Cmd+R)

Both build systems (`Package.swift` and `project.yml`) are kept in sync.

---

## Project Structure

```
chunkpad-swift/
├── Chunkpad/
│   ├── App/
│   │   ├── ChunkpadApp.swift          # App entry point
│   │   └── AppState.swift             # Global observable state
│   ├── Models/
│   │   ├── Chunk.swift                # Document chunk model
│   │   ├── ChunkFileTree.swift        # Chunk embedding status + file tree for review
│   │   ├── IndexedDocument.swift      # Indexed document metadata
│   │   ├── IndexedFolder.swift        # Indexed folder & chunk file info
│   │   ├── LLMProvider.swift          # LLM provider enums & configs
│   │   ├── Message.swift              # Chat message model
│   │   ├── ScoredChunk.swift          # Chunk + relevance score + include toggle
│   │   ├── ChunkFeedback.swift        # Chunk feedback signal model (boost/hide)
│   │   └── Collection.swift           # Document collection model
│   ├── Services/
│   │   ├── AnthropicClient.swift      # Anthropic Claude API client
│   │   ├── BookmarkService.swift      # Security-scoped bookmark persistence
│   │   ├── BundledLLMService.swift    # Llama 3.2 local generation via MLXLLM
│   │   ├── ChunkFileService.swift     # Chunk markdown file I/O
│   │   ├── ConversationDatabaseService.swift # Chat conversation SQLite DB
│   │   ├── DatabaseService.swift      # SQLite + sqlite-vec + FTS5
│   │   ├── DocumentProcessor.swift    # PDF/DOCX/TXT/MD/RTF parsing & chunking
│   │   ├── EmbeddingService.swift     # MLX embedding (bge-large-en-v1.5)
│   │   ├── KeychainHelper.swift       # Keychain storage for API keys
│   │   ├── LLMService.swift           # LLM client protocol & factory
│   │   └── OpenAIClient.swift         # OpenAI API client
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift        # RAG pipeline orchestration
│   │   └── IndexingViewModel.swift    # Document indexing orchestration
│   ├── Utilities/
│   │   └── Color+Hex.swift            # Color(hex:) initializer for CSS hex colors
│   ├── Views/
│   │   ├── MainView.swift             # Root NavigationSplitView
│   │   ├── Chat/
│   │   │   ├── ChatView.swift         # Chat orchestration (toolbar, dialogs, bottom bar)
│   │   │   ├── ChatMessagesView.swift # Messages scroll area with auto-scroll
│   │   │   ├── ChatInputBar.swift     # Input field, pin button, search preview, send
│   │   │   ├── ChunksBarView.swift    # Collapsible retrieved chunks bar + regenerate
│   │   │   ├── SearchPanelView.swift  # Pre-send search results panel (Cmd+K)
│   │   │   ├── MessageBubble.swift    # Message display
│   │   │   ├── ChunkPreview.swift     # Chunk preview with score & toggle
│   │   │   └── PinDocumentsSheet.swift # Pin documents to always include
│   │   ├── Documents/
│   │   │   ├── DocumentsView.swift    # Document management orchestration
│   │   │   ├── CollectionsSectionView.swift  # Collection sidebar with CRUD
│   │   │   ├── ChunkTreeSidebarView.swift   # Chunk file tree outline
│   │   │   ├── ChunkListView.swift    # Chunk list/grid with filter bar
│   │   │   ├── DocumentBannersView.swift    # Error, skipped file, inaccessible banners
│   │   │   ├── FeedbackManagementView.swift # Chunk feedback management & analytics
│   │   │   └── IndexingProgressView.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift     # Settings orchestration (smaller sections inline)
│   │   │   ├── DatabaseSettingsSection.swift     # DB status, stats, clear data
│   │   │   ├── EmbeddingsSettingsSection.swift   # Embedding model info & status
│   │   │   ├── LlamaSettingsSection.swift        # Bundled Llama download/unload
│   │   │   └── GenerationSettingsSection.swift   # Provider picker, API keys, validation
│   │   └── Components/
│   │       ├── ChunkStatusBadge.swift # Embedding status indicator (colored icon + label)
│   │       ├── GlassCard.swift        # Reusable Liquid Glass card
│   │       ├── GlassIconButton.swift  # Circular glass icon button
│   │       ├── GlassPill.swift        # Capsule-shaped glass tag/label
│   │       └── GlassTokens.swift      # Centralized design tokens (radii, spacing, padding)
│   └── Resources/
│       ├── Info.plist
│       ├── Chunkpad.entitlements
│       └── Assets.xcassets/
├── Vendor/
│   └── CSQLiteVec/                    # sqlite-vec C extension (compiled in)
│       ├── sqlite-vec.c
│       ├── include/
│       │   ├── sqlite-vec.h
│       │   └── module.modulemap
├── Package.swift                      # SPM manifest (for swift build)
├── project.yml                        # XcodeGen spec (for Xcode)
└── .gitignore
```

---

## Architecture Overview

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical architecture.

**TL;DR pipeline:**

```
Documents → DocumentProcessor → Chunks
                                  ↓
                    EmbeddingService (MLX, bge-large-en-v1.5)
                                  ↓
                    DatabaseService (SQLite + sqlite-vec + FTS5)
                                  ↓
            User Query → embedQuery() → Hybrid Search → Top Chunks
                                                           ↓
                                              LLM (cloud or local) → Answer
```

---

## Dependencies

| Dependency | Purpose | Source |
|---|---|---|
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MLXEmbedders (embeddings) + MLXLLM (Llama generation) | SPM |
| [sqlite-vec](https://github.com/asg017/sqlite-vec) | Vector search extension for SQLite | Vendored C source |
| System SQLite3 | Database engine (ships with macOS) | macOS SDK |

No other third-party dependencies. LLM clients use `URLSession` directly.

---

## Configuration

### Embedding Model

- **Model:** BAAI/bge-large-en-v1.5 (1024 dimensions, BERT-based)
- **Purpose:** Creates vector embeddings for document search. NEVER used for text generation.
- **Download:** From HuggingFace, only when you index documents (~1.3 GB). Never from chat.
- **Cache:** `~/.cache/` (cached locally after first download)
- **Privacy:** 100% on-device inference via MLX on Apple Silicon

### LLM Providers (Text Generation)

| Mode | Provider | Setup |
|---|---|---|
| Anthropic | Claude API | Enter API key in Settings |
| OpenAI | ChatGPT API | Enter API key in Settings |
| Llama 3.2 (On-Device) | Bundled via MLX | Accept download offer (~1.7 GB), runs on Apple Silicon |

Both cloud API keys can be configured simultaneously in Settings, so you can switch between Claude and ChatGPT without re-entering credentials. If no API key is set, the app offers to download Llama 3.2 for free local generation.

### Database

- **Location:** `~/Library/Application Support/Chunkpad/chunkpad.db`
- **Engine:** SQLite 3 with WAL mode
- **Extensions:** sqlite-vec (vector search), FTS5 (full-text search)

---

## License

TBD
