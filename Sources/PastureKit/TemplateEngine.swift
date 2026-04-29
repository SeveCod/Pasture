import Foundation

public enum VariableKind: Sendable, Hashable {
    case scalar
    case list
}

public struct TemplateVariable: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let defaultValue: String
    public var value: String
    public var kind: VariableKind

    public init(name: String, defaultValue: String = "", kind: VariableKind = .scalar) {
        self.name = name
        self.defaultValue = defaultValue
        self.value = defaultValue
        self.kind = kind
    }

    public var listItems: [String] {
        value.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

public enum TemplateNode: Sendable, Equatable {
    case text(String)
    case variable(name: String, defaultValue: String)
    case currentValue
    case currentIndex
    case ifBlock(variable: String, body: [TemplateNode])
    case unlessBlock(variable: String, body: [TemplateNode])
    case eachBlock(variable: String, body: [TemplateNode])
}

enum BlockKind: String, Equatable {
    case `if` = "if"
    case unless = "unless"
    case each = "each"
}

enum TemplateToken: Equatable {
    case text(String)
    case variable(name: String, defaultValue: String)
    case blockOpen(kind: BlockKind, variable: String)
    case blockClose(kind: BlockKind)
    case dot
    case index
}

public enum TemplateEngine {
    public static let maxNestingDepth = 16
    public static let maxIterations = 1_000

    // MARK: — Public API

    public static func extractVariables(from text: String) -> [TemplateVariable] {
        let nodes = parse(text)
        var seen = Set<String>()
        var vars: [TemplateVariable] = []
        collectVariables(from: nodes, seen: &seen, vars: &vars)
        return vars
    }

    public static func render(_ text: String, with variables: [TemplateVariable]) -> String {
        let nodes = parse(text)
        return render(nodes: nodes, with: variables)
    }

    public static func render(nodes: [TemplateNode], with variables: [TemplateVariable]) -> String {
        let lookup = Dictionary(variables.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        var output = ""
        for node in nodes {
            renderNode(node, lookup: lookup, currentItem: nil, currentIndex: nil, into: &output, depth: 0)
        }
        return output
    }

    public static func hasVariables(in text: String) -> Bool {
        text.contains("{{")
            && tokenize(text).contains(where: {
                switch $0 {
                case .variable, .blockOpen: return true
                default: return false
                }
            })
    }

    public static func hasBlocks(in text: String) -> Bool {
        tokenize(text).contains(where: {
            if case .blockOpen = $0 { return true }
            return false
        })
    }

    public static func parse(_ text: String) -> [TemplateNode] {
        let tokens = tokenize(text)
        var index = 0
        return parseNodes(tokens: tokens, index: &index, until: nil, depth: 0)
    }

    // MARK: — Tokenizer

    static func tokenize(_ text: String) -> [TemplateToken] {
        var tokens: [TemplateToken] = []
        var current = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "{",
               text.index(after: i) < text.endIndex,
               text[text.index(after: i)] == "{" {
                if !current.isEmpty {
                    tokens.append(.text(current))
                    current = ""
                }
                let tagStart = text.index(i, offsetBy: 2)
                guard let closeRange = text.range(of: "}}", range: tagStart..<text.endIndex) else {
                    current.append(contentsOf: text[i..<text.endIndex])
                    break
                }
                let inner = String(text[tagStart..<closeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                tokens.append(classifyTag(inner))
                i = closeRange.upperBound
            } else {
                current.append(text[i])
                i = text.index(after: i)
            }
        }

        if !current.isEmpty {
            tokens.append(.text(current))
        }
        return tokens
    }

    private static func classifyTag(_ inner: String) -> TemplateToken {
        if inner == "." { return .dot }
        if inner == "@index" { return .index }

        if inner.hasPrefix("#") {
            let rest = String(inner.dropFirst())
            if let spaceIdx = rest.firstIndex(of: " ") {
                let kindStr = String(rest[rest.startIndex..<spaceIdx])
                let varName = String(rest[rest.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                if let kind = BlockKind(rawValue: kindStr), isValidName(varName) {
                    return .blockOpen(kind: kind, variable: varName)
                }
            }
        }

        if inner.hasPrefix("/") {
            let kindStr = String(inner.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let kind = BlockKind(rawValue: kindStr) {
                return .blockClose(kind: kind)
            }
        }

        if let eqIdx = inner.firstIndex(of: "=") {
            let name = String(inner[inner.startIndex..<eqIdx])
            let def = String(inner[inner.index(after: eqIdx)...])
            if isValidName(name) {
                return .variable(name: name, defaultValue: def)
            }
        }

        if isValidName(inner) {
            return .variable(name: inner, defaultValue: "")
        }

        return .text("{{\(inner)}}")
    }

    private static func isValidName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    // MARK: — Parser

    private static func parseNodes(tokens: [TemplateToken], index: inout Int, until: BlockKind?, depth: Int) -> [TemplateNode] {
        var nodes: [TemplateNode] = []

        while index < tokens.count {
            let token = tokens[index]

            switch token {
            case .text(let s):
                nodes.append(.text(s))
                index += 1

            case .variable(let name, let def):
                nodes.append(.variable(name: name, defaultValue: def))
                index += 1

            case .dot:
                nodes.append(.currentValue)
                index += 1

            case .index:
                nodes.append(.currentIndex)
                index += 1

            case .blockOpen(let kind, let variable):
                index += 1
                if depth >= maxNestingDepth {
                    nodes.append(.text("{{\(blockOpenText(kind, variable))}}"))
                } else {
                    let body = parseNodes(tokens: tokens, index: &index, until: kind, depth: depth + 1)
                    switch kind {
                    case .if: nodes.append(.ifBlock(variable: variable, body: body))
                    case .unless: nodes.append(.unlessBlock(variable: variable, body: body))
                    case .each: nodes.append(.eachBlock(variable: variable, body: body))
                    }
                }

            case .blockClose(let kind):
                index += 1
                if kind == until {
                    return nodes
                }
                nodes.append(.text("{{/\(kind.rawValue)}}"))
            }
        }

        return nodes
    }

    private static func blockOpenText(_ kind: BlockKind, _ variable: String) -> String {
        "#\(kind.rawValue) \(variable)"
    }

    // MARK: — Renderer

    private static func renderNode(_ node: TemplateNode, lookup: [String: String], currentItem: String?, currentIndex: Int?, into output: inout String, depth: Int) {
        switch node {
        case .text(let s):
            output += s

        case .variable(let name, let def):
            if let val = lookup[name] {
                output += val
            } else if !def.isEmpty {
                output += def
            } else {
                output += "{{\(name)}}"
            }

        case .currentValue:
            if let item = currentItem {
                output += item
            } else {
                output += "{{.}}"
            }

        case .currentIndex:
            if let idx = currentIndex {
                output += String(idx)
            } else {
                output += "{{@index}}"
            }

        case .ifBlock(let variable, let body):
            guard depth < maxNestingDepth else { return }
            let val = lookup[variable] ?? ""
            if !val.isEmpty {
                for child in body {
                    renderNode(child, lookup: lookup, currentItem: currentItem, currentIndex: currentIndex, into: &output, depth: depth + 1)
                }
            }

        case .unlessBlock(let variable, let body):
            guard depth < maxNestingDepth else { return }
            let val = lookup[variable] ?? ""
            if val.isEmpty {
                for child in body {
                    renderNode(child, lookup: lookup, currentItem: currentItem, currentIndex: currentIndex, into: &output, depth: depth + 1)
                }
            }

        case .eachBlock(let variable, let body):
            guard depth < maxNestingDepth else { return }
            let val = lookup[variable] ?? ""
            let items = val.split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for (idx, item) in items.prefix(maxIterations).enumerated() {
                for child in body {
                    renderNode(child, lookup: lookup, currentItem: item, currentIndex: idx, into: &output, depth: depth + 1)
                }
            }
        }
    }

    // MARK: — Variable extraction

    private static func collectVariables(from nodes: [TemplateNode], seen: inout Set<String>, vars: inout [TemplateVariable]) {
        for node in nodes {
            switch node {
            case .variable(let name, let def):
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                vars.append(TemplateVariable(name: name, defaultValue: def, kind: .scalar))

            case .ifBlock(let variable, let body):
                if !seen.contains(variable) {
                    seen.insert(variable)
                    vars.append(TemplateVariable(name: variable, kind: .scalar))
                }
                collectVariables(from: body, seen: &seen, vars: &vars)

            case .unlessBlock(let variable, let body):
                if !seen.contains(variable) {
                    seen.insert(variable)
                    vars.append(TemplateVariable(name: variable, kind: .scalar))
                }
                collectVariables(from: body, seen: &seen, vars: &vars)

            case .eachBlock(let variable, let body):
                if !seen.contains(variable) {
                    seen.insert(variable)
                    vars.append(TemplateVariable(name: variable, kind: .list))
                }
                collectVariables(from: body, seen: &seen, vars: &vars)

            case .text, .currentValue, .currentIndex:
                break
            }
        }
    }
}
