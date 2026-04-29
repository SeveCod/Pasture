import Testing
@testable import PastureKit

@Suite("TemplateEngine")
struct TemplateEngineTests {

    // MARK: - extractVariables

    @Test("Extrae variable simple {{VAR}}")
    func extractSimpleVariable() {
        let vars = TemplateEngine.extractVariables(from: "Hello {{NAME}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "NAME")
        #expect(vars[0].defaultValue == "")
    }

    @Test("Extrae variable con default {{VAR=default}}")
    func extractVariableWithDefault() {
        let vars = TemplateEngine.extractVariables(from: "Hello {{NAME=World}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "NAME")
        #expect(vars[0].defaultValue == "World")
        #expect(vars[0].value == "World")
    }

    @Test("Extrae multiples variables")
    func extractMultipleVariables() {
        let text = "{{FIRST}} and {{SECOND=default}} and {{THIRD}}"
        let vars = TemplateEngine.extractVariables(from: text)
        #expect(vars.count == 3)
        #expect(vars[0].name == "FIRST")
        #expect(vars[1].name == "SECOND")
        #expect(vars[1].defaultValue == "default")
        #expect(vars[2].name == "THIRD")
    }

    @Test("Duplicados: primera ocurrencia gana")
    func extractDuplicatesFirstWins() {
        let text = "{{VAR=first}} and {{VAR=second}}"
        let vars = TemplateEngine.extractVariables(from: text)
        #expect(vars.count == 1, "Duplicados deben deduplicarse")
        #expect(vars[0].name == "VAR")
        #expect(vars[0].defaultValue == "first", "El default de la primera ocurrencia gana")
    }

    @Test("Nombre invalido empezando con digito: {{123}}")
    func extractInvalidNameStartingWithDigit() {
        let vars = TemplateEngine.extractVariables(from: "{{123}}")
        #expect(vars.isEmpty, "{{123}} no es un nombre valido de variable")
    }

    @Test("Llaves vacias: {{}}")
    func extractEmptyBraces() {
        let vars = TemplateEngine.extractVariables(from: "{{}}")
        #expect(vars.isEmpty, "{{}} no debe producir variables")
    }

    @Test("String vacio no produce variables")
    func extractFromEmptyString() {
        let vars = TemplateEngine.extractVariables(from: "")
        #expect(vars.isEmpty)
    }

    @Test("Texto sin templates no produce variables")
    func extractNoVariables() {
        let vars = TemplateEngine.extractVariables(from: "Just plain text with no templates")
        #expect(vars.isEmpty)
    }

    @Test("Variables con underscore son validas")
    func extractUnderscoreVariable() {
        let vars = TemplateEngine.extractVariables(from: "{{_private}} and {{__double}}")
        #expect(vars.count == 2)
        #expect(vars[0].name == "_private")
        #expect(vars[1].name == "__double")
    }

    @Test("Variable con default vacio: {{VAR=}}")
    func extractVariableWithEmptyDefault() {
        let vars = TemplateEngine.extractVariables(from: "{{VAR=}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "VAR")
        #expect(vars[0].defaultValue == "")
    }

    // MARK: - render

    @Test("Reemplazo simple de una variable")
    func renderSimpleReplacement() {
        var v = TemplateVariable(name: "NAME")
        v.value = "World"
        let result = TemplateEngine.render("Hello {{NAME}}!", with: [v])
        #expect(result == "Hello World!")
    }

    @Test("Reemplazo de multiples variables")
    func renderMultipleReplacements() {
        var first = TemplateVariable(name: "FIRST")
        first.value = "A"
        var second = TemplateVariable(name: "SECOND")
        second.value = "B"
        let result = TemplateEngine.render("{{FIRST}} and {{SECOND}}", with: [first, second])
        #expect(result == "A and B")
    }

    @Test("Render con valor default aplicado")
    func renderWithDefaultValue() {
        let v = TemplateVariable(name: "NAME", defaultValue: "Default")
        let result = TemplateEngine.render("Hello {{NAME=Default}}!", with: [v])
        #expect(result == "Hello Default!")
    }

    @Test("Variable sin match en lookup queda intacta")
    func renderVariableWithoutMatchStaysIntact() {
        let result = TemplateEngine.render("Hello {{UNKNOWN}}!", with: [])
        #expect(result == "Hello {{UNKNOWN}}!", "Sin match en lookup, el placeholder queda intacto")
    }

    @Test("Misma variable aparece multiples veces")
    func renderSameVariableMultipleTimes() {
        var v = TemplateVariable(name: "X")
        v.value = "replaced"
        let result = TemplateEngine.render("{{X}} and {{X}} again", with: [v])
        #expect(result == "replaced and replaced again")
    }

    @Test("Render de string vacio")
    func renderEmptyString() {
        let result = TemplateEngine.render("", with: [])
        #expect(result == "")
    }

    @Test("Render sin placeholders en el texto")
    func renderNoPlaceholders() {
        let result = TemplateEngine.render("Just text", with: [TemplateVariable(name: "X")])
        #expect(result == "Just text")
    }

    // MARK: - hasVariables

    @Test("hasVariables detecta placeholders")
    func hasVariablesTrue() {
        #expect(TemplateEngine.hasVariables(in: "Hello {{NAME}}"))
    }

    @Test("hasVariables retorna false sin placeholders")
    func hasVariablesFalse() {
        #expect(!TemplateEngine.hasVariables(in: "Hello World"))
    }

    @Test("hasVariables con string vacio")
    func hasVariablesEmptyString() {
        #expect(!TemplateEngine.hasVariables(in: ""))
    }

    @Test("hasVariables con placeholder invalido")
    func hasVariablesInvalidPlaceholder() {
        #expect(!TemplateEngine.hasVariables(in: "{{123}}"))
    }

    @Test("hasVariables con default value")
    func hasVariablesWithDefault() {
        #expect(TemplateEngine.hasVariables(in: "{{VAR=something}}"))
    }

    // MARK: - #if blocks

    @Test("#if renderiza bloque cuando variable tiene valor")
    func ifBlockWithValue() {
        var v = TemplateVariable(name: "LANG")
        v.value = "es"
        let result = TemplateEngine.render("{{#if LANG}}Idioma: {{LANG}}{{/if}}", with: [v])
        #expect(result == "Idioma: es")
    }

    @Test("#if omite bloque cuando variable esta vacia")
    func ifBlockEmpty() {
        let v = TemplateVariable(name: "LANG")
        let result = TemplateEngine.render("{{#if LANG}}Idioma: {{LANG}}{{/if}}", with: [v])
        #expect(result == "")
    }

    @Test("#if con texto alrededor")
    func ifBlockSurroundingText() {
        var v = TemplateVariable(name: "SHOW")
        v.value = "yes"
        let result = TemplateEngine.render("Before {{#if SHOW}}middle{{/if}} after", with: [v])
        #expect(result == "Before middle after")
    }

    // MARK: - #unless blocks

    @Test("#unless renderiza cuando variable esta vacia")
    func unlessBlockEmpty() {
        let v = TemplateVariable(name: "VERBOSE")
        let result = TemplateEngine.render("{{#unless VERBOSE}}Resumen breve{{/unless}}", with: [v])
        #expect(result == "Resumen breve")
    }

    @Test("#unless omite cuando variable tiene valor")
    func unlessBlockWithValue() {
        var v = TemplateVariable(name: "VERBOSE")
        v.value = "true"
        let result = TemplateEngine.render("{{#unless VERBOSE}}Resumen breve{{/unless}}", with: [v])
        #expect(result == "")
    }

    // MARK: - #each blocks

    @Test("#each itera sobre items separados por coma")
    func eachBasic() {
        var v = TemplateVariable(name: "ITEMS", kind: .list)
        v.value = "a, b, c"
        let result = TemplateEngine.render("{{#each ITEMS}}[{{.}}]{{/each}}", with: [v])
        #expect(result == "[a][b][c]")
    }

    @Test("#each con @index")
    func eachWithIndex() {
        var v = TemplateVariable(name: "ITEMS", kind: .list)
        v.value = "x,y"
        let result = TemplateEngine.render("{{#each ITEMS}}{{@index}}:{{.}} {{/each}}", with: [v])
        #expect(result == "0:x 1:y ")
    }

    @Test("#each con lista vacia no produce output")
    func eachEmptyList() {
        let v = TemplateVariable(name: "ITEMS", kind: .list)
        let result = TemplateEngine.render("{{#each ITEMS}}item{{/each}}", with: [v])
        #expect(result == "")
    }

    @Test("{{.}} fuera de #each se deja como texto literal")
    func dotOutsideEach() {
        let result = TemplateEngine.render("{{.}}", with: [])
        #expect(result == "{{.}}")
    }

    @Test("{{@index}} fuera de #each se deja como texto literal")
    func indexOutsideEach() {
        let result = TemplateEngine.render("{{@index}}", with: [])
        #expect(result == "{{@index}}")
    }

    // MARK: - Nesting

    @Test("#if dentro de #each")
    func ifInsideEach() {
        var users = TemplateVariable(name: "USERS", kind: .list)
        users.value = "Ana,Bob"
        var greeting = TemplateVariable(name: "GREETING")
        greeting.value = "yes"
        let result = TemplateEngine.render(
            "{{#each USERS}}{{#if GREETING}}Hello {{.}} {{/if}}{{/each}}",
            with: [users, greeting]
        )
        #expect(result == "Hello Ana Hello Bob ")
    }

    @Test("#each dentro de #if")
    func eachInsideIf() {
        var show = TemplateVariable(name: "SHOW")
        show.value = "yes"
        var items = TemplateVariable(name: "ITEMS", kind: .list)
        items.value = "a,b"
        let result = TemplateEngine.render(
            "{{#if SHOW}}Items: {{#each ITEMS}}{{.}} {{/each}}{{/if}}",
            with: [show, items]
        )
        #expect(result == "Items: a b ")
    }

    // MARK: - Edge cases

    @Test("Bloque sin cierre no crashea")
    func unclosedBlock() {
        var v = TemplateVariable(name: "X")
        v.value = "yes"
        let result = TemplateEngine.render("{{#if X}}content", with: [v])
        #expect(result == "content")
    }

    @Test("Cierre sin apertura se trata como texto")
    func closeWithoutOpen() {
        let result = TemplateEngine.render("text{{/if}}", with: [])
        #expect(result == "text{{/if}}")
    }

    @Test("Profundidad maxima de nesting no crashea")
    func maxNestingDepth() {
        var template = ""
        for _ in 0..<20 {
            template += "{{#if X}}"
        }
        template += "deep"
        for _ in 0..<20 {
            template += "{{/if}}"
        }
        var v = TemplateVariable(name: "X")
        v.value = "yes"
        let result = TemplateEngine.render(template, with: [v])
        #expect(result.contains("deep"))
    }

    @Test("#each respeta limite de iteraciones")
    func eachIterationLimit() {
        var v = TemplateVariable(name: "BIG", kind: .list)
        v.value = (0..<2000).map { String($0) }.joined(separator: ",")
        let result = TemplateEngine.render("{{#each BIG}}x{{/each}}", with: [v])
        #expect(result.count == TemplateEngine.maxIterations)
    }

    // MARK: - extractVariables with blocks

    @Test("extractVariables detecta variables de #if como scalar")
    func extractIfVariable() {
        let vars = TemplateEngine.extractVariables(from: "{{#if SHOW}}text{{/if}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "SHOW")
        #expect(vars[0].kind == .scalar)
    }

    @Test("extractVariables detecta variables de #each como list")
    func extractEachVariable() {
        let vars = TemplateEngine.extractVariables(from: "{{#each ITEMS}}{{.}}{{/each}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "ITEMS")
        #expect(vars[0].kind == .list)
    }

    @Test("extractVariables extrae variables dentro de bloques")
    func extractVariablesInsideBlocks() {
        let text = "{{#if SHOW}}Hello {{NAME}}{{/if}}"
        let vars = TemplateEngine.extractVariables(from: text)
        #expect(vars.count == 2)
        #expect(vars[0].name == "SHOW")
        #expect(vars[1].name == "NAME")
    }

    // MARK: - hasBlocks

    @Test("hasBlocks detecta #if")
    func hasBlocksIf() {
        #expect(TemplateEngine.hasBlocks(in: "{{#if X}}y{{/if}}"))
    }

    @Test("hasBlocks retorna false sin bloques")
    func hasBlocksFalse() {
        #expect(!TemplateEngine.hasBlocks(in: "{{VAR}} normal"))
    }

    // MARK: - Single-pass rendering (security)

    @Test("Valor de variable con sintaxis template no se re-procesa")
    func singlePassRendering() {
        var v = TemplateVariable(name: "INPUT")
        v.value = "{{#if ADMIN}}secret{{/if}}"
        let result = TemplateEngine.render("Got: {{INPUT}}", with: [v])
        #expect(result == "Got: {{#if ADMIN}}secret{{/if}}")
    }

    @Test("Cierre con tipo incorrecto no crashea")
    func mismatchedBlockClose() {
        var v = TemplateVariable(name: "X")
        v.value = "yes"
        let result = TemplateEngine.render("{{#if X}}content{{/each}}", with: [v])
        #expect(result.contains("content"))
    }

    @Test("Render usa defaultValue del AST cuando variable no esta en lookup")
    func renderUsesASTDefault() {
        let nodes = TemplateEngine.parse("Hello {{NAME=World}}")
        let result = TemplateEngine.render(nodes: nodes, with: [])
        #expect(result == "Hello World")
    }

    @Test("#each trimea espacios pero preserva espacios internos")
    func eachItemsWithInternalSpaces() {
        var v = TemplateVariable(name: "ITEMS", kind: .list)
        v.value = "  hello world  ,  foo bar  "
        let result = TemplateEngine.render("{{#each ITEMS}}[{{.}}]{{/each}}", with: [v])
        #expect(result == "[hello world][foo bar]")
    }

    @Test("#each omite items vacios entre comas")
    func eachSkipsEmptyItems() {
        var v = TemplateVariable(name: "ITEMS", kind: .list)
        v.value = "a,,b"
        let result = TemplateEngine.render("{{#each ITEMS}}{{.}}{{/each}}", with: [v])
        #expect(result == "ab")
    }

    @Test("#unless con variable no definida en lookup se renderiza")
    func unlessUndefinedVariable() {
        let result = TemplateEngine.render("{{#unless X}}visible{{/unless}}", with: [])
        #expect(result == "visible")
    }

    @Test("Variable de solo underscore es valida")
    func singleUnderscoreVariable() {
        let vars = TemplateEngine.extractVariables(from: "{{_}}")
        #expect(vars.count == 1)
        #expect(vars[0].name == "_")
    }
}
