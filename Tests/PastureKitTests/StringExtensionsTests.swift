import Testing
@testable import PastureKit

@Suite("String.xmlEscapedAttribute")
struct StringExtensionsTests {

    @Test("Escapa ampersand &")
    func escapeAmpersand() {
        #expect("A&B".xmlEscapedAttribute == "A&amp;B")
    }

    @Test("Escapa menor que <")
    func escapeLessThan() {
        #expect("A<B".xmlEscapedAttribute == "A&lt;B")
    }

    @Test("Escapa mayor que >")
    func escapeGreaterThan() {
        #expect("A>B".xmlEscapedAttribute == "A&gt;B")
    }

    @Test("Escapa comillas dobles")
    func escapeDoubleQuote() {
        #expect("A\"B".xmlEscapedAttribute == "A&quot;B")
    }

    @Test("Escapa comillas simples")
    func escapeSingleQuote() {
        #expect("A'B".xmlEscapedAttribute == "A&apos;B")
    }

    @Test("Escapa todos los caracteres especiales combinados")
    func escapeAllSpecialCharacters() {
        let input = "<tag attr=\"val\" other='val2'>&amp;"
        let expected = "&lt;tag attr=&quot;val&quot; other=&apos;val2&apos;&gt;&amp;amp;"
        #expect(input.xmlEscapedAttribute == expected)
    }

    @Test("String vacio no cambia")
    func escapeEmptyString() {
        #expect("".xmlEscapedAttribute == "")
    }

    @Test("String sin caracteres especiales no cambia")
    func escapeNoSpecialCharacters() {
        let input = "Hello World 123"
        #expect(input.xmlEscapedAttribute == input)
    }

    @Test("Multiples ampersands")
    func escapeMultipleAmpersands() {
        #expect("&&&".xmlEscapedAttribute == "&amp;&amp;&amp;")
    }

    @Test("Orden de escape: & se procesa primero que <")
    func escapeOrderMatters() {
        // El & debe escaparse PRIMERO, para no doble-escapar los & de las entidades
        #expect("&<".xmlEscapedAttribute == "&amp;&lt;")
    }

    @Test("Nombre de archivo con caracteres especiales")
    func escapeFilenameWithSpecialChars() {
        let filename = "file<name>.md"
        #expect(filename.xmlEscapedAttribute == "file&lt;name&gt;.md")
    }
}
