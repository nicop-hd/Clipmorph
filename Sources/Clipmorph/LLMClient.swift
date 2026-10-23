import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-5"
        }
    }
}

struct TransformRequest {
    var provider: ProviderKind
    var apiKey: String
    var model: String
    /// Leading part of the system prompt that stays the same across requests (the repository),
    /// sent first so providers can cache it.
    var systemPrefix: String? = nil
    var system: String
    var input: String
    /// Needed only for Claude keys that aren't scoped to a single workspace.
    var workspaceID: String? = nil
}

struct LLMError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Streams text from the chosen provider over Server-Sent Events.
enum LLMClient {
    static func stream(_ request: TransformRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw LLMError(message: "\(request.provider.displayName) error \(status): \(errorMessage(from: body))")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let text = try parse(event, provider: request.provider), !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeURLRequest(_ request: TransformRequest) throws -> URLRequest {
        var urlRequest: URLRequest
        var body: [String: Any]

        switch request.provider {
        case .anthropic:
            urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let workspaceID = request.workspaceID {
                urlRequest.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
            }
            body = [
                "model": request.model,
                "max_tokens": 16000,
                "stream": true,
                "system": anthropicSystem(request),
                "messages": [["role": "user", "content": Prompts.user(input: request.input)]],
                // Clipboard transforms are short and latency-sensitive.
                "output_config": ["effort": "low"],
            ]
            // Re-route a safety decline to a fallback model instead of returning nothing.
            if supportsServerFallback(request.model) {
                urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }

        case .openai:
            urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": request.model,
                "stream": true,
                "messages": [
                    ["role": "system", "content": [request.systemPrefix, request.system].compactMap { $0 }.joined(separator: "\n\n")],
                    ["role": "user", "content": Prompts.user(input: request.input)],
                ],
            ]
        }

        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// A plain string, or blocks with the repository marked for prompt caching.
    private static func anthropicSystem(_ request: TransformRequest) -> Any {
        guard let prefix = request.systemPrefix else { return request.system }
        return [
            ["type": "text", "text": prefix, "cache_control": ["type": "ephemeral"]],
            ["type": "text", "text": request.system],
        ]
    }

    private static func supportsServerFallback(_ model: String) -> Bool {
        ["claude-opus-5", "claude-fable-5", "claude-sonnet-5-5"].contains { model.hasPrefix($0) }
    }

    /// Returns the text carried by one SSE event, if any.
    private static func parse(_ event: [String: Any], provider: ProviderKind) throws -> String? {
        switch provider {
        case .anthropic:
            switch event["type"] as? String {
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? delta?["text"] as? String : nil
            case "message_delta":
                let delta = event["delta"] as? [String: Any]
                if delta?["stop_reason"] as? String == "refusal" {
                    throw LLMError(message: "Claude declined to transform this text.")
                }
                return nil
            case "error":
                let error = event["error"] as? [String: Any]
                throw LLMError(message: error?["message"] as? String ?? "Unknown streaming error.")
            default:
                return nil
            }

        case .openai:
            let choices = event["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            return delta?["content"] as? String
        }
    }

    private static func errorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return body.isEmpty ? "no details" : String(body.prefix(300))
        }
        return message
    }
}
