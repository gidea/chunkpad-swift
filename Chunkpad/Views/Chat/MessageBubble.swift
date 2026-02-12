import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var assistantIcon: String {
        // Distinguish cloud vs local responses via the message metadata
        // For now, use a generic assistant icon; Phase 4 will set provider info per message
        "sparkles"
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                Label(
                    message.role == .user ? "You" : "Assistant",
                    systemImage: message.role == .user ? "person.circle" : assistantIcon
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                // Message content
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background {
                        if message.role == .user {
                            RoundedRectangle(cornerRadius: GlassTokens.Radius.card)
                                .fill(.tint.opacity(0.15))
                                .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: GlassTokens.Radius.card))
                        } else {
                            RoundedRectangle(cornerRadius: GlassTokens.Radius.card)
                                .fill(.clear)
                                .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.card))
                        }
                    }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}
