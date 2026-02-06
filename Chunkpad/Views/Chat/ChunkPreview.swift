import SwiftUI

struct ChunkPreview: View {
    let chunk: Chunk
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(chunk.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 3)

            Text(chunk.sourcePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            Text(chunk.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer()

            if let slideNumber = chunk.slideNumber {
                Text("Slide \(slideNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .font(.caption)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }
}
