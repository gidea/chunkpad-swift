import SwiftUI

@main
struct ChunkpadApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .task {
                    await initializeDatabase()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
    }

    private func initializeDatabase() async {
        let db = DatabaseService()
        do {
            try await db.connect()
            appState.isDatabaseConnected = true
            appState.indexedDocumentCount = try await db.documentCount()
        } catch {
            appState.isDatabaseConnected = false
            print("Database initialization failed: \(error.localizedDescription)")
        }
        appState.loadFromUserProfile()
        do {
            try await appState.conversationDatabase.connect()
        } catch {
            print("Conversation DB initialization failed: \(error.localizedDescription)")
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
