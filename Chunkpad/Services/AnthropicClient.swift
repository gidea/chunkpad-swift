import Foundation

/// Anthropic Messages API client with streaming support.
struct AnthropicClient: LLMClient, Sendable {
    let apiKey: String
    let model: String

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Non-streaming

    func chat(messages: [ChatMessage]) async throws -> String {
        let (systemPrompt, userMessages) = splitSystem(messages)
        let body = AnthropicRequest(
            model: model,
            max_tokens: 4096,
            system: systemPrompt,
            messages: userMessages.map { .init(role: $0.role, content: $0.content) },
            stream: false
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed(errorText)
        }

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return result.content.first?.text ?? ""
    }

    // MARK: - Streaming

    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (systemPrompt, userMessages) = splitSystem(messages)
                    let body = AnthropicRequest(
                        model: model,
                        max_tokens: 4096,
                        system: systemPrompt,
                        messages: userMessages.map { .init(role: $0.role, content: $0.content) },
                        stream: true
                    )

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw LLMError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }

                        if let data = json.data(using: .utf8),
                           let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data),
                           event.type == "content_block_delta",
                           let text = event.delta?.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func splitSystem(_ messages: [ChatMessage]) -> (String?, [ChatMessage]) {
        let system = messages.first(where: { $0.role == "system" })?.content
        let rest = messages.filter { $0.role != "system" }
        return (system, rest)
    }
}

// MARK: - API Types

private struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let text: String
    }
}

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    struct Delta: Decodable {
        let text: String?
    }
}
