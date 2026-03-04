import SwiftUI

struct MessageBubble: View {
    let message: Message
    @State private var copied = false

    private var assistantIcon: String {
        // Distinguish cloud vs local responses via the message metadata
        // For now, use a generic assistant icon; Phase 4 will set provider info per message
        "sparkles"
    }

    private func triggerCopied() {
        withAnimation(.spring(response: 0.3)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { copied = false }
        }
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
                .overlay(alignment: message.role == .user ? .topLeading : .topTrailing) {
                    // Task 15.1: "Copied" confirmation checkmark
                    if copied {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contextMenu {
                    if message.role == .assistant {
                        Button {
                            MessageExporter.copyMarkdown(message.content)
                            triggerCopied()
                        } label: {
                            Label("Copy as Markdown", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            MessageExporter.copyPlainText(message.content)
                            triggerCopied()
                        } label: {
                            Label("Copy as Plain Text", systemImage: "doc.plaintext")
                        }
                    } else {
                        Button {
                            MessageExporter.copyPlainText(message.content)
                            triggerCopied()
                        } label: {
                            Label("Copy", systemImage: "doc.on.clipboard")
                        }
                    }
                }
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

// MARK: - MessageExporter (Task 15.1)

/// Static helpers for copying and formatting message content.
/// Shared by MessageBubble (15.1) and ChatView export actions (15.2).
enum MessageExporter {

    // MARK: Clipboard

    /// Copies raw markdown content to the system clipboard.
    static func copyMarkdown(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
    }

    /// Strips markdown formatting and copies plain text to the clipboard.
    static func copyPlainText(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(stripMarkdown(content), forType: .string)
    }

    /// Formats all messages as a simple plain-text transcript and copies to clipboard.
    /// Role headings use "[You]" / "[Assistant]" with timestamps (Task 15.2).
    static func copyConversation(_ messages: [Message]) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        var output = ""
        for message in messages {
            let role = message.role == .user ? "You" : "Assistant"
            let ts = df.string(from: message.timestamp)
            output += "[\(role) — \(ts)]\n\n\(message.content)\n\n---\n\n"
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(output.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
    }

    // MARK: Formatting

    /// Strips common markdown syntax, returning plain readable text.
    static func stripMarkdown(_ text: String) -> String {
        var result = text
        // ATX headings: ## Title → Title
        result = result.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#,
                                             with: "", options: .regularExpression)
        // Bold / italic: **text** or *text* → text
        result = result.replacingOccurrences(of: #"\*{1,2}([^*\n]+)\*{1,2}"#,
                                             with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_{1,2}([^_\n]+)_{1,2}"#,
                                             with: "$1", options: .regularExpression)
        // Inline code: `code` → code
        result = result.replacingOccurrences(of: #"`([^`\n]+)`"#,
                                             with: "$1", options: .regularExpression)
        // Markdown links: [label](url) → label
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#,
                                             with: "$1", options: .regularExpression)
        // Code fences
        result = result.replacingOccurrences(of: #"```[a-z]*\n?"#,
                                             with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
