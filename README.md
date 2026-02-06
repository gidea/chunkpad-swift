# Chunkpad

**A native macOS app for local document search and AI-assisted Q&A, built with Swift and SwiftUI.**

Chunkpad indexes your local documents (PDF, DOCX, TXT, Markdown, PPTX, RTF), generates semantic embeddings on-device using Apple Silicon, stores them in an embedded SQLite database with vector search, and lets you query your knowledge base using the LLM of your choice -- cloud or local.

---

## Key Features

- **100% local indexing** -- Documents are chunked and embedded on your Mac. Nothing leaves your machine during indexing.
- **On-device embeddings** -- Uses [BAAI/bge-base-en-v1.5](https://huggingface.co/BAAI/bge-base-en-v1.5) via MLX Swift on Apple Silicon. No external API calls.
- **Embedded database** -- SQLite + [sqlite-vec](https://github.com/asg017/sqlite-vec) for vector search + FTS5 for keyword search. No server to install.
- **Hybrid search** -- Combines vector similarity (70%) and full-text matching (30%) for high-quality retrieval.
- **Flexible LLM** -- Choose between cloud providers (Anthropic Claude, OpenAI GPT-4) or local models (Ollama, planned bundled llama.cpp).
- **Liquid Glass UI** -- macOS 26 native design language with `.glassEffect()` throughout.
- **Lazy model download** -- The embedding model (~438 MB) is not bundled. It's downloaded from HuggingFace only when you first index documents or search. Cached for instant loads afterwards.

---

## Requirements

- **macOS 26** (Tahoe) or later
- **Apple Silicon** (M1/M2/M3/M4) -- required for MLX
- **Xcode 26** or Swift 6.2+ toolchain
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
│   │   ├── IndexedDocument.swift      # Indexed document metadata
│   │   ├── LLMProvider.swift          # LLM provider enums & configs
│   │   └── Message.swift              # Chat message model
│   ├── Services/
│   │   ├── EmbeddingService.swift     # MLX embedding (bge-base-en-v1.5)
│   │   ├── DatabaseService.swift      # SQLite + sqlite-vec + FTS5
│   │   ├── DocumentProcessor.swift    # PDF/DOCX/TXT/MD/PPTX parsing & chunking
│   │   ├── LLMService.swift           # LLM client protocol & factory
│   │   ├── AnthropicClient.swift      # Anthropic Claude API client
│   │   ├── OpenAIClient.swift         # OpenAI API client
│   │   └── OllamaClient.swift         # Ollama local LLM client
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift        # RAG pipeline orchestration
│   │   └── IndexingViewModel.swift    # Document indexing orchestration
│   ├── Views/
│   │   ├── MainView.swift             # Root NavigationSplitView
│   │   ├── Chat/
│   │   │   ├── ChatView.swift         # Chat interface
│   │   │   ├── MessageBubble.swift    # Message display
│   │   │   └── ChunkPreview.swift     # Retrieved chunk preview
│   │   ├── Documents/
│   │   │   ├── DocumentsView.swift    # Document list & indexing trigger
│   │   │   └── IndexingProgressView.swift
│   │   ├── Settings/
│   │   │   └── SettingsView.swift     # LLM config, DB status, model info
│   │   └── Components/
│   │       └── GlassCard.swift        # Reusable Liquid Glass card
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
                    EmbeddingService (MLX, bge-base-en-v1.5)
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
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MLXEmbedders for on-device BERT inference | SPM |
| [sqlite-vec](https://github.com/asg017/sqlite-vec) | Vector search extension for SQLite | Vendored C source |
| System SQLite3 | Database engine (ships with macOS) | macOS SDK |

No other third-party dependencies. LLM clients use `URLSession` directly.

---

## Configuration

### Embedding Model

- **Model:** BAAI/bge-base-en-v1.5 (768 dimensions, BERT-based)
- **Download:** Automatic on first use (~438 MB from HuggingFace)
- **Cache:** `~/.cache/huggingface/hub/`
- **Privacy:** 100% on-device inference via MLX on Apple Silicon

### LLM Providers

| Mode | Provider | Setup |
|---|---|---|
| Anthropic | Claude API | Enter API key in Settings |
| OpenAI | GPT-4 API | Enter API key in Settings |
| Ollama | Local via HTTP | Install Ollama, run a model |
| Bundled | llama.cpp (planned) | No setup needed |

### Database

- **Location:** `~/Library/Application Support/Chunkpad/chunkpad.db`
- **Engine:** SQLite 3 with WAL mode
- **Extensions:** sqlite-vec (vector search), FTS5 (full-text search)

---

## License

TBD
