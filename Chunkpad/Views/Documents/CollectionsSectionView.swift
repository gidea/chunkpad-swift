import SwiftUI

/// Sidebar section showing document collections with create/rename/delete actions.
struct CollectionsSectionView: View {
    let collections: [Collection]
    var onCreateNew: () -> Void
    var onRename: (Collection) -> Void
    var onDelete: (Collection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Label("Collections", systemImage: "folder.badge.gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCreateNew) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("New Collection")
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if collections.isEmpty {
                Text("No collections yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                ForEach(collections) { collection in
                    HStack(spacing: 10) {
                        // Colored indicator dot
                        Circle()
                            .fill(Color(hex: collection.color) ?? Color.accentColor.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(collection.name)
                            .font(.callout)
                        Spacer()
                        Text("\(collection.documentCount) doc\(collection.documentCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            onRename(collection)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            onDelete(collection)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 4)
        }
    }
}
