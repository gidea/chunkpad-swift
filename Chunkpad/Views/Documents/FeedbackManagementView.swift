import SwiftUI

// MARK: - FeedbackManagementView (Task 16.5)

/// Sheet showing all active chunk feedback signals grouped by source document.
/// Users can toggle or clear individual signals, or bulk-clear by type.
struct FeedbackManagementView: View {
    let database: DatabaseService

    @State private var feedbackRecords: [ChunkFeedback] = []
    @State private var chunkTitles: [String: String] = [:]
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Derived

    private var filtered: [ChunkFeedback] {
        guard !searchText.isEmpty else { return feedbackRecords }
        let lower = searchText.lowercased()
        return feedbackRecords.filter { record in
            let title = chunkTitles[record.chunkId] ?? ""
            let fileName = URL(fileURLWithPath: record.sourcePath).lastPathComponent
            return title.lowercased().contains(lower) || fileName.lowercased().contains(lower)
        }
    }

    private var groupedBySource: [(path: String, records: [ChunkFeedback])] {
        let groups = Dictionary(grouping: filtered, by: \.sourcePath)
        return groups.keys.sorted().compactMap { path in
            guard let g = groups[path] else { return nil }
            return (path: path, records: g)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading feedback…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if feedbackRecords.isEmpty {
                    ContentUnavailableView {
                        Label("No Feedback Signals", systemImage: "hand.thumbsup")
                    } description: {
                        Text("Boost or hide chunks during chat to build your retrieval signal history.")
                    }
                } else {
                    feedbackList
                }
            }
            .navigationTitle("Chunk Feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    bulkActionsMenu
                }
            }
            .searchable(text: $searchText, prompt: "Search by chunk or document")
        }
        .frame(minWidth: 580, minHeight: 420)
        .task { await loadData() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - Subviews

    private var feedbackList: some View {
        List {
            let total = feedbackRecords.count
            let boostedCount = feedbackRecords.filter { $0.feedbackType == .boost }.count
            let hiddenCount  = feedbackRecords.filter { $0.feedbackType == .hide  }.count
            Section {
                HStack(spacing: 16) {
                    Label("\(total) total", systemImage: "number.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Label("\(boostedCount) boosted", systemImage: "hand.thumbsup.fill")
                        .font(.caption).foregroundStyle(.green)
                    Label("\(hiddenCount) hidden", systemImage: "eye.slash.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Summary")
            }

            ForEach(groupedBySource, id: \.path) { group in
                Section(URL(fileURLWithPath: group.path).lastPathComponent) {
                    ForEach(group.records) { record in
                        feedbackRow(record)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func feedbackRow(_ record: ChunkFeedback) -> some View {
        HStack(spacing: 10) {
            feedbackPill(record.feedbackType)

            VStack(alignment: .leading, spacing: 2) {
                let title = chunkTitles[record.chunkId]
                Text(title ?? "(orphaned chunk)")
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(title == nil ? .secondary : .primary)
                Text(record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toggle boost ↔ hide
            Button {
                let next: FeedbackType = record.feedbackType == .boost ? .hide : .boost
                Task { await applyFeedback(chunkId: record.chunkId, type: next) }
            } label: {
                Image(systemName: record.feedbackType == .boost
                      ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(record.feedbackType == .boost ? "Switch to Hidden" : "Switch to Boosted")

            // Clear
            Button {
                Task { await applyFeedback(chunkId: record.chunkId, type: .neutral) }
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear feedback (revert to neutral 1.0×)")
        }
        .padding(.vertical, 2)
    }

    private func feedbackPill(_ type: FeedbackType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: type == .boost ? "hand.thumbsup.fill" : "eye.slash.fill")
                .font(.caption2)
            Text(type.displayName)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(type == .boost ? Color.green : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (type == .boost ? Color.green : Color.secondary).opacity(0.1),
            in: .capsule
        )
        .frame(width: 90)
    }

    private var bulkActionsMenu: some View {
        Menu {
            Button("Clear All Feedback", role: .destructive) {
                Task { await clearByType(nil) }
            }
            Divider()
            Button("Clear Boosts Only") {
                Task { await clearByType(.boost) }
            }
            Button("Clear Hidden Only") {
                Task { await clearByType(.hide) }
            }
        } label: {
            Label("Bulk Actions", systemImage: "ellipsis.circle")
        }
        .disabled(feedbackRecords.isEmpty)
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        do {
            try await database.connect()
            let records = try await database.allFeedback()
            let ids = records.map(\.chunkId)
            let titles = try await database.chunkTitles(for: ids)
            feedbackRecords = records
            chunkTitles = titles
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyFeedback(chunkId: String, type: FeedbackType) async {
        do {
            try await database.setChunkFeedback(chunkId: chunkId, type: type)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearByType(_ type: FeedbackType?) async {
        let targets = type == nil ? feedbackRecords : feedbackRecords.filter { $0.feedbackType == type }
        do {
            for record in targets {
                try await database.setChunkFeedback(chunkId: record.chunkId, type: .neutral)
            }
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
