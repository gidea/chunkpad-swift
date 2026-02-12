import SwiftUI
import AppKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var chatViewModel = ChatViewModel()

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(selection: $appState.selectedItem) {
                Section {
                    Label("New Chat", systemImage: "plus.message")
                        .tag(AppState.SidebarSelection.chat(conversationId: nil))

                    ForEach(chatViewModel.conversations) { conv in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(conv.updatedAt, style: .date)
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
                    }
                } header: {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

                Section {
                    Label("Documents", systemImage: "doc.on.doc")
                        .tag(AppState.SidebarSelection.documents)
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
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            chatViewModel.appState = appState
            Task { await chatViewModel.refreshConversations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await chatViewModel.refreshConversations() }
        }
        .onChange(of: chatViewModel.currentConversationId) { _, newId in
            appState.selectedItem = .chat(conversationId: newId)
        }
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
