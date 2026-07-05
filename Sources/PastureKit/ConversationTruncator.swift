import Foundation

/// Trims an Ask transcript so it fits the model's context window before sending.
///
/// Budget = `floor(0.95 * contextWindow) - maxOutputTokens` — the 5% margin
/// absorbs the heuristic error of `TokenEstimator` plus the wire overhead of the
/// JSON envelope. When over budget it drops the *oldest middle* messages one at a
/// time, but NEVER the first message (it carries the file context) nor the last
/// (the current turn). If even context + current turn exceed the budget, both are
/// still returned unchanged — the caller's pre-send guard surfaces that case.
public enum ConversationTruncator {
    public static func truncate(_ messages: [ChatMessage], model: AIModel) -> [ChatMessage] {
        guard messages.count > 2 else { return messages }

        let budget = Int(Double(model.contextWindow) * 0.95) - model.maxOutputTokens

        var result = messages
        while result.count > 2, totalTokens(result) > budget {
            result.remove(at: 1) // drop the oldest message between context and current turn
        }
        return result
    }

    private static func totalTokens(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + TokenEstimator.estimate($1.content) }
    }
}
