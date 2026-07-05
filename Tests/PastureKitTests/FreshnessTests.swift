import Testing
import Foundation
@testable import PastureKit

/// Memoria viva (v1.7, Fase A) — estado de frescura determinista (reloj inyectado).
@Suite struct FreshnessTests {

    private func d(_ iso: String) -> Date { FrontmatterParser.parseDate(iso)! }

    // MARK: — Sin caducidad declarada = siempre fresca

    @Test func noFrontmatterIsFresh() {
        #expect(Freshness.state(frontmatter: nil, reference: d("2020-01-01"), now: d("2030-01-01")) == .fresh)
    }

    @Test func frontmatterWithoutExpiryIsFresh() {
        let fm = Frontmatter(generated: true)   // sin review_after ni ttl
        #expect(Freshness.state(frontmatter: fm, reference: d("2020-01-01"), now: d("2030-01-01")) == .fresh)
    }

    // MARK: — AC#3: ttl con last_reviewed

    @Test func ttlExpiredByLastReviewed() {
        let fm = Frontmatter(ttlDays: 90, lastReviewed: d("2026-01-01"))
        // 2026-01-01 → 2026-05-01 son exactamente 120 días.
        #expect(Freshness.state(frontmatter: fm, reference: d("2000-01-01"), now: d("2026-05-01"))
                == .expired(daysSinceReview: 120))
    }

    @Test func ttlFreshWithinWindow() {
        let fm = Frontmatter(ttlDays: 90, lastReviewed: d("2026-04-01"))
        // 2026-04-01 → 2026-05-01 son 30 días (< 90).
        #expect(Freshness.state(frontmatter: fm, reference: d("2000-01-01"), now: d("2026-05-01")) == .fresh)
    }

    @Test func ttlFallsBackToReferenceWhenNoLastReviewed() {
        let fm = Frontmatter(ttlDays: 90)   // sin last_reviewed → usa reference
        #expect(Freshness.state(frontmatter: fm, reference: d("2026-01-01"), now: d("2026-05-01"))
                == .expired(daysSinceReview: 120))
    }

    // MARK: — review_after (fecha absoluta)

    @Test func reviewAfterInThePastIsExpired() {
        let fm = Frontmatter(reviewAfter: d("2026-01-01"))
        let state = Freshness.state(frontmatter: fm, reference: d("2026-04-01"), now: d("2026-05-01"))
        // Caducada; días desde la referencia (30).
        #expect(state == .expired(daysSinceReview: 30))
    }

    @Test func reviewAfterInTheFutureIsFresh() {
        let fm = Frontmatter(reviewAfter: d("2027-01-01"))
        #expect(Freshness.state(frontmatter: fm, reference: d("2026-04-01"), now: d("2026-05-01")) == .fresh)
    }

    // MARK: — daysBetween

    @Test func daysBetweenIsCalendarUTC() {
        #expect(Freshness.daysBetween(d("2026-01-01"), d("2026-05-01")) == 120)
        #expect(Freshness.daysBetween(d("2026-05-01"), d("2026-01-01")) == -120)
        #expect(Freshness.daysBetween(d("2026-05-01"), d("2026-05-01")) == 0)
    }
}
