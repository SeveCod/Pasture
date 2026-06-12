import Testing
@testable import PastureKit

/// F3 — Aviso de límite de contexto. Lógica pura del estado binario (ADR-004):
/// el aviso salta al EXCEDER, no al acercarse. Sin modelo, no hay denominador.
@Suite("ContextLimit")
struct ContextLimitTests {

    @Test("No window (nil) => no denominator, never exceeds")
    func noWindow() {
        let state = ContextLimit.state(totalTokens: 999_999, contextWindow: nil)
        #expect(state.contextWindow == nil)
        #expect(state.exceeds == false)
    }

    @Test("Window of 0 is treated as no denominator")
    func zeroWindow() {
        let state = ContextLimit.state(totalTokens: 100, contextWindow: 0)
        #expect(state.contextWindow == nil)
        #expect(state.exceeds == false)
    }

    @Test("Under the limit does not exceed")
    func underLimit() {
        let state = ContextLimit.state(totalTokens: 15_000, contextWindow: 200_000)
        #expect(state.contextWindow == 200_000)
        #expect(state.exceeds == false)
    }

    @Test("Exactly at the limit does not exceed (binary: only when over)")
    func atLimit() {
        let state = ContextLimit.state(totalTokens: 200_000, contextWindow: 200_000)
        #expect(state.exceeds == false)
    }

    @Test("Just below the limit does not exceed (199k / 200k)")
    func justBelow() {
        let state = ContextLimit.state(totalTokens: 199_000, contextWindow: 200_000)
        #expect(state.exceeds == false)
    }

    @Test("Over the limit exceeds")
    func overLimit() {
        let state = ContextLimit.state(totalTokens: 250_000, contextWindow: 200_000)
        #expect(state.exceeds == true)
    }
}
