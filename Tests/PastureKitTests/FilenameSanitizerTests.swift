import Testing
@testable import PastureKit

@Suite("FilenameSanitizer")
struct FilenameSanitizerTests {

    @Test("Reemplaza / por -")
    func sanitizeSlash() {
        #expect(FilenameSanitizer.sanitize("path/file") == "path-file")
    }

    @Test("Elimina null bytes")
    func sanitizeNullByte() {
        #expect(FilenameSanitizer.sanitize("file\0name") == "filename")
    }

    @Test("Reemplaza : por -")
    func sanitizeColon() {
        #expect(FilenameSanitizer.sanitize("file:name") == "file-name")
    }

    @Test("Reemplaza \\ por -")
    func sanitizeBackslash() {
        #expect(FilenameSanitizer.sanitize("path\\file") == "path-file")
    }

    @Test("Elimina punto inicial")
    func sanitizeLeadingDot() {
        #expect(FilenameSanitizer.sanitize(".hidden") == "hidden")
    }

    @Test("Elimina punto final")
    func sanitizeTrailingDot() {
        #expect(FilenameSanitizer.sanitize("file.") == "file")
    }

    @Test("Elimina espacio inicial")
    func sanitizeLeadingSpace() {
        #expect(FilenameSanitizer.sanitize(" file") == "file")
    }

    @Test("Elimina espacio final")
    func sanitizeTrailingSpace() {
        #expect(FilenameSanitizer.sanitize("file ") == "file")
    }

    @Test("Multiples caracteres problematicos")
    func sanitizeMultipleProblematicCharacters() {
        #expect(FilenameSanitizer.sanitize("a/b:c\\d") == "a-b-c-d")
    }

    @Test("Solo puntos queda vacio")
    func sanitizeOnlyDots() {
        #expect(FilenameSanitizer.sanitize("...") == "")
    }

    @Test("Solo espacios queda vacio")
    func sanitizeOnlySpaces() {
        #expect(FilenameSanitizer.sanitize("   ") == "")
    }

    @Test("String vacio")
    func sanitizeEmptyString() {
        #expect(FilenameSanitizer.sanitize("") == "")
    }

    @Test("Nombre normal no cambia")
    func sanitizeNormalName() {
        #expect(FilenameSanitizer.sanitize("my-file") == "my-file")
    }

    @Test("Puntos en medio se preservan")
    func sanitizeDotsInMiddle() {
        #expect(FilenameSanitizer.sanitize("file.name.txt") == "file.name.txt")
    }

    @Test("Solo null byte queda vacio")
    func sanitizeNullByteOnly() {
        #expect(FilenameSanitizer.sanitize("\0") == "")
    }

    @Test("Path traversal: no contiene / y no empieza con punto")
    func sanitizePathTraversal() {
        let result = FilenameSanitizer.sanitize("../../../etc/passwd")
        #expect(!result.contains("/"), "No debe contener slash")
        #expect(!result.hasPrefix("."), "No debe empezar con punto")
    }
}
