import Testing
@testable import PastureKit
import Foundation

private let anthropicModel = AIModel(
    id: "claude-test", displayName: "Test", provider: .anthropic,
    contextWindow: 200_000, inputCostPer1M: 3.0, outputCostPer1M: 15.0
)

private let openRouterModel = AIModel(
    id: "anthropic/claude-test", displayName: "Test", provider: .openRouter,
    contextWindow: 200_000, inputCostPer1M: 3.0, outputCostPer1M: 15.0
)

// MARK: - Request Building

@Suite struct AIClientRequestTests {

    @Test func anthropicRequestURL() throws {
        let req = try AIClient.buildRequest(question: "q", context: "c", model: anthropicModel, apiKey: "sk-ant")
        #expect(req.url == URL(string: "https://api.anthropic.com/v1/messages")!)
        #expect(req.httpMethod == "POST")
    }

    @Test func anthropicRequestHeaders() throws {
        let req = try AIClient.buildRequest(question: "q", context: "c", model: anthropicModel, apiKey: "sk-ant-key")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-key")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test func anthropicRequestBody() throws {
        let req = try AIClient.buildRequest(question: "what?", context: "my context", model: anthropicModel, apiKey: "key")
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "claude-test")
        #expect(json["stream"] as? Bool == true)
        #expect(json["max_tokens"] as? Int == 4096)

        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] == "user")
        let content = try #require(messages[0]["content"])
        #expect(content.contains("my context"))
        #expect(content.contains("what?"))
    }

    @Test func openRouterRequestURL() throws {
        let req = try AIClient.buildRequest(question: "q", context: "c", model: openRouterModel, apiKey: "sk-or")
        #expect(req.url == URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        #expect(req.httpMethod == "POST")
    }

    @Test func openRouterRequestHeaders() throws {
        let req = try AIClient.buildRequest(question: "q", context: "c", model: openRouterModel, apiKey: "sk-or-key")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-key")
        #expect(req.value(forHTTPHeaderField: "X-Title") == "Pasture")
        #expect(req.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test func openRouterRequestBody() throws {
        let req = try AIClient.buildRequest(question: "q", context: "c", model: openRouterModel, apiKey: "key")
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "anthropic/claude-test")
        #expect(json["stream"] as? Bool == true)
        #expect(json.keys.contains("max_tokens") == false)
    }
}

// MARK: - Extract Delta

@Suite struct AIClientExtractDeltaTests {

    @Test func anthropicTextDelta() {
        let event = SSEEvent(event: "content_block_delta", data: #"{"delta":{"text":"hello"}}"#)
        #expect(AIClient.extractDelta(from: event, provider: .anthropic) == "hello")
    }

    @Test func anthropicNonTextEvent() {
        let event = SSEEvent(event: "message_start", data: #"{"type":"message_start"}"#)
        #expect(AIClient.extractDelta(from: event, provider: .anthropic) == nil)
    }

    @Test func openRouterContentDelta() {
        let event = SSEEvent(event: nil, data: #"{"choices":[{"delta":{"content":"world"}}]}"#)
        #expect(AIClient.extractDelta(from: event, provider: .openRouter) == "world")
    }

    @Test func openRouterDoneSignal() {
        let event = SSEEvent(event: nil, data: "[DONE]")
        #expect(AIClient.extractDelta(from: event, provider: .openRouter) == nil)
    }

    @Test func invalidJSON() {
        let event = SSEEvent(event: nil, data: "not json")
        #expect(AIClient.extractDelta(from: event, provider: .anthropic) == nil)
        #expect(AIClient.extractDelta(from: event, provider: .openRouter) == nil)
    }

    @Test func emptyChoices() {
        let event = SSEEvent(event: nil, data: #"{"choices":[]}"#)
        #expect(AIClient.extractDelta(from: event, provider: .openRouter) == nil)
    }

    @Test func anthropicMissingDeltaKey() {
        let event = SSEEvent(event: "content_block_delta", data: #"{"other":"value"}"#)
        #expect(AIClient.extractDelta(from: event, provider: .anthropic) == nil)
    }

    @Test func openRouterMissingContentKey() {
        let event = SSEEvent(event: nil, data: #"{"choices":[{"delta":{"role":"assistant"}}]}"#)
        #expect(AIClient.extractDelta(from: event, provider: .openRouter) == nil)
    }
}

// MARK: - Stream End Detection

@Suite struct AIClientStreamEndTests {

    @Test func anthropicMessageStop() {
        let event = SSEEvent(event: "message_stop", data: #"{"type":"message_stop"}"#)
        #expect(AIClient.isStreamEnd(event: event, provider: .anthropic) == true)
    }

    @Test func anthropicOtherEvent() {
        let event = SSEEvent(event: "content_block_delta", data: #"{"delta":{"text":"x"}}"#)
        #expect(AIClient.isStreamEnd(event: event, provider: .anthropic) == false)
    }

    @Test func openRouterDone() {
        let event = SSEEvent(event: nil, data: "[DONE]")
        #expect(AIClient.isStreamEnd(event: event, provider: .openRouter) == true)
    }

    @Test func openRouterNotDone() {
        let event = SSEEvent(event: nil, data: #"{"choices":[{"delta":{"content":"x"}}]}"#)
        #expect(AIClient.isStreamEnd(event: event, provider: .openRouter) == false)
    }

    @Test func anthropicNilEvent() {
        let event = SSEEvent(event: nil, data: "")
        #expect(AIClient.isStreamEnd(event: event, provider: .anthropic) == false)
    }
}

// MARK: - HTTP Error Mapping

@Suite struct AIClientErrorMappingTests {

    @Test func status401MapsToInvalidAPIKey() {
        let error = AIClient.mapStatusCode(401, body: "", retryAfter: nil)
        guard case .invalidAPIKey = error else {
            Issue.record("Expected invalidAPIKey, got \(error)")
            return
        }
    }

    @Test func status429WithRetryAfter() {
        let error = AIClient.mapStatusCode(429, body: "", retryAfter: 30)
        guard case .rateLimited(let retry) = error else {
            Issue.record("Expected rateLimited, got \(error)")
            return
        }
        #expect(retry == 30)
    }

    @Test func status429WithoutRetryAfter() {
        let error = AIClient.mapStatusCode(429, body: "", retryAfter: nil)
        guard case .rateLimited(let retry) = error else {
            Issue.record("Expected rateLimited, got \(error)")
            return
        }
        #expect(retry == nil)
    }

    @Test func status529Overloaded() {
        let error = AIClient.mapStatusCode(529, body: "", retryAfter: nil)
        guard case .serverError(let code, let msg) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(code == 529)
        #expect(msg.contains("overloaded"))
    }

    @Test func status500WithJSONErrorMessage() {
        let body = #"{"error":{"message":"Internal server error"}}"#
        let error = AIClient.mapStatusCode(500, body: body, retryAfter: nil)
        guard case .serverError(let code, let msg) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(code == 500)
        #expect(msg == "Internal server error")
    }

    @Test func status500PlainTextFallback() {
        let error = AIClient.mapStatusCode(500, body: "not json", retryAfter: nil)
        guard case .serverError(let code, let msg) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(code == 500)
        #expect(msg == "HTTP 500")
    }

    @Test func longErrorMessageTruncated() {
        let longMessage = String(repeating: "x", count: 300)
        let body = #"{"error":{"message":"\#(longMessage)"}}"#
        let error = AIClient.mapStatusCode(500, body: body, retryAfter: nil)
        guard case .serverError(_, let msg) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(msg.count <= 200)
    }
}

// MARK: - Error Message Extraction

@Suite struct AIClientErrorExtractionTests {

    @Test func extractsMessageFromJSON() {
        let body = #"{"error":{"message":"Something went wrong"}}"#
        #expect(AIClient.extractErrorMessage(from: body) == "Something went wrong")
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(AIClient.extractErrorMessage(from: "not json") == nil)
    }

    @Test func returnsNilForMissingErrorKey() {
        #expect(AIClient.extractErrorMessage(from: #"{"status":"error"}"#) == nil)
    }

    @Test func returnsNilForMissingMessageKey() {
        #expect(AIClient.extractErrorMessage(from: #"{"error":{"code":500}}"#) == nil)
    }

    @Test func returnsNilForEmptyString() {
        #expect(AIClient.extractErrorMessage(from: "") == nil)
    }
}

// MARK: - Error Descriptions

@Suite struct AIClientErrorDescriptionTests {

    @Test func allErrorCasesHaveDescriptions() {
        #expect(AIClientError.noAPIKey.localizedDescription.contains("Settings"))
        #expect(AIClientError.invalidAPIKey.localizedDescription.contains("Invalid"))
        #expect(AIClientError.timeout.localizedDescription.contains("timed out"))
        #expect(AIClientError.invalidResponse.localizedDescription.contains("Invalid"))

        let contextErr = AIClientError.contextTooLarge(limit: 200_000, actual: 300_000)
        #expect(contextErr.localizedDescription.contains("300.0k"))
        #expect(contextErr.localizedDescription.contains("200.0k"))

        let rateErr = AIClientError.rateLimited(retryAfter: 30)
        #expect(rateErr.localizedDescription.contains("30"))

        let rateErrNil = AIClientError.rateLimited(retryAfter: nil)
        #expect(rateErrNil.localizedDescription.contains("wait"))

        let serverErr = AIClientError.serverError(statusCode: 500, message: "boom")
        #expect(serverErr.localizedDescription.contains("500"))
        #expect(serverErr.localizedDescription.contains("boom"))

        let netErr = AIClientError.networkError(underlying: "no internet")
        #expect(netErr.localizedDescription.contains("no internet"))
    }
}

// MARK: - Retry Logic

@Suite("Retry Logic")
struct RetryLogicTests {

    @Test("429 is retryable")
    func retryable429() {
        #expect(AIClient.isRetryable(statusCode: 429))
    }

    @Test("529 is retryable")
    func retryable529() {
        #expect(AIClient.isRetryable(statusCode: 529))
    }

    @Test("401 is not retryable")
    func notRetryable401() {
        #expect(!AIClient.isRetryable(statusCode: 401))
    }

    @Test("500 is not retryable")
    func notRetryable500() {
        #expect(!AIClient.isRetryable(statusCode: 500))
    }

    @Test("200 is not retryable")
    func notRetryable200() {
        #expect(!AIClient.isRetryable(statusCode: 200))
    }

    @Test("Retry delay uses retryAfter when provided")
    func retryDelayWithRetryAfter() {
        let delay = AIClient.retryDelay(attempt: 0, retryAfter: 5.0)
        #expect(delay == 5.0)
    }

    @Test("Retry delay caps retryAfter at maxDelay")
    func retryDelayCapsRetryAfter() {
        let delay = AIClient.retryDelay(attempt: 0, retryAfter: 60.0)
        #expect(delay == AIClient.maxDelay)
    }

    @Test("Retry delay uses exponential backoff without retryAfter")
    func retryDelayExponentialBackoff() {
        let d0 = AIClient.retryDelay(attempt: 0, retryAfter: nil)
        let d1 = AIClient.retryDelay(attempt: 1, retryAfter: nil)
        let d2 = AIClient.retryDelay(attempt: 2, retryAfter: nil)
        #expect(d0 == AIClient.baseDelay)
        #expect(d1 == AIClient.baseDelay * 2)
        #expect(d2 == AIClient.baseDelay * 4)
    }

    @Test("Retry delay caps exponential at maxDelay")
    func retryDelayCapsExponential() {
        let delay = AIClient.retryDelay(attempt: 10, retryAfter: nil)
        #expect(delay == AIClient.maxDelay)
    }

    @Test("Retry delay ignores zero retryAfter")
    func retryDelayIgnoresZero() {
        let delay = AIClient.retryDelay(attempt: 1, retryAfter: 0)
        #expect(delay == AIClient.baseDelay * 2)
    }

    @Test("Retry delay ignores negative retryAfter")
    func retryDelayIgnoresNegative() {
        let delay = AIClient.retryDelay(attempt: 0, retryAfter: -5)
        #expect(delay == AIClient.baseDelay)
    }

    @Test("Max retries is 2")
    func maxRetriesValue() {
        #expect(AIClient.maxRetries == 2)
    }
}
