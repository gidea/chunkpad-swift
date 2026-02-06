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
    }
}
