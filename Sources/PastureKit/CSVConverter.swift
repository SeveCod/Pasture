import Foundation

public enum CSVConverter {

    public static func convert(_ text: String, maxRows: Int = 1000) -> String {
        let rows = parse(text)
        guard let header = rows.first, !header.isEmpty else { return text }

        let colCount = header.count
        var lines: [String] = []

        lines.append("| " + header.map(escapeCell).joined(separator: " | ") + " |")
        lines.append("|" + Array(repeating: " --- ", count: colCount).joined(separator: "|") + "|")

        for row in rows.dropFirst().prefix(maxRows) {
            var cells = row
            while cells.count < colCount { cells.append("") }
            cells = Array(cells.prefix(colCount))
            lines.append("| " + cells.map(escapeCell).joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        guard !text.isEmpty else { return [] }

        let delim = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if quoted {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                    } else {
                        quoted = false
                        i = text.index(after: i)
                    }
                } else {
                    field.append(c)
                    i = text.index(after: i)
                }
            } else if c == "\"" && field.isEmpty {
                quoted = true
                i = text.index(after: i)
            } else if c == delim {
                row.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
                i = text.index(after: i)
            } else if c == "\r\n" || c == "\r" || c == "\n" {
                row.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
                rows.append(row)
                row = []
                i = text.index(after: i)
            } else {
                field.append(c)
                i = text.index(after: i)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: .whitespaces))
            rows.append(row)
        }

        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) {
            rows.removeLast()
        }

        return rows
    }

    public static func detectDelimiter(_ text: String) -> Character {
        let firstLine = String(text.prefix(while: { $0 != "\n" && $0 != "\r" }))
        let commas = firstLine.filter { $0 == "," }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        let semicolons = firstLine.filter { $0 == ";" }.count

        if tabs > commas && tabs >= semicolons { return "\t" }
        if semicolons > commas { return ";" }
        return ","
    }

    private static func escapeCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }
}
