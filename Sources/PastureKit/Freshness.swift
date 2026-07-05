import Foundation

/// Memoria viva (v1.7, Fase A) — evalúa si una nota está fresca o caducada según
/// su frontmatter. Enum PURO `nonisolated` con reloj INYECTADO (mismo patrón que
/// `ContextLimit.state`): determinista y testeable, sin `Date()` implícito.
///
/// Regla: una nota sin caducidad declarada (ni `review_after` ni `ttl`) es
/// SIEMPRE fresca — cero regresión para vaults que no usan la feature.
public enum Freshness {

    public enum State: Sendable, Equatable {
        case fresh
        /// Caducada: días transcurridos desde la última revisión (o modificación).
        case expired(daysSinceReview: Int)
    }

    /// - Parameters:
    ///   - frontmatter: metadatos de la nota (`nil` ⇒ fresca).
    ///   - reference: fecha base cuando no hay `last_reviewed` (la de modificación).
    ///   - now: reloj inyectado.
    public static func state(frontmatter: Frontmatter?, reference: Date, now: Date) -> State {
        guard let frontmatter, frontmatter.declaresExpiry else { return .fresh }

        let base = frontmatter.lastReviewed ?? reference
        let daysSince = daysBetween(base, now)

        var expired = false
        if let ttl = frontmatter.ttlDays, daysSince > ttl { expired = true }
        if let reviewAfter = frontmatter.reviewAfter, now > reviewAfter { expired = true }

        return expired ? .expired(daysSinceReview: max(0, daysSince)) : .fresh
    }

    /// Días de calendario (UTC) entre dos fechas. Negativo si `later` < `earlier`.
    static func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
