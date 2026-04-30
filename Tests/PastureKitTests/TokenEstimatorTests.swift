import Testing
@testable import PastureKit

@Suite("TokenEstimator")
struct TokenEstimatorTests {

    // MARK: - estimate

    @Test("String vacio devuelve 0")
    func estimateEmptyString() {
        #expect(TokenEstimator.estimate("") == 0)
    }

    @Test("ASCII corto (2 chars)")
    func estimateShortASCII() {
        // "Hi" = 2 chars alphanumeric, len/4 = 0 -> max(1, 0) = 1
        #expect(TokenEstimator.estimate("Hi") == 1)
    }

    @Test("Un solo caracter")
    func estimateSingleCharacter() {
        // "A" = 1 char, len/4 = 0 -> max(1, 0) = 1
        #expect(TokenEstimator.estimate("A") == 1)
    }

    @Test("Palabra de 4 caracteres")
    func estimateFourCharWord() {
        // "word" = 4 chars, len/4 = 1 -> max(1, 1) = 1
        #expect(TokenEstimator.estimate("word") == 1)
    }

    @Test("Texto largo (16 chars alfanumericos)")
    func estimateLongText() {
        // "abcdefghijklmnop" = 16 chars, len/4 = 4 -> max(1, 4) = 4
        #expect(TokenEstimator.estimate("abcdefghijklmnop") == 4)
    }

    @Test("Solo whitespace devuelve 1")
    func estimateOnlyWhitespace() {
        // Solo espacios/tabs/newlines => count queda en 0, pero guard !text.isEmpty pasa
        // Al final: max(1, 0) = 1
        #expect(TokenEstimator.estimate("   \t\n  ") == 1)
    }

    @Test("Caracteres especiales cuentan 1 cada uno")
    func estimateSpecialCharacters() {
        // "!@#" = 3 special chars => count = 3
        #expect(TokenEstimator.estimate("!@#") == 3)
    }

    @Test("Contenido mixto: palabras + puntuacion")
    func estimateMixedContent() {
        // "Hello World!" = "Hello"(5/4=1) + " "(skip) + "World"(5/4=1) + "!"(1) = 3
        #expect(TokenEstimator.estimate("Hello World!") == 3)
    }

    @Test("Siempre devuelve al menos 1 para string no vacio")
    func estimateReturnsAtLeastOne() {
        #expect(TokenEstimator.estimate("x") >= 1)
        #expect(TokenEstimator.estimate(" ") >= 1)
    }

    // MARK: - formatted

    @Test("999 se muestra como entero")
    func formattedUnderThousand() {
        #expect(TokenEstimator.formatted(999) == "999")
    }

    @Test("1000 se muestra como 1.0k")
    func formattedExactlyThousand() {
        #expect(TokenEstimator.formatted(1000) == "1.0k")
    }

    @Test("1500 se muestra como 1.5k")
    func formattedFifteenHundred() {
        #expect(TokenEstimator.formatted(1500) == "1.5k")
    }

    @Test("10000 se muestra como 10.0k")
    func formattedTenThousand() {
        #expect(TokenEstimator.formatted(10000) == "10.0k")
    }

    @Test("0 se muestra como 0")
    func formattedZero() {
        #expect(TokenEstimator.formatted(0) == "0")
    }

    @Test("1 se muestra como 1")
    func formattedOne() {
        #expect(TokenEstimator.formatted(1) == "1")
    }

    @Test("128000 se muestra como 128.0k")
    func formattedLargeNumber() {
        #expect(TokenEstimator.formatted(128000) == "128.0k")
    }

    // MARK: - estimatedCost

    @Test("Zero tokens cost is zero")
    func estimatedCostZero() {
        let model = AIModel(id: "test", displayName: "Test", provider: .anthropic,
                            contextWindow: 200_000, inputCostPer1M: 3.0, outputCostPer1M: 15.0)
        let cost = TokenEstimator.estimatedCost(inputTokens: 0, outputTokens: 0, model: model)
        #expect(cost == 0.0)
    }

    @Test("Cost calculation is correct")
    func estimatedCostCalculation() {
        let model = AIModel(id: "test", displayName: "Test", provider: .anthropic,
                            contextWindow: 200_000, inputCostPer1M: 3.0, outputCostPer1M: 15.0)
        let cost = TokenEstimator.estimatedCost(inputTokens: 1_000_000, outputTokens: 1_000_000, model: model)
        #expect(cost == 18.0)
    }

    // MARK: - formattedCost

    @Test("Zero cost formatted as $0.00")
    func formattedCostZero() {
        #expect(TokenEstimator.formattedCost(0) == "$0.00")
    }

    @Test("Very small cost formatted as <$0.001")
    func formattedCostTiny() {
        #expect(TokenEstimator.formattedCost(0.0001) == "<$0.001")
    }

    @Test("Normal cost formatted with 3 decimals")
    func formattedCostNormal() {
        #expect(TokenEstimator.formattedCost(0.003) == "~$0.003")
    }

    @Test("Large cost formatted with 2 decimals")
    func formattedCostLarge() {
        #expect(TokenEstimator.formattedCost(0.15) == "~$0.15")
    }
}
