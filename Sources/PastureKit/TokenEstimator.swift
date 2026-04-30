import Foundation

public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        let scalars = text.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let c = scalars[i]
            if c == " " || c == "\n" || c == "\r" || c == "\t" {
                i = scalars.index(after: i)
                continue
            }
            if CharacterSet.alphanumerics.contains(c) {
                var len = 0
                while i < scalars.endIndex && CharacterSet.alphanumerics.contains(scalars[i]) {
                    len += 1
                    i = scalars.index(after: i)
                }
                count += max(1, len / 4)
            } else {
                count += 1
                i = scalars.index(after: i)
            }
        }
        return max(1, count)
    }

    public static func formatted(_ tokens: Int) -> String {
        if tokens >= 1000 {
            let k = Double(tokens) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(tokens)"
    }

    public static func estimatedCost(inputTokens: Int, outputTokens: Int, model: AIModel) -> Double {
        let inCost = Double(inputTokens) * model.inputCostPer1M / 1_000_000
        let outCost = Double(outputTokens) * model.outputCostPer1M / 1_000_000
        return inCost + outCost
    }

    public static func formattedCost(_ usd: Double) -> String {
        if usd <= 0 { return "$0.00" }
        if usd < 0.001 { return "<$0.001" }
        if usd >= 0.10 { return String(format: "~$%.2f", usd) }
        return String(format: "~$%.3f", usd)
    }
}
