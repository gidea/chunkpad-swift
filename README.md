# Chunkpad

**A native macOS app for local document search and AI-assisted Q&A, built with Swift and SwiftUI.**

Chunkpad indexes your local documents (PDF, DOCX, TXT, Markdown, PPTX, RTF), generates semantic embeddings on-device using Apple Silicon, stores them in an embedded SQLite database with vector search, and lets you query your knowledge base using the LLM of your choice -- cloud or local.

---

## Key Features

- **100% local indexing** -- Documents are chunked and embedded on your Mac. Nothing leaves your machine during indexing.
- **On-device embeddings** -- Uses [BAAI/bge-base-en-v1.5](https://huggingface.co/BAAI/bge-base-en-v1.5) via MLX Swift on Apple Silicon. No external API calls.
- **Embedded database** -- SQLite + [sqlite-vec](https://github.com/asg017/sqlite-vec) for vector search + FTS5 for keyword search. No server to install.
- **Hybrid search** -- Combines vector similarity (70%) and full-text matching (30%) with a relevance threshold. Irrelevant chunks are automatically filtered out.
- **Transparent retrieval** -- Retrieved chunks are shown with relevance scores. Toggle individual chunks on/off and regenerate with your selection. Pin documents to always include them in context.
- **Flexible LLM** -- Choose between cloud providers (Claude, ChatGPT), local models (Ollama), or the bundled Llama 3.2. Both cloud API keys can be configured upfront. If no API key is set, the app offers to download Llama 3.2 for free local generation.
- **Liquid Glass UI** -- macOS 26 native design language with `.glassEffect()` throughout. Design values are centralized in `GlassTokens` for accessibility control, since Liquid Glass has known legibility and contrast issues in its initial release.
- **Lazy model downloads** -- Neither the embedding model (~438 MB) nor the local LLM (~1.7 GB) is bundled with the app. The embedding model downloads only when you index documents. Llama 3.2 downloads only if you accept the offer. Cached locally for instant loads afterwards.

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
│   │   ├── ScoredChunk.swift          # Chunk + relevance score + include toggle
│   │   ├── IndexedDocument.swift      # Indexed document metadata
│   │   ├── LLMProvider.swift          # LLM provider enums & configs
│   │   └── Message.swift              # Chat message model
│   ├── Services/
│   │   ├── EmbeddingService.swift     # MLX embedding (bge-base-en-v1.5)
│   │   ├── BundledLLMService.swift    # Llama 3.2 local generation via MLXLLM
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
│   │   │   ├── ChatView.swift         # Chat interface + regenerate + pin docs
│   │   │   ├── MessageBubble.swift    # Message display
│   │   │   ├── ChunkPreview.swift     # Chunk preview with score & toggle
│   │   │   └── PinDocumentsSheet.swift # Pin documents to always include
│   │   ├── Documents/
│   │   │   ├── DocumentsView.swift    # Document list & indexing trigger
│   │   │   └── IndexingProgressView.swift
│   │   ├── Settings/
│   │   │   └── SettingsView.swift     # LLM config, DB status, model info
│   │   └── Components/
│   │       ├── GlassTokens.swift      # Centralized design tokens (radii, spacing, padding)
│   │       ├── GlassCard.swift        # Reusable Liquid Glass card
│   │       ├── GlassIconButton.swift  # Circular glass icon button
│   │       └── GlassPill.swift        # Capsule-shaped glass tag/label
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
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MLXEmbedders (embeddings) + MLXLLM (Llama generation) | SPM |
| [sqlite-vec](https://github.com/asg017/sqlite-vec) | Vector search extension for SQLite | Vendored C source |
| System SQLite3 | Database engine (ships with macOS) | macOS SDK |

No other third-party dependencies. LLM clients use `URLSession` directly.

---

## Configuration

### Embedding Model

- **Model:** BAAI/bge-base-en-v1.5 (768 dimensions, BERT-based)
- **Purpose:** Creates vector embeddings for document search. NEVER used for text generation.
- **Download:** From HuggingFace, only when you index documents (~438 MB). Never from chat.
- **Cache:** `~/.cache/` (cached locally after first download)
- **Privacy:** 100% on-device inference via MLX on Apple Silicon

### LLM Providers (Text Generation)

| Mode | Provider | Setup |
|---|---|---|
| Anthropic | Claude API | Enter API key in Settings |
| OpenAI | ChatGPT API | Enter API key in Settings |
| Ollama | Local via HTTP | Install Ollama, run a model |
| Llama 3.2 | Bundled via MLX | Accept download offer (~1.7 GB) |

Both cloud API keys can be configured simultaneously in Settings, so you can switch between Claude and ChatGPT without re-entering credentials. If no API key is set, the app offers to download Llama 3.2 for free local generation.

### Database

- **Location:** `~/Library/Application Support/Chunkpad/chunkpad.db`
- **Engine:** SQLite 3 with WAL mode
- **Extensions:** sqlite-vec (vector search), FTS5 (full-text search)

---

## License

TBD
