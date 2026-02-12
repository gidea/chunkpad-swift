# Chunkpad Interface Specification

**UI/UX review document**

Date: February 2026
Status: Current implementation

---

## Application Shell

Chunkpad uses a `NavigationSplitView` with a fixed sidebar and a detail area.

### Window

- Default size: 1000 x 700 pt
- Minimum size: 800 x 600 pt
- Window style: `.automatic` (system-managed Liquid Glass chrome)

### Sidebar

Three tabs, always visible:

| Tab | Icon | Destination |
|---|---|---|
| Chat | `bubble.left.and.bubble.right` | `ChatView` |
| Documents | `doc.on.doc` | `DocumentsView` |
| Settings | `gear` | `SettingsView` |

The selected tab is stored in `AppState.selectedTab` so that other views can programmatically navigate (e.g. the Llama offer dialog's "Open Settings" button sets `selectedTab = .settings`).

---

## 1. Chat View

**File:** `ChatView.swift`
**ViewModel:** `ChatViewModel`

The primary interaction surface. A **NavigationSplitView** with a conversation sidebar and a detail pane:

```
┌─────────────┬──────────────────────────────────────────────────┐
│ Sidebar     │  Toolbar: [Generation Mode Picker]  [New Chat]     │
│             ├──────────────────────────────────────────────────┤
│ [New Chat]  │                                                  │
│             │  Messages Area (scrollable)                       │
│ Conversa-   │    • ContentUnavailableView (empty state)        │
│ tions       │    • MessageBubble (user / assistant)             │
│   • Conv 1  │    • Progress indicators (searching, generating)│
│   • Conv 2  │    • Llama download progress bar                  │
│   • ...     │                                                  │
│             ├──────────────────────────────────────────────────┤
│             │  Error Banner (when viewModel.error != nil)       │
│             │  ⚠ message text                        [Dismiss]  │
│             ├──────────────────────────────────────────────────┤
│             │  Bottom Bar (GlassEffectContainer)                │
│             │  ┌──────────────────────────────────────────┐    │
│             │  │ Chunks Bar (horizontal scroll)            │    │
│             │  │  [ChunkPreview] [ChunkPreview] ... [+]     │    │
│             │  ├──────────────────────────────────────────┤    │
│             │  │ Regenerate Bar (conditional)             │    │
│             │  │  "3/5 chunks selected"    [Regenerate]   │    │
│             │  ├──────────────────────────────────────────┤    │
│             │  │ Input Bar (80% width, centered)           │    │
│             │  │  [TextField ···················] [Send]   │    │
│             │  └──────────────────────────────────────────┘    │
└─────────────┴──────────────────────────────────────────────────┘
```

- **Sidebar** (min width 200pt): "New Chat" button at top; then a list of conversations (title + date). Tapping a row loads that conversation's messages. The current conversation is highlighted. No conversation is restored at app launch — the user starts with an empty state until they send a message (creates a new conversation) or select a past conversation.
- **Detail:** Messages area, optional error banner, and bottom bar (chunks + regenerate + input).

### 1.1 Toolbar

- **Generation Mode Picker** (`.principal` placement): A dropdown showing Claude, ChatGPT, and Ollama. Bound to `AppState.generationMode`. Changing the picker immediately changes which provider will be used for the next message.
- **New Chat** button (`.primaryAction` placement): Creates a new conversation in the chat DB, selects it, and clears local messages/chunks/error. Always enabled. Also available as the top item in the conversation sidebar.

### 1.2 Error Banner

When `ChatViewModel.error` is non-nil (e.g. "No documents indexed yet", "Search failed", "Generation failed"), a banner appears above the bottom bar:

- Warning icon (exclamationmark.triangle.fill), error message text, and a **Dismiss** button that sets `viewModel.error = nil`.
- Styled with `GlassTokens` (element padding, corner radius) for consistency with the rest of the UI.
- Error is cleared at the start of `sendMessage` and when starting regeneration, so a new attempt hides the previous error until the user dismisses or retries.

### 1.3 Messages Area

- **Empty state:** `ContentUnavailableView` with icon and description text: "Ask questions about your indexed documents..."
- **Conversation:** A `LazyVStack` of `MessageBubble` views in a `ScrollView`. Each message shows:
  - Role label ("You" or "Assistant") with icon
  - Content text (selectable via `.textSelection(.enabled)`)
  - Timestamp
  - User messages: tinted glass background (`.accentColor`), right-aligned
  - Assistant messages: neutral glass background, left-aligned
- **Progress indicators** (appended below messages):
  - "Searching documents..." with spinner — during embedding + hybrid search
  - "Generating response..." with spinner — during LLM streaming
  - "Downloading Llama 3.2... N%" with progress bar — during bundled LLM download

### 1.4 Bottom Bar

Wrapped in a `GlassEffectContainer` with flush spacing so chunks bar, regenerate bar, and input bar appear as one cohesive glass surface.

#### Chunks Bar

Appears only when `retrievedChunks` is non-empty. A horizontal `ScrollView` containing:

- **ChunkPreview cards** (260pt wide, max height 120pt) for each `ScoredChunk`:
  - Toggle button (checkmark circle / empty circle) to include/exclude from LLM context
  - Title (one line, truncated)
  - Relevance score pill (e.g. "87 %") with color coding: green >= 70%, orange >= 40%, red < 40%
  - Optional slide number pill
  - Expand/collapse chevron — toggles between 3-line preview and full content
  - Source file path (caption, truncated middle)
  - Excluded chunks dim to 50% opacity
- **Pin button** (`plus.circle`): Opens the Pin Documents sheet to manually include documents in context.

#### Regenerate Bar

Appears only when there are retrieved chunks AND the last message is from the assistant AND generation is not in progress. Shows:

- "N/M chunks selected" count
- "Regenerate" button — re-runs only the LLM generation step (skips re-embedding and re-searching)
- Disabled if zero chunks are selected

#### Input Bar

- `TextField` with placeholder "Ask about your documents...", supports multi-line (1–5 lines)
- **Enter** key submits (via `.onSubmit`)
- **Cmd+Return** as backup keyboard shortcut
- Send button (arrow.up.circle.fill) — disabled when input is empty or generation is in progress
- The bar is 80% of the container width, centered with 10% margins

### 1.5 Dialogs and Sheets

- **Llama Offer Alert:** Shown when the user sends a message but no cloud API key is configured and Llama is not already downloaded. Three buttons:
  - "Download Llama" — starts download, then retries the message
  - "Open Settings" — navigates to Settings tab
  - "Cancel" — dismisses without action
- **Pin Documents Sheet:** Lists all indexed documents with pin/unpin toggles. Each row shows document icon, file name, chunk count, and a pin button. "Done" dismisses the sheet.

### 1.6 Send Message Flow

- If `currentConversationId == nil`, the view model creates a new conversation in the chat DB first, then continues.
- User and assistant messages are persisted to the separate conversation DB (`chunkpad_chat.db`) on send; the conversation title is set from the first user message (truncated).
- Regenerate persists the new assistant message to the same conversation.

```
User types question → presses Enter
    │
    ├─ Cloud/Ollama provider configured? (AppState.resolvedProvider)
    │   └─ YES → sendMessage(text, provider)
    │
    ├─ Bundled Llama already downloaded? (isBundledLLMReady)
    │   └─ YES → sendMessage(text, bundledProvider)
    │
    └─ No provider at all
        └─ prepareLlamaOffer(text)
            → Create conversation if needed, add user message, persist
            → Present Llama Offer alert
            ├─ "Download Llama" → downloadLlamaAndSend()
            ├─ "Open Settings" → navigate to Settings
            └─ "Cancel" → message stays, no response
```

### 1.7 Observations and Concerns

1. **The Regenerate button is always visible after a response.** The `hasChunkSelectionChanged` computed property currently returns `true` whenever there are chunks and an assistant message — regardless of whether the user actually toggled anything. This means the Regenerate button appears immediately after every response, even before the user touches a chunk toggle. This is intentional as a "try again" affordance but may confuse users who haven't toggled anything into thinking something needs regenerating.

2. **Chunks bar and input bar compete for vertical space.** The chunks bar has a `maxHeight` of 120pt. On smaller windows (600pt minimum height), the chunks bar + regenerate bar + input bar can consume ~200pt of vertical space, leaving limited room for the conversation. There is currently no way to collapse the chunks bar entirely.

3. **The Pin button only appears when chunks are already shown.** The `plus.circle` button sits at the end of the chunks bar scroll, which only appears after the first search returns results. A user who wants to pre-pin documents before their first question has no way to do so. This is a bootstrapping problem — pins are only useful after at least one query has been made, but a user may want to set up their context before asking.

4. **Pinned chunks always get score 1.0.** Pinned document chunks are inserted at the top with a hardcoded relevance of 1.0 regardless of actual relevance to the query. If a user pins a large document with many chunks, all of those chunks appear at 100% relevance, which is misleading and could flood the context window. Pinned chunks should perhaps have a visual distinction (e.g. a pin icon instead of a score) rather than a fake score.

5. **Llama download progress sits in the message list.** The Llama download progress bar is rendered as a row inside the `LazyVStack` of messages. It scrolls with the conversation and could be scrolled out of view. A better position might be a fixed banner or inline in the bottom bar.

6. **No auto-scroll to latest message.** When new tokens stream in from the LLM, the `ScrollView` does not automatically scroll to the bottom. The user must manually scroll down to follow the streaming response. This breaks the expected chat UX.

7. **Generation mode picker is disconnected from API key state.** The user can select "Claude" in the toolbar picker even without an Anthropic API key. The mismatch is only discovered when they try to send a message, at which point `resolvedProvider()` returns `nil` and the Llama offer appears. The picker could visually indicate which providers are configured (e.g. checkmark or badge) or disable providers that lack keys.

8. **Chunk toggle state is ephemeral.** The `isIncluded` toggle on `ScoredChunk` is in-memory only. If the user sends a new message, `retrievedChunks` is replaced by fresh search results (all with `isIncluded = true`), losing any previous toggling. This is probably correct for "next question" but may surprise users who expect toggles to persist within a session.

9. **`sendMessage` hardcodes k=10 and minScore=0.1.** The number of retrieved chunks and the relevance threshold are not user-configurable. Power users may want to adjust these — e.g. fewer chunks for concise answers or a higher threshold for precision.

10. **No streaming cancellation.** Once the LLM starts streaming, there is no way to cancel the generation. The send button is disabled during generation, and there is no stop button. Long responses from slow providers (especially bundled Llama) cannot be interrupted.

---

## 2. Documents View

**File:** `DocumentsView.swift`
**ViewModel:** `IndexingViewModel`

The document management screen. Uses a **two-step indexing pipeline**: (1) process documents into editable chunk markdown files on disk, (2) review and embed selected chunks into the vector database.

### 2.0 Layout

The view has three states:

**Empty state** (no chunk tree, no indexed documents, not processing):

```
┌──────────────────────────────────────────────────┐
│  Toolbar: [Add Folder]                           │
├──────────────────────────────────────────────────┤
│                                                  │
│  Error Banner (if previous error)                │
│  ⚠ error message                     [Dismiss]  │
│                                                  │
│  ContentUnavailableView                          │
│    "No Documents Indexed"                        │
│    Supported: TXT, RTF, DOC, DOCX, ODT, PDF     │
│    [Add Folder] button                           │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Processing state** (during Step 1 or Step 2):

```
┌──────────────────────────────────────────────────┐
│  Toolbar: [Add Folder] (disabled)                │
├──────────────────────────────────────────────────┤
│                                                  │
│  Model Download Progress (during Step 2 only):   │
│  ┌──────────────────────────────────────────┐    │
│  │ ↓ Downloading embedding model...         │    │
│  │ ████████████░░░░░░░░ 60%                 │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  Processing Progress:                            │
│  ┌──────────────────────────────────────────┐    │
│  │ 🔍 report.pdf                            │    │
│  │ 12/34 files                              │    │
│  │ ████████████████░░░░ 35%                 │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  Error Banner (if error)                         │
│                                                  │
│  (Tree or document list appears below once done) │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Review state** (chunk tree available after Step 1):

```
┌──────────────────────────────────────────────────┐
│  Toolbar: [Add Folder]  [Embed Selected (N)]     │
├─────────────────┬────────────────────────────────┤
│ Chunk Tree      │  Chunk Detail                  │
│ (sidebar)       │                                │
│                 │  report.pdf.md                  │
│ ▼ _chunks       │                                │
│   📄 report.md  │  ☑ Chunk 1         (2340 chars)│
│   📄 notes.md   │  ┌─────────────────────────┐   │
│   ▼ subdir      │  │ First chunk content...  │   │
│     📄 memo.md  │  └─────────────────────────┘   │
│                 │                                │
│                 │  ☑ Chunk 2         (1892 chars)│
│                 │  ┌─────────────────────────┐   │
│                 │  │ Second chunk content...  │   │
│                 │  └─────────────────────────┘   │
│                 │                                │
│                 │  ☐ Chunk 3 (excluded, dimmed)  │
│                 │  ┌─────────────────────────┐   │
│                 │  │ Third chunk content...   │   │
│                 │  └─────────────────────────┘   │
│                 │                                │
├─────────────────┴────────────────────────────────┤
│  Modified Chunk Files Banner (if detected)       │
│  ⚙ Some chunk files modified.   [Re-embed]      │
├──────────────────────────────────────────────────┤
│  Fallback: Document List (if tree not available) │
│    📄 report.pdf    3 chunks · PDF  · 2m ago     │
│    📝 notes.md      5 chunks · MD   · 2m ago     │
└──────────────────────────────────────────────────┘
```

### 2.1 Step 1: Process Folder

```
User clicks "Add Folder"
    → NSOpenPanel (directories only, single selection)
    → User selects folder
    → IndexingViewModel.selectAndProcessFolder()
        → DocumentProcessor.processDirectory(at: url)
            → Enumerate supported files (skips _chunks/ directories)
            → For each file: parse → chunk
            → Chunk size/overlap from AppState Settings (default 1000 tokens, 100 overlap)
            → Returns [URL: [ProcessedChunk]]
        → ChunkFileService.writeChunks() for each file
            → Creates {selectedFolder}/_chunks/ (inside the selected folder)
            → Writes one .md file per source file, mirroring folder structure
        → ChunkFileService.discoverChunkFiles() → [ChunkFileInfo]
        → ChunkFileTree built for sidebar display
        → IndexedFolder persisted to UserDefaults
```

No embedding model is downloaded. No database writes. This step is fast.

### 2.2 Review Phase

After Step 1, the view enters the **review state** with a `NavigationSplitView`:

- **Sidebar** (min 220pt): An `OutlineGroup` tree of chunk files, mirroring the `_chunks/` folder structure. Only file nodes are selectable; folder nodes expand/collapse.
- **Detail**: When a file is selected, shows a scrollable list of chunks from that file:
  - Each chunk shows: toggle button (checkmark circle / empty circle), title, character count, and the full chunk text (monospaced, up to 20 lines, selectable).
  - Excluded chunks dim to 50% opacity.
- **"Embed Selected (N)"** toolbar button: Shows the count of included chunks. Triggers Step 2.
- **Modified Files Banner**: When the app detects that chunk files have been modified externally (via file modification dates), shows an orange banner with a "Re-embed" button. Appears when the user returns to the app after editing `.md` files.

### 2.3 Step 2: Embed Selected

```
User clicks "Embed Selected"
    → IndexingViewModel.embedApprovedChunks()
        → Connect to database
        → Download embedding model (if not cached)
            → Progress: "Downloading embedding model... N%"
        → Load model into MLX
        → For each included chunk (grouped by source file):
            → Delete previous embeddings for that source path
            → Create IndexedDocument in DB
            → Embed chunk content (no query prefix)
            → Store chunk + vector in SQLite
            → Track embedded chunk IDs (persisted in UserDefaults)
        → Update AppState.indexedDocumentCount
```

### 2.4 Fallback Document List

When no chunk tree is available but documents exist in the database (e.g. from a previous session where the `_chunks/` folder was deleted), a flat list of `IndexedDocument` records is shown. Each row shows: document type icon, file name, chunk count, document type label, and relative time since indexing.

This list is loaded via `.task { indexedDocuments = await viewModel.loadIndexedDocumentsFromDatabase() }` and refreshed when `viewModel.isIndexing` transitions to `false`.

### 2.5 Observations and Concerns

1. **No way to remove indexed documents.** Once embedded, there is no delete action — no swipe-to-delete on list rows, no "Remove" button, no "Clear All" option. Users who want to re-index or remove stale documents have no UI path.

2. **No incremental processing.** Re-adding the same folder re-processes all files and overwrites the `_chunks/` directory. There is no diff to detect which source files have changed.

3. **Folder selection is per-action.** The user must click "Add Folder" and use `NSOpenPanel` for every processing operation. The `IndexedFolder` is persisted, but only the most recent folder is remembered, and there is no UI to re-process or re-add it without the folder picker.

4. **No cancel during processing or embedding.** The "Add Folder" button is disabled during processing, but there is no cancel/stop button.

5. **No file-level progress during embedding.** The progress bar shows file count (e.g. "3/5 files") but not chunk-level detail. Large files with many chunks cause the progress bar to stall on a single file.

6. **Chunk tree requires on-disk `_chunks/` folder.** If the user deletes the `_chunks/` directory, the tree cannot be rebuilt (falls back to the flat document list). There is no "Re-process" button to regenerate chunk files from the original documents.

---

## 3. Settings View

**File:** `SettingsView.swift`
**State:** `AppState` (direct bindings)

A `Form` with `.grouped` style, divided into sections.

```
┌──────────────────────────────────────────────────┐
│  Database                                        │
│    Engine:             SQLite + sqlite-vec        │
│    Status:             ● Connected                │
│    Location:           ~/Library/Application...   │
│    Indexed Documents:  42                         │
├──────────────────────────────────────────────────┤
│  Embeddings (Local via MLX)                      │
│    Model:              bge-base-en-v1.5           │
│    Size:               ~438 MB                    │
│    Dimensions:         768                        │
│    Status:             ● Ready                    │
│    (if not downloaded: "Will download on index")  │
│    Framework:          MLX Swift on Apple Silicon  │
│    Cache:              ~/.cache/                   │
│    Privacy:            100% on-device              │
├──────────────────────────────────────────────────┤
│  Llama (Local)                                   │
│    Model:              Llama 3.2 3B Instruct 4bit │
│    Size:               ~1.7 GB                    │
│    Status:             ● Ready / ○ Not Downloaded │
│    Cache:              ~/.cache/                   │
│    [Download Llama] / [Remove from memory]        │
├──────────────────────────────────────────────────┤
│  Document Indexing                               │
│    Chunk size (tokens): [1000]                    │
│    Overlap (tokens):    [100]                     │
│    Approx. characters per chunk: ~4000            │
├──────────────────────────────────────────────────┤
│  Generation Model                                │
│    ○ Claude                                      │
│    ○ ChatGPT                                     │
│    ○ Ollama                                      │
├──────────────────────────────────────────────────┤
│  Claude (Anthropic)                              │
│    API Key:            [••••••••••••]             │
│    Model:              [Claude Sonnet 4.5 ▾]     │
├──────────────────────────────────────────────────┤
│  ChatGPT (OpenAI)                                │
│    API Key:            [••••••••••••]             │
│    Model:              [GPT-5.2 ▾]               │
├──────────────────────────────────────────────────┤
│  Ollama Configuration (only when Ollama selected)│
│    Endpoint:           [http://localhost:11434]   │
│    Model:              [llama3.3]                 │
├──────────────────────────────────────────────────┤
│  🛡️ Privacy note (contextual)                   │
├──────────────────────────────────────────────────┤
│  About                                           │
│    Version:            0.1.0                      │
│    Architecture:       Local MLX embeddings...    │
└──────────────────────────────────────────────────┘
```

### 3.1 Key Interactions

- **Llama section:** Shows model name, size, status (with colored dot), and cache path. If not downloaded/ready, a "Download Llama" button is shown. If ready, a "Remove from memory" button is available. The download button is disabled while downloading or loading.
- **Document Indexing section:** Chunk size (tokens) and overlap (tokens) are configurable via numeric text fields. Both are persisted in UserDefaults. An "Approx. characters per chunk" read-only field shows the derived value (tokens × 4). These values are used by `DocumentProcessor` during Step 1 (folder processing). Changing them and re-processing a folder regenerates chunk files with the new sizes.
- **Generation Model radio group:** Selects the active LLM provider. All three options are always shown regardless of configuration state.
- **Claude and ChatGPT sections:** Always visible so users can pre-configure both keys and switch freely. Each has a `SecureField` for the API key and a `Picker` for model selection.
- **Ollama section:** Only shown when Ollama is selected as the generation mode.
- **Privacy note:** Contextual — shows a cloud warning when a cloud provider is selected, or an "everything local" message for Ollama.

### 3.2 Persistence

- **API keys** are stored in the macOS Keychain (service `"Chunkpad"`, accounts `anthropic_api_key` / `openai_api_key`) via `KeychainHelper`. They are loaded in `AppState.loadFromUserProfile()` at launch and saved in `saveToUserProfile()` when changed in Settings.
- **Other settings** (generation mode, anthropic/openai model, ollama endpoint/model, context size, chunk size tokens, chunk overlap tokens) are stored in `UserDefaults` and loaded/saved the same way. Settings view uses `.onChange(of: ...)` on each bound value to call `saveToUserProfile()`, so changes are persisted as the user edits.

### 3.3 Observations and Concerns

1. **No validation of API keys.** The user can enter any string as an API key. There is no "Test Connection" button or automatic validation. A bad key only surfaces as an error when the user tries to chat.

2. **No visual connection between Settings and Chat.** After entering an API key in Settings, there is no confirmation or feedback that the key is active. The user must navigate to Chat and send a message to verify. A "Connected" badge or test-send button would help.

3. **Ollama configuration doesn't verify the endpoint.** The user can enter any endpoint URL. There is no connectivity check to confirm Ollama is running or that the specified model is available.

4. **The embedding model section is informational only.** Users cannot trigger a manual download, clear the cache, or change the embedding model. This is by design (the model downloads on first index) but may frustrate users who want to pre-download the model before indexing.

5. **Llama section has limited management.** The Llama section shows status and allows downloading or unloading from memory, but there is no way to delete the cached model files from disk to reclaim ~1.7 GB. Users must manually delete the cache folder.

---

## 4. Design System

### Glass Components

| Component | Usage |
|---|---|
| `GlassTokens` | Centralized radii, spacing, and padding values |
| `GlassCard` | Cards and panels (not currently used in main views) |
| `GlassIconButton` | Circular icon buttons (chunk toggle, expand, pin) |
| `GlassPill` | Capsule tags (relevance score, slide number) |

### Design Tokens

| Token | Value | Used In |
|---|---|---|
| `Radius.card` | 20pt | Input bar, message bubbles, indexing progress |
| `Radius.element` | 14pt | Chunk previews, error banners |
| `Radius.input` | 16pt | Text field glass effect |
| `Spacing.containerDefault` | 8pt | Chunks bar spacing |
| `Spacing.containerFlush` | 0pt | Bottom bar (flush stacking) |
| `Padding.card` | 16pt all sides | Indexing progress card |
| `Padding.element` | 12pt all sides | Chunk previews, error banners |

---

## 5. Intended User Flow

### First-Time User (No Documents, No API Key)

```
1. Open app → Chat tab is selected
2. See empty state: "Start a Conversation"
3. Navigate to Documents tab
4. Click "Add Folder" → select a folder of documents
5. Watch processing progress (files parsed, chunked to disk — fast, no model needed)
6. Review chunk tree in sidebar: browse files, toggle chunks on/off
7. (Optional) Adjust chunk size/overlap in Settings, re-add folder to regenerate
8. Click "Embed Selected (N)" → embedding model downloads (~438 MB, one-time)
9. Watch embedding progress
10. Navigate to Settings tab
11. Enter API key for Claude or ChatGPT, select model
12. Navigate back to Chat tab
13. Type a question → press Enter
14. See "Searching documents..." → chunks bar appears with results
15. See "Generating response..." → assistant message streams in
16. Review retrieved chunks with relevance scores
17. Optionally toggle chunks, tap Regenerate for a refined answer
```

### First-Time User (No API Key, Uses Llama)

```
1-9. Same as above (process and embed documents first)
10. Skip Settings — no API key entered
11. Navigate to Chat tab
12. Type a question → press Enter
13. Alert: "No LLM Provider Configured — Download Llama 3.2?"
14. Click "Download Llama" → progress bar appears in chat
15. After download, message is automatically retried
16. Chunks bar + assistant response appear
```

### Returning User

```
1. Open app → Chat tab (no conversation restored at launch; empty state or sidebar visible)
2. Option A: Select a past conversation from sidebar → messages load from chunkpad_chat.db
   Option B: Tap "New Chat" or type and send → new conversation created, message persisted
3. Type question → press Enter
4. Embedding model loads from cache (instant)
5. Hybrid search returns scored chunks
6. Chunks bar shows results with relevance %
7. LLM streams response (user + assistant messages persisted to conversation)
8. User reviews chunks, toggles some off
9. Taps Regenerate → new response with filtered context (new assistant message persisted)
```

### Pinning Documents

```
1. User sends at least one question (chunks bar appears)
2. Scrolls to end of chunks bar, clicks [+] button
3. Pin Documents sheet opens with all indexed documents
4. User pins 1-2 specific documents
5. Closes sheet
6. Sends next question
7. Pinned documents' chunks are merged at top of results
8. Regular search results follow below
```

---

## 6. Cross-Cutting Concerns

### Error Visibility

| Error Source | Current Behaviour |
|---|---|
| No documents indexed | `ChatViewModel.error` set; **error banner** above bottom bar (icon + message + Dismiss) |
| Search failed | Error string set; **error banner** above bottom bar |
| Generation failed | Error message + fallback assistant bubble; **error banner** shows generation failure |
| Llama download failed | Error string set; **error banner** shows after dismiss/retry |
| Processing/indexing failed | Error banner in DocumentsView (shown in both empty state and document list views, with Dismiss button) |
| Database connection failed | Status dot turns red in Settings (passive) |

### State Lifecycle

| State | Persisted? | Scope | Notes |
|---|---|---|---|
| API keys | Yes (Keychain) | Persistent | Via `KeychainHelper`; load/save in AppState |
| Generation mode | Yes (UserDefaults) | Persistent | Load at launch, save on change in Settings |
| Model selections | Yes (UserDefaults) | Persistent | Anthropic/OpenAI model, Ollama endpoint/model, context size |
| Chunk size/overlap | Yes (UserDefaults) | Persistent | `chunkSizeTokens`, `chunkOverlapTokens` in AppState |
| Indexed folder | Yes (UserDefaults) | Persistent | `rootURL` + `chunksRootURL` pair; only most recent folder |
| Embedded chunk IDs | Yes (UserDefaults) | Persistent | Set of `"{filePath}::chunk_{index}"` strings |
| Chunk files on disk | Yes (filesystem) | Persistent | `{folder}/_chunks/` directory; editable by user |
| Chunk inclusion toggles | No | Session | `chunkInclusionOverrides` dict in IndexingViewModel |
| Conversations & messages | Yes (SQLite) | Persistent | Separate DB `chunkpad_chat.db`; no restore at launch |
| Current conversation | No | Session | In-memory `currentConversationId`; user selects or creates |
| Retrieved chunks | No | Per-query | Replaced on new query |
| Chunk toggles (chat) | No | Per-query | `ScoredChunk.isIncluded`; reset on new query |
| Pinned documents | No | Session | In-memory only; not persisted |
| Indexed document count | Yes (DB) | Persistent | Main DB `chunkpad.db` |
| Embedding model cache | Yes (disk) | Persistent | Survives quit |
| Llama model cache | Yes (disk) | Persistent | Survives quit |

### Missing UI Capabilities

| Capability | Status | Impact |
|---|---|---|
| Persist conversation | **Done** | Conversations/messages in `chunkpad_chat.db`; list + load in sidebar |
| Persist settings | **Done** | Keychain for API keys, UserDefaults for other settings |
| Error display in chat | **Done** | Error banner above bottom bar with Dismiss |
| Error display in documents | **Done** | Error banner shown in both empty state and document list |
| Document list population | **Done** | Loaded via `.task` from `DatabaseService.listDocuments()` |
| Llama status in Settings | **Done** | Llama section with status, download, and unload buttons |
| Configurable chunk size | **Done** | Chunk size (tokens) and overlap (tokens) in Settings |
| Two-step indexing | **Done** | Process → review → embed pipeline with chunk file tree |
| Auto-scroll to newest message | Missing | User must manually scroll during streaming |
| Stop generation | Missing | Cannot cancel slow LLM responses |
| Delete indexed documents | Missing | No way to remove stale data |
| Pre-query document pinning | Missing | Can only pin after first search |
| Configurable search params | Missing | k=10 and minScore=0.1 are hardcoded |
| Markdown rendering | Missing | Assistant responses render as plain text |
| In-app chunk editor | Missing | Must edit .md files externally; app detects modifications |
| Cancel processing/embedding | Missing | No stop button during folder processing or embedding |

---

## 7. Summary of Recommended Changes

Implemented:

- **Display errors in chat UI** — Error banner above the bottom bar when `ChatViewModel.error` is set; warning icon, message text, Dismiss button. Cleared on new send/regenerate or when user dismisses.
- **Display errors in documents UI** — Error banner shown in both empty state and document list views, with Dismiss button. Previously, errors during processing were silently swallowed when no documents were loaded yet.
- **Persist settings** — API keys in Keychain (`KeychainHelper`); generation mode, model selections, Ollama config, context size, chunk size/overlap in UserDefaults. Load in `AppState.loadFromUserProfile()` at launch; save in `saveToUserProfile()` triggered by `.onChange` in Settings.
- **Persist conversation** — Separate SQLite DB `chunkpad_chat.db` (ConversationDatabaseService). Conversations and messages stored; no conversation loaded at launch. Chat tab has NavigationSplitView with conversation list sidebar (New Chat + list); selecting a conversation loads its messages; New Chat creates and selects a new conversation.
- **Two-step indexing pipeline** — Process documents into chunk markdown files (Step 1), then review and embed (Step 2). Chunk tree sidebar with include/exclude toggles, "Embed Selected" button, and modified file detection. See Section 2 for full details.
- **Populate the document list** — `DocumentsView` loads indexed documents from the database via `.task` on appear, refreshed when indexing completes.
- **Show Llama status in Settings** — Llama section with model name, size, status dot, download button (when not ready), and "Remove from memory" button (when ready).
- **Configurable chunk size** — Document Indexing section in Settings with chunk size (tokens) and overlap (tokens) fields, persisted in UserDefaults.
- **Sandbox fix** — Changed entitlement from `files.user-selected.read-only` to `files.user-selected.read-write` so the app can write `_chunks/` inside user-selected folders. Chunk output directory moved from sibling (`{folder}_chunks/`) to inside (`{folder}/_chunks/`) to stay within NSOpenPanel's security-scoped access.

Remaining, in priority order:

1. **Auto-scroll chat** — Add a `ScrollViewReader` with `scrollTo` when messages update or tokens stream in.

2. **Add stop generation button** — Replace the disabled send button with a stop button during generation. Use `Task` cancellation.

3. **Distinguish pinned chunks visually** — Show a pin icon instead of a fake "100 %" relevance score. Makes it clear these are manually included, not search results.

4. **Add document deletion** — Swipe-to-delete or a toolbar button to remove indexed documents and their chunks from the vector DB.

5. **Allow collapsing the chunks bar** — A disclosure toggle to hide the chunks bar when the user wants more conversation space.

6. **Validate/test API keys** — A "Test" button in Settings that sends a minimal request to verify the key works.

7. **In-app chunk editor** — Edit chunk content directly in the review view instead of requiring an external text editor.

8. **Cancel processing/embedding** — A stop button to abort folder processing or embedding in progress.
