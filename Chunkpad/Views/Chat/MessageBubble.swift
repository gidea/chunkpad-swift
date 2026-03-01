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
                Group {
                    if message.role == .assistant {
                        MarkdownContentView(content: message.content)
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                    }
                }
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

// MARK: - Markdown Content View

/// Renders markdown content with support for fenced code blocks.
/// Text segments use SwiftUI's built-in markdown parsing (bold, italic, inline code, links).
/// Fenced code blocks render in monospace with a distinct background.
private struct MarkdownContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(markdownAttributedString(from: text))
                        .textSelection(.enabled)
                case .code(let language, let code):
                    VStack(alignment: .leading, spacing: 4) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Segment Parsing

    private enum Segment {
        case text(String)
        case code(language: String, content: String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        let lines = content.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""
        var codeLines: [String] = []

        for line in lines {
            if !inCodeBlock && line.hasPrefix("```") {
                // Flush accumulated text
                let text = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append(.text(text))
                }
                currentText = []
                // Start code block
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
            } else if inCodeBlock && line.hasPrefix("```") {
                // End code block
                let code = codeLines.joined(separator: "\n")
                result.append(.code(language: codeLanguage, content: code))
                inCodeBlock = false
                codeLanguage = ""
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                currentText.append(line)
            }
        }

        // Flush remaining content
        if inCodeBlock {
            // Unclosed code block — treat as text with the opening fence
            currentText.append("```\(codeLanguage)")
            currentText.append(contentsOf: codeLines)
        }
        let remaining = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            result.append(.text(remaining))
        }

        return result
    }

    /// Converts markdown text to AttributedString, falling back to plain text on failure.
    private func markdownAttributedString(from text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(text)
        }
    }
}
