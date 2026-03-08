import SwiftUI

/// Settings section for database status, stats, and data management.
struct DatabaseSettingsSection: View {
    @Environment(AppState.self) private var appState

    @State private var dbFileSize: Int64?
    @State private var dbChunkCount: Int?
    @State private var showClearConfirmation = false

    var body: some View {
        Section("Database") {
            LabeledContent("Engine") {
                Text("SQLite + sqlite-vec")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isDatabaseConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.isDatabaseConnected ? "Connected" : "Not Connected")
                }
            }
            LabeledContent("Location") {
                Text("~/Library/Application Support/Chunkpad/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Documents") {
                Text("\(appState.indexedDocumentCount)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Chunks") {
                Text(dbChunkCount.map { "\($0)" } ?? "\u{2014}")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Size") {
                Text(formattedDatabaseSize)
                    .foregroundStyle(.secondary)
            }

            if appState.isDatabaseConnected && appState.indexedDocumentCount > 0 {
                Button("Clear All Data\u{2026}", role: .destructive) {
                    showClearConfirmation = true
                }
                .controlSize(.small)
            }
        }
        .task { await refreshDatabaseStats() }
        .confirmationDialog("Clear All Data", isPresented: $showClearConfirmation) {
            Button("Clear Database", role: .destructive) {
                Task { await clearDatabase() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all indexed documents, chunks, and embeddings. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private var formattedDatabaseSize: String {
        guard let size = dbFileSize else { return "\u{2014}" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func refreshDatabaseStats() async {
        guard appState.isDatabaseConnected else { return }
        let db = DatabaseService()
        do {
            try await db.connect()
            dbChunkCount = try await db.totalChunkCount()
            dbFileSize = await db.databaseFileSize()
        } catch {
            dbChunkCount = nil
            dbFileSize = nil
        }
    }

    private func clearDatabase() async {
        let db = DatabaseService()
        do {
            try await db.connect()
            try await db.deleteAllData()
            appState.indexedDocumentCount = 0
            dbChunkCount = 0
            await refreshDatabaseStats()
            NotificationCenter.default.post(name: IndexingViewModel.documentDeletedNotification, object: nil)
        } catch {
            // Silently fail; user can retry
        }
    }
}
