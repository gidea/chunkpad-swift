import SwiftUI

// MARK: - Skipped Files Banner

/// Banner showing files that could not be parsed, with per-file retry buttons.
struct SkippedFilesBanner: View {
    let files: [(url: URL, reason: String)]
    var onRetry: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text("\(files.count) file\(files.count == 1 ? "" : "s") could not be parsed")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            ForEach(files, id: \.url) { skipped in
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skipped.url.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(skipped.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Retry") {
                        onRetry(skipped.url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }
}

// MARK: - Inaccessible Folder Banner

/// Banner shown when a previously indexed folder is no longer accessible.
struct InaccessibleFolderBanner: View {
    let folder: IndexedFolder
    var onReselect: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder Not Accessible")
                    .font(.caption.weight(.semibold))
                Text("\(folder.rootURL.lastPathComponent) \u{2014} access was lost. Re-select to restore or remove it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-select", action: onReselect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Remove", action: onRemove)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }
}

// MARK: - Error Banner

/// Generic error banner with optional embedding cache recovery and dismiss buttons.
struct DocumentsErrorBanner: View {
    let message: String
    let showCacheRecovery: Bool
    var onClearCache: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            if showCacheRecovery {
                Button("Clear Cache & Retry", action: onClearCache)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }
}
