import Testing
@testable import PastureKit
import AppKit
import Foundation

private func makeAttrString(_ text: String, font: NSFont = .systemFont(ofSize: 12)) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [.font: font])
}

private func makeMutableAttrString(_ text: String, font: NSFont = .systemFont(ofSize: 12)) -> NSMutableAttributedString {
    NSMutableAttributedString(string: text, attributes: [.font: font])
}

@Suite struct DOCXConverterTests {

    // MARK: - Plain text

    @Test func plainTextPassesThrough() throws {
        let attr = makeAttrString("Hello world")
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result == "Hello world")
    }

    @Test func multiParagraphText() throws {
        let attr = makeAttrString("First paragraph\n\nSecond paragraph")
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result.contains("First paragraph"))
        #expect(result.contains("Second paragraph"))
    }

    @Test func emptyDocumentThrows() {
        let attr = makeAttrString("   \n  \n  ")
        #expect(throws: DOCXConverter.ConversionError.emptyDocument) {
            try DOCXConverter.convertAttributedString(attr)
        }
    }

    @Test func completelyEmptyStringThrows() {
        let attr = makeAttrString("")
        #expect(throws: DOCXConverter.ConversionError.emptyDocument) {
            try DOCXConverter.convertAttributedString(attr)
        }
    }

    // MARK: - Bold & italic

    @Test func boldTextWrappedInDoubleAsterisks() throws {
        let boldFont = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .boldFontMask)
        let attr = makeMutableAttrString("normal ", font: .systemFont(ofSize: 12))
        attr.append(NSAttributedString(string: "bold", attributes: [.font: boldFont]))
        attr.append(NSAttributedString(string: " normal", attributes: [.font: NSFont.systemFont(ofSize: 12)]))

        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result.contains("**bold**"))
    }

    @Test func italicTextWrappedInSingleAsterisks() throws {
        let italicFont = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        let attr = makeMutableAttrString("normal ", font: .systemFont(ofSize: 12))
        attr.append(NSAttributedString(string: "italic", attributes: [.font: italicFont]))

        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result.contains("*italic*"))
    }

    @Test func boldItalicWrappedInTripleAsterisks() throws {
        let biFont = NSFontManager.shared.convert(.boldSystemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        let attr = makeMutableAttrString("normal ", font: .systemFont(ofSize: 12))
        attr.append(NSAttributedString(string: "both", attributes: [.font: biFont]))

        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result.contains("***both***"))
    }

    // MARK: - Headings

    @Test func largeFontDetectedAsH1() {
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let h1Font = NSFont.systemFont(ofSize: 24)
        let attr = makeMutableAttrString("Body text is longer than heading for weight detection purposes and more text here\n", font: bodyFont)
        attr.append(NSAttributedString(string: "Heading", attributes: [.font: h1Font]))

        let result = DOCXConverter.attributedStringToMarkdown(attr)
        #expect(result.contains("# Heading"))
    }

    @Test func mediumFontDetectedAsH2() {
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let h2Font = NSFont.systemFont(ofSize: 18)
        let attr = makeMutableAttrString("Body text is longer than heading for weight detection purposes and more text here\n", font: bodyFont)
        attr.append(NSAttributedString(string: "Subheading", attributes: [.font: h2Font]))

        let result = DOCXConverter.attributedStringToMarkdown(attr)
        #expect(result.contains("## Subheading"))
    }

    @Test func slightlyLargerBoldDetectedAsH3() {
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let h3Font = NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: .boldFontMask)
        let attr = makeMutableAttrString("Body text is longer than heading for weight detection purposes and more text here\n", font: bodyFont)
        attr.append(NSAttributedString(string: "Section", attributes: [.font: h3Font]))

        let result = DOCXConverter.attributedStringToMarkdown(attr)
        #expect(result.contains("### Section"))
    }

    @Test func headingLevelZeroForBodyRange() {
        let attr = makeAttrString("Just body text")
        let range = NSRange(location: 0, length: attr.length)
        #expect(DOCXConverter.headingLevel(attr, range: range, bodySize: 12) == 0)
    }

    @Test func headingLevelZeroForEmptyRange() {
        let attr = makeAttrString("text")
        let range = NSRange(location: 0, length: 0)
        #expect(DOCXConverter.headingLevel(attr, range: range, bodySize: 12) == 0)
    }

    // MARK: - Links

    @Test func linkFormattedAsMarkdown() throws {
        let attr = NSMutableAttributedString(string: "Click here", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .link: URL(string: "https://example.com")!,
        ])
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result == "[Click here](https://example.com)")
    }

    @Test func stringLinkFormattedAsMarkdown() throws {
        let attr = NSMutableAttributedString(string: "Link text", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .link: "https://example.org",
        ])
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result == "[Link text](https://example.org)")
    }

    // MARK: - Inline markdown helpers

    @Test func boldSuppressedInHeadings() {
        let attr = NSAttributedString(string: "Heading", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let range = NSRange(location: 0, length: attr.length)
        let md = DOCXConverter.inlineMarkdown(attr, range: range, bodySize: 12, isHeading: true)
        #expect(!md.contains("**"))
        #expect(md == "Heading")
    }

    @Test func boldNotSuppressedInBody() {
        let boldFont = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .boldFontMask)
        let attr = NSAttributedString(string: "Bold", attributes: [.font: boldFont])
        let range = NSRange(location: 0, length: attr.length)
        let md = DOCXConverter.inlineMarkdown(attr, range: range, bodySize: 12, isHeading: false)
        #expect(md == "**Bold**")
    }

    // MARK: - Whitespace collapsing

    @Test func consecutiveEmptyLinesCollapsed() throws {
        let attr = makeAttrString("First\n\n\n\nSecond")
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(!result.contains("\n\n\n"))
    }

    @Test func leadingTrailingWhitespaceTrimmed() throws {
        let attr = makeAttrString("\n\n  Hello  \n\n")
        let result = try DOCXConverter.convertAttributedString(attr)
        #expect(result == "Hello")
    }

    // MARK: - Error descriptions

    @Test func errorDescriptionsExist() {
        #expect(DOCXConverter.ConversionError.cannotReadFile.localizedDescription.contains("Cannot read"))
        #expect(DOCXConverter.ConversionError.emptyDocument.localizedDescription.contains("no extractable"))
    }

    // MARK: - File conversion error

    @Test func convertNonexistentFileThrows() {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_file_\(UUID()).docx")
        #expect(throws: (any Error).self) {
            try DOCXConverter.convert(url: fakeURL)
        }
    }
}
