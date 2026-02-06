import Foundation

/// Ollama HTTP API client for local LLM inference with streaming support.
struct OllamaClient: LLMClient, Sendable {
    let endpoint: String
    let model: String

    private var chatURL: URL {
        URL(string: "\(endpoint)/api/chat")!
    }

    // MARK: - Non-streaming

    func chat(messages: [ChatMessage]) async throws -> String {
        let body = OllamaRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            stream: false
        )

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed(errorText)
        }

        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return result.message.content
    }

    // MARK: - Streaming

    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = OllamaRequest(
                        model: model,
                        messages: messages.map { .init(role: $0.role, content: $0.content) },
                        stream: true
                    )

                    var request = URLRequest(url: chatURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw LLMError.requestFailed("Ollama not reachable at \(endpoint)")
                    }

                    // Ollama streams NDJSON (one JSON object per line)
                    if let responseStr = String(data: bytes, encoding: .utf8) {
                        let lines = responseStr.components(separatedBy: "\n")
                        for line in lines where !line.isEmpty {
                            if let data = line.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OllamaStreamChunk.self, from: data) {
                                continuation.yield(chunk.message.content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - API Types

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaResponse: Decodable {
    let message: OllamaMessage
}

private struct OllamaStreamChunk: Decodable {
    let message: OllamaMessage
    let done: Bool
}
