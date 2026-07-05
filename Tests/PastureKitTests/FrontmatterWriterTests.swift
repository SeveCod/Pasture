import Testing
import Foundation
@testable import PastureKit

/// Memoria viva (v1.7, Fase A) — escritura de `last_reviewed` preservando el cuerpo.
@Suite struct FrontmatterWriterTests {

    private func d(_ iso: String) -> Date { FrontmatterParser.parseDate(iso)! }

    @Test func updatesExistingLastReviewed() {
        let content = "---\nttl: 90\nlast_reviewed: 2025-01-01\n---\ncuerpo real"
        let result = FrontmatterWriter.settingLastReviewed(in: content, to: d("2026-05-01"))
        let fm = try! #require(FrontmatterParser.parse(result).frontmatter)
        #expect(fm.lastReviewed == d("2026-05-01"))
        #expect(fm.ttlDays == 90)   // conserva el resto
        #expect(FrontmatterParser.parse(result).body == "cuerpo real")
    }

    @Test func insertsLastReviewedIntoExistingBlock() {
        let content = "---\nttl: 90\n---\ncuerpo"
        let result = FrontmatterWriter.settingLastReviewed(in: content, to: d("2026-05-01"))
        let fm = try! #require(FrontmatterParser.parse(result).frontmatter)
        #expect(fm.lastReviewed == d("2026-05-01"))
        #expect(fm.ttlDays == 90)
    }

    @Test func prependsBlockWhenNoFrontmatter() {
        let content = "# Solo cuerpo\nsin frontmatter"
        let result = FrontmatterWriter.settingLastReviewed(in: content, to: d("2026-05-01"))
        #expect(result.hasPrefix("---\nlast_reviewed: 2026-05-01\n---\n"))
        let parsed = FrontmatterParser.parse(result)
        #expect(parsed.frontmatter?.lastReviewed == d("2026-05-01"))
        #expect(parsed.body == content)
    }

    @Test func markingReviewedClearsExpiry() {
        // Una nota vencida por ttl, tras marcarla revisada hoy, vuelve a fresca.
        let content = "---\nttl: 30\nlast_reviewed: 2020-01-01\n---\nx"
        let now = d("2026-05-01")
        let updated = FrontmatterWriter.settingLastReviewed(in: content, to: now)
        let fm = try! #require(FrontmatterParser.parse(updated).frontmatter)
        #expect(Freshness.state(frontmatter: fm, reference: now, now: now) == .fresh)
    }
}
