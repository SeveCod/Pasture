import Foundation

/// F3 — Lógica pura del aviso de límite de contexto en el feed.
///
/// Regla binaria (ADR-004): el aviso salta solo al EXCEDER, no al acercarse.
/// Sin modelo configurado (`contextWindow == nil`), no hay denominador y nunca
/// se considera excedido — comportamiento idéntico a v1.3 (sin regresión).
public enum ContextLimit {

    public struct State: Sendable, Equatable {
        /// Denominador a mostrar (`nil` => sin modelo => sin denominador).
        public let contextWindow: Int?
        /// Verdadero solo si la selección excede el contexto del modelo.
        public let exceeds: Bool
    }

    public static func state(totalTokens: Int, contextWindow: Int?) -> State {
        guard let window = contextWindow, window > 0 else {
            return State(contextWindow: nil, exceeds: false)
        }
        return State(contextWindow: window, exceeds: totalTokens > window)
    }
}
