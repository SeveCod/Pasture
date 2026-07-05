import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — emisor + compilación pura.
@Suite struct PackCompilerTests {

    private func entry(_ name: String, _ content: String) -> ContextBuilder.FileEntry {
        ContextBuilder.FileEntry(name: name, content: content)
    }

    // MARK: — Emisor

    @Test func emitterProducesMarkdownForBothKinds() {
        let files = [entry("rules", "Regla A")]
        let claude = PackEmitter.assemble(files: files, kind: .claudeMd)
        let agents = PackEmitter.assemble(files: files, kind: .agentsMd)
        #expect(claude.contains("## rules.md"))
        #expect(claude.contains("Regla A"))
        #expect(agents == claude)   // v1: mismo formato Markdown
    }

    // MARK: — Compile determinista (AC#1)

    @Test func compileRendersTemplateVariables() throws {
        let files = [entry("rules", "Reglas de {{PROJECT}}")]
        let result = try compileOK(name: "p", vars: ["PROJECT": "foo"], files: files)
        #expect(result.body == "## rules.md\n```\nReglas de foo\n```")
    }

    // MARK: — Idempotencia byte a byte (AC#12)

    @Test func compileIsByteIdenticalAcrossRuns() throws {
        let files = [entry("a", "uno {{V}}"), entry("b", "dos")]
        let first = try compileOK(name: "p", vars: ["V": "x"], files: files)
        let second = try compileOK(name: "p", vars: ["V": "x"], files: files)
        #expect(first.body == second.body)   // sin timestamps en el cuerpo
    }

    // MARK: — Inyección single-pass (AC#8-análogo)

    @Test func variableValueIsNotReparsedAsTemplate() throws {
        let files = [entry("f", "Hola {{NAME}}")]
        let result = try compileOK(name: "p", vars: ["NAME": "Ana {{OTHER}}"], files: files)
        #expect(result.body.contains("Hola Ana {{OTHER}}"))
        #expect(!result.body.contains("Hola Ana \n"))   // OTHER no se resolvió a vacío
    }

    // MARK: — Cap de 2 MB (AC#11)

    @Test func compileRejectsBodyOverTwoMegabytes() {
        let huge = String(repeating: "x", count: PackCompiler.maxBodyBytes + 1)
        let result = PackCompiler.compile(
            packName: "p", variables: [:], kind: .claudeMd, sourceFiles: [entry("big", huge)])
        guard case .failure(let error) = result else {
            Issue.record("esperaba fallo por tamaño")
            return
        }
        if case .tooLarge = error { } else { Issue.record("esperaba .tooLarge") }
    }

    // MARK: — Secreto post-render (AC#6)

    @Test func compileScansRenderedContentForSecrets() throws {
        let syntheticKey = "sk-ant-" + "api03-" + "abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        let files = [entry("f", "clave {{SECRET}}")]
        let result = try compileOK(name: "p", vars: ["SECRET": syntheticKey], files: files)
        #expect(result.body.contains(syntheticKey))          // contenido íntegro
        #expect(!result.secretScan.isEmpty)                  // detectado
        #expect(result.secretScan.kinds.contains(.anthropicKey))
    }

    @Test func compileOnCleanContentHasEmptyScan() throws {
        let result = try compileOK(name: "p", vars: [:], files: [entry("f", "sin secretos")])
        #expect(result.secretScan.isEmpty)
    }

    // MARK: — Helper

    private func compileOK(
        name: String, vars: [String: String], files: [ContextBuilder.FileEntry]
    ) throws -> PackCompiler.CompileResult {
        switch PackCompiler.compile(packName: name, variables: vars, kind: .claudeMd, sourceFiles: files) {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
