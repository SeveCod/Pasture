import Testing
@testable import PastureKit

@Suite struct ContextBuilderTests {

    @Test func emptyFilesReturnsEmptyString() {
        #expect(ContextBuilder.build(files: []) == "")
    }

    @Test func singleFileWrapsInContextTag() {
        let entry = ContextBuilder.FileEntry(name: "notes", content: "Hello world")
        let result = ContextBuilder.build(files: [entry])
        #expect(result.contains("<context name=\"notes.md\">"))
        #expect(result.contains("<![CDATA[Hello world]]>"))
        #expect(result.contains("</context>"))
        #expect(!result.contains("<documents>"))
    }

    @Test func multipleFilesWrapsInDocuments() {
        let files = [
            ContextBuilder.FileEntry(name: "a", content: "aaa"),
            ContextBuilder.FileEntry(name: "b", content: "bbb"),
        ]
        let result = ContextBuilder.build(files: files)
        #expect(result.hasPrefix("<documents>"))
        #expect(result.hasSuffix("</documents>"))
        #expect(result.contains("<context name=\"a.md\">"))
        #expect(result.contains("<context name=\"b.md\">"))
    }

    @Test func cdataClosingTagEscaped() {
        let entry = ContextBuilder.FileEntry(name: "tricky", content: "before ]]> after")
        let result = ContextBuilder.build(files: [entry])
        #expect(!result.contains("before ]]> after"))
        #expect(result.contains("]]]]><![CDATA[>"))
    }

    @Test func specialCharsInNameEscaped() {
        let entry = ContextBuilder.FileEntry(name: "file\"with&quotes", content: "x")
        let result = ContextBuilder.build(files: [entry])
        #expect(result.contains("&quot;"))
        #expect(result.contains("&amp;"))
    }

    @Test func contextTagFormat() {
        let tag = ContextBuilder.contextTag(name: "test", content: "body")
        #expect(tag == "<context name=\"test.md\">\n<![CDATA[body]]>\n</context>")
    }

    @Test func multipleFilesPreserveOrder() {
        let files = (1...5).map { ContextBuilder.FileEntry(name: "f\($0)", content: "c\($0)") }
        let result = ContextBuilder.build(files: files)
        let f1Pos = result.range(of: "f1.md")!.lowerBound
        let f5Pos = result.range(of: "f5.md")!.lowerBound
        #expect(f1Pos < f5Pos)
    }

    @Test func emptyContentStillWraps() {
        let entry = ContextBuilder.FileEntry(name: "empty", content: "")
        let result = ContextBuilder.build(files: [entry])
        #expect(result.contains("<![CDATA[]]>"))
    }

    @Test func unicodeContentPreserved() {
        let entry = ContextBuilder.FileEntry(name: "unicode", content: "Héllo wörld 🌍 日本語")
        let result = ContextBuilder.build(files: [entry])
        #expect(result.contains("Héllo wörld 🌍 日本語"))
    }
}
