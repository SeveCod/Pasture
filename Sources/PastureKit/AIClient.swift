import Foundation

public enum AIClientError: Error, LocalizedError, Sendable {
    case noAPIKey
    case invalidAPIKey
    case contextTooLarge(limit: Int, actual: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case serverError(statusCode: Int, message: String)
    case networkError(underlying: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Open Settings \u{2192} AI to add one."
        case .invalidAPIKey:
            return "Invalid API key. Check your key in Settings \u{2192} AI."
        case .contextTooLarge(let limit, let actual):
            return "Context too large: ~\(TokenEstimator.formatted(actual)) tokens exceeds model limit of \(TokenEstimator.formatted(limit))."
        case .rateLimited(let retry):
            if let retry { return "Rate limited. Try again in \(Int(retry))s." }
            return "Rate limited. Please wait and try again."
        case .timeout:
            return "Request timed out. Try a shorter context or try again."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Invalid response from API."
        }
    }
}

public actor AIClient {
    /// Shared instance so every caller (Ask mode, Settings test connection) uses
    /// the same URLSession configuration — timeouts, cache policy, retry behavior.
    public static let shared = AIClient()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    public func ask(
        question: String,
        context: String,
        model: AIModel,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        let request: URLRequest
        do {
            request = try Self.buildRequest(question: question, context: context, model: model, apiKey: apiKey)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: AIClientError?

                for attempt in 0...Self.maxRetries {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    if attempt > 0, let delay = lastError.flatMap({ self.delayForRetry(attempt: attempt, error: $0) }) {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }
                    }

                    do {
                        let (bytes, response) = try await session.bytes(for: request)

                        guard let http = response as? HTTPURLResponse else {
                            continuation.finish(throwing: AIClientError.invalidResponse)
                            return
                        }

                        if http.statusCode != 200 {
                            let error = await self.readHTTPError(statusCode: http.statusCode, bytes: bytes, response: http)
                            if Self.isRetryable(statusCode: http.statusCode) && attempt < Self.maxRetries {
                                lastError = error
                                continue
                            }
                            continuation.finish(throwing: error)
                            return
                        }

                        var buffer = SSELineBuffer()
                        for try await line in bytes.lines {
                            guard !Task.isCancelled else { break }

                            if let event = SSEParser.parse(line: line, buffer: &buffer) {
                                if let text = Self.extractDelta(from: event, provider: model.provider) {
                                    continuation.yield(text)
                                }
                                if Self.isStreamEnd(event: event, provider: model.provider) {
                                    break
                                }
                            }
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch let urlError as URLError where urlError.code == .timedOut {
                        continuation.finish(throwing: AIClientError.timeout)
                        return
                    } catch let urlError as URLError {
                        continuation.finish(throwing: AIClientError.networkError(underlying: urlError.localizedDescription))
                        return
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish(throwing: lastError ?? AIClientError.serverError(statusCode: 0, message: "Retries exhausted"))
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Single builder for both providers — the JSON body is identical; only the
    /// endpoint URL and auth headers differ per provider.
    static func buildRequest(question: String, context: String, model: AIModel, apiKey: String) throws -> URLRequest {
        var request: URLRequest
        switch model.provider {
        case .anthropic:
            request = URLRequest(url: anthropicURL)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openRouter:
            request = URLRequest(url: openRouterURL)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("Pasture", forHTTPHeaderField: "X-Title")
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let userContent = context.isEmpty ? question : "\(context)\n\n\(question)"
        let body: [String: Any] = [
            "model": model.id,
            "max_tokens": model.maxOutputTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Retry logic

    static let maxRetries = 2
    static let baseDelay: TimeInterval = 1.0
    static let maxDelay: TimeInterval = 30.0

    static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || statusCode == 529
    }

    static func retryDelay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, maxDelay)
        }
        let exponential = baseDelay * pow(2.0, Double(attempt))
        return min(exponential, maxDelay)
    }

    private func delayForRetry(attempt: Int, error: AIClientError) -> TimeInterval? {
        switch error {
        case .rateLimited(let retryAfter):
            return Self.retryDelay(attempt: attempt, retryAfter: retryAfter)
        case .serverError(let code, _) where code == 529:
            return Self.retryDelay(attempt: attempt, retryAfter: nil)
        default:
            return nil
        }
    }

    // MARK: - Response parsing

    static func extractDelta(from event: SSEEvent, provider: AIProviderKind) -> String? {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        switch provider {
        case .anthropic:
            guard let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { return nil }
            return text
        case .openRouter:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { return nil }
            return content
        }
    }

    static func isStreamEnd(event: SSEEvent, provider: AIProviderKind) -> Bool {
        switch provider {
        case .anthropic:
            return event.event == "message_stop"
        case .openRouter:
            return event.data == "[DONE]"
        }
    }

    static func mapStatusCode(_ statusCode: Int, body: String, retryAfter: TimeInterval?) -> AIClientError {
        let message = extractErrorMessage(from: body) ?? "HTTP \(statusCode)"

        switch statusCode {
        case 401: return .invalidAPIKey
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 529: return .serverError(statusCode: 529, message: "API overloaded \u{2014} try again later")
        default: return .serverError(statusCode: statusCode, message: String(message.prefix(200)))
        }
    }

    static func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }

    private func readHTTPError(statusCode: Int, bytes: URLSession.AsyncBytes, response: HTTPURLResponse) async -> AIClientError {
        var body = ""
        do {
            for try await line in bytes.lines {
                body += line
                if body.count > 2000 { break }
            }
        } catch { /* best-effort: use whatever body was read so far */ }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return Self.mapStatusCode(statusCode, body: body, retryAfter: retryAfter)
    }
}
