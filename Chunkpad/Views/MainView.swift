import SwiftUI
import AppKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var chatViewModel = ChatViewModel()
    @State private var conversationToDelete: Conversation?
    @State private var conversationToRename: Conversation?
    @State private var renameText = ""

    /// True when both main DB and conversation DB are broken (greying out Chat + Documents).
    private var isFullyUnavailable: Bool {
        appState.initError != nil
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Persistent DB error banner (appears below toolbar, above content)
            if let dbError = appState.initError {
                dbErrorBanner(message: dbError, isMainDB: true)
            }
            if let convError = appState.conversationDBError {
                dbErrorBanner(message: convError, isMainDB: false)
            }

            NavigationSplitView {
                List(selection: $appState.selectedItem) {
                    Section {
                        Label("New Chat", systemImage: "plus.message")
                            .tag(AppState.SidebarSelection.chat(conversationId: nil))
                            .disabled(appState.conversationDBError != nil)
                            .help(appState.conversationDBError != nil ? (appState.conversationDBError ?? "") : "")

                        ForEach(chatViewModel.conversations) { conv in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.title)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    Text(conv.updatedAt, style: .date)
                                    if conv.messageCount > 0 {
                                        Text("·")
                                        Text("\(conv.messageCount) msg\(conv.messageCount == 1 ? "" : "s")")
                                    }
                                    if conv.collectionId != nil {
                                        Image(systemName: "folder.badge.person.crop")
                                    }
                                    if conv.exportedAt != nil {
                                        Image(systemName: "tray.and.arrow.down.fill")
                                            .help("Saved to Knowledge Base")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(AppState.SidebarSelection.chat(conversationId: conv.id))
                            .listRowBackground(
                                conv.id == chatViewModel.currentConversationId
                                    ? Color.accentColor.opacity(0.2)
                                    : nil
                            )
                            .contextMenu {
                                Button {
                                    conversationToRename = conv
                                    renameText = conv.title
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    conversationToDelete = conv
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    conversationToDelete = conv
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }

                    Section {
                        Label("Documents", systemImage: "doc.on.doc")
                            .tag(AppState.SidebarSelection.documents)
                            .disabled(isFullyUnavailable)
                            .foregroundStyle(isFullyUnavailable ? .secondary : .primary)
                            .help(isFullyUnavailable ? (appState.initError ?? "") : "")
                        Label("Settings", systemImage: "gear")
                            .tag(AppState.SidebarSelection.settings)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Chunkpad")
                .onChange(of: appState.selectedItem) { _, newValue in
                    handleSelectionChange(newValue)
                }
            } detail: {
                detailView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            chatViewModel.appState = appState
            Task {
                await chatViewModel.refreshConversations()
                await chatViewModel.validatePinnedDocuments()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await chatViewModel.refreshConversations() }
        }
        // 9.2: Clean up stale pins when a document is deleted
        .onReceive(NotificationCenter.default.publisher(for: IndexingViewModel.documentDeletedNotification)) { _ in
            Task { await chatViewModel.validatePinnedDocuments() }
        }
        .onChange(of: chatViewModel.currentConversationId) { _, newId in
            appState.selectedItem = .chat(conversationId: newId)
        }
        .alert("Delete Conversation?", isPresented: .init(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let conv = conversationToDelete {
                    Task { await chatViewModel.deleteConversation(id: conv.id) }
                }
            }
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
        } message: {
            Text("This will permanently delete \"\(conversationToDelete?.title ?? "")\" and all its messages.")
        }
        .alert("Rename Conversation", isPresented: .init(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let conv = conversationToRename {
                    Task { await chatViewModel.renameConversation(id: conv.id, title: renameText) }
                }
            }
            Button("Cancel", role: .cancel) { conversationToRename = nil }
        } message: {
            Text("Enter a new title for this conversation.")
        }
    }

    // MARK: - DB Error Banner

    private func dbErrorBanner(message: String, isMainDB: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMainDB ? "Database Error" : "Chat Database Error")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry") {
                Task { await appState.retryDatabaseInit?() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red.opacity(0.08))
    }

    private func handleSelectionChange(_ selection: AppState.SidebarSelection) {
        switch selection {
        case .chat(conversationId: let id):
            if let id {
                Task { await chatViewModel.loadConversation(id: id) }
            } else {
                Task { await chatViewModel.createNewConversation() }
            }
        case .documents, .settings:
            break
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedItem {
        case .chat:
            ChatView(viewModel: chatViewModel)
        case .documents:
            DocumentsView()
        case .settings:
            SettingsView()
        }
    }
}
