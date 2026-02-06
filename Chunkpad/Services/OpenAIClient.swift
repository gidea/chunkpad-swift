import Foundation

/// OpenAI Chat Completions API client with streaming support.
struct OpenAIClient: LLMClient, Sendable {
    let apiKey: String
    let model: String

    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Non-streaming

    func chat(messages: [ChatMessage]) async throws -> String {
        let body = OpenAIRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            stream: false
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed(errorText)
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }

    // MARK: - Streaming

    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = OpenAIRequest(
                        model: model,
                        messages: messages.map { .init(role: $0.role, content: $0.content) },
                        stream: true
                    )

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                           let event = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                           let text = event.choices.first?.delta.content {
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
}

// MARK: - API Types

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: OpenAIMessage
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [StreamChoice]
    struct StreamChoice: Decodable {
        let delta: Delta
    }
    struct Delta: Decodable {
        let content: String?
    }
}
