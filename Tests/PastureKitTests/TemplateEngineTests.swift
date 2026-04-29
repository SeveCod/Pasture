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
}
