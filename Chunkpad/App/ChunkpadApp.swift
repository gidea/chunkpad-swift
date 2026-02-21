import SwiftUI

@main
struct ChunkpadApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .task {
                    appState.retryDatabaseInit = { await initializeDatabase() }
                    await initializeDatabase()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
    }

    @MainActor
    func initializeDatabase() async {
        let db = DatabaseService()
        appState.initError = nil
        appState.conversationDBError = nil
        do {
            try await db.connect()
            appState.isDatabaseConnected = true
            appState.indexedDocumentCount = try await db.documentCount()
            // Bookmark resolution is handled by IndexingViewModel.loadFromDatabase()
            // when the user navigates to the Documents tab, avoiding duplicate work.
        } catch {
            appState.isDatabaseConnected = false
            appState.initError = "Database unavailable: \(error.localizedDescription)"
        }
        appState.loadFromUserProfile()
        do {
            try await appState.conversationDatabase.connect()
        } catch {
            appState.conversationDBError = "Conversation database unavailable: \(error.localizedDescription)"
        }

        // Bridge BundledLLMService status to AppState for Settings and Chat
        await BundledLLMService.shared.setStatusCallback { status in
            Task { @MainActor in
                appState.bundledLLMStatus = status
            }
        }
        appState.bundledLLMStatus = await BundledLLMService.shared.getStatus()
    }
}
