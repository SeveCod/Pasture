import Testing
import Foundation
@testable import PastureKit

/// Memoria viva (v1.7, Fase A) — parser de frontmatter tolerante.
@Suite struct FrontmatterParserTests {

    private func date(_ iso: String) -> Date? { FrontmatterParser.parseDate(iso) }

    // MARK: — AC#1: parseo feliz con claves tipadas + body sin bloque

    @Test func parsesTypedKeysAndStripsBlock() {
        let content = "---\nreview_after: 2026-01-01\nttl: 90d\nlast_reviewed: 2025-12-01\n---\ncuerpo real"
        let result = FrontmatterParser.parse(content)
        let fm = try! #require(result.frontmatter)
        #expect(fm.reviewAfter == date("2026-01-01"))
        #expect(fm.ttlDays == 90)
        #expect(fm.lastReviewed == date("2025-12-01"))
        #expect(result.body == "cuerpo real")
    }

    @Test func ttlAcceptsPlainNumberAndDSuffix() {
        #expect(FrontmatterParser.parseTTLDays("90") == 90)
        #expect(FrontmatterParser.parseTTLDays("90d") == 90)
        #expect(FrontmatterParser.parseTTLDays("0") == nil)     // no positivo
        #expect(FrontmatterParser.parseTTLDays("abc") == nil)   // basura
    }

    @Test func parsesGeneratedAndSource() {
        let content = "---\ngenerated: true\nsource: ~/Docs/proyecto\n---\nx"
        let fm = try! #require(FrontmatterParser.parse(content).frontmatter)
        #expect(fm.generated)
        #expect(fm.source == "~/Docs/proyecto")
        #expect(!fm.declaresExpiry)   // sin review_after/ttl
    }

    // MARK: — AC#2: degenerados no lanzan y degradan a 'sin metadatos'

    @Test func unclosedDelimiterIsNotFrontmatter() {
        let content = "---\nreview_after: 2026-01-01\ncuerpo sin cierre"
        let result = FrontmatterParser.parse(content)
        #expect(result.frontmatter == nil)
        #expect(result.body == content)
    }

    @Test func garbageDateIsIgnored() {
        let content = "---\nreview_after: no-es-fecha\nttl: xx\n---\ncuerpo"
        let fm = try! #require(FrontmatterParser.parse(content).frontmatter)
        #expect(fm.reviewAfter == nil)
        #expect(fm.ttlDays == nil)
        #expect(!fm.declaresExpiry)
    }

    @Test func unknownKeysAreIgnored() {
        let content = "---\nfoo: bar\nreview_after: 2026-01-01\n---\nc"
        let fm = try! #require(FrontmatterParser.parse(content).frontmatter)
        #expect(fm.reviewAfter == date("2026-01-01"))
    }

    @Test func duplicateKeyFirstWins() {
        let content = "---\nttl: 30\nttl: 90\n---\nc"
        let fm = try! #require(FrontmatterParser.parse(content).frontmatter)
        #expect(fm.ttlDays == 30)
    }

    @Test func oversizedBlockIsIgnored() {
        // Bloque sin cierre y enorme → se abandona por el cap, sin colgarse.
        let filler = String(repeating: "k: v\n", count: 5_000)
        let content = "---\n" + filler + "cuerpo"
        let result = FrontmatterParser.parse(content)
        #expect(result.frontmatter == nil)
        #expect(result.body == content)
    }

    @Test func noFrontmatterReturnsContentUnchanged() {
        let content = "# Solo un título\nsin frontmatter"
        let result = FrontmatterParser.parse(content)
        #expect(result.frontmatter == nil)
        #expect(result.body == content)
    }

    @Test func crlfDelimiterIsHandled() {
        let content = "---\r\nttl: 45\r\n---\r\ncuerpo\r\ncon crlf"
        let result = FrontmatterParser.parse(content)
        let fm = try! #require(result.frontmatter)
        #expect(fm.ttlDays == 45)
    }

    @Test func emptyFrontmatterBlockYieldsNoMetadata() {
        let content = "---\n---\ncuerpo"
        let result = FrontmatterParser.parse(content)
        let fm = try! #require(result.frontmatter)
        #expect(!fm.declaresExpiry)
        #expect(result.body == "cuerpo")
    }
}
