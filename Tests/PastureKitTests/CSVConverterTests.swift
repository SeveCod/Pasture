import Testing
@testable import PastureKit

struct CSVConverterTests {

    // MARK: — Parsing

    @Test func parseSimpleCSV() {
        let rows = CSVConverter.parse("a,b,c\n1,2,3")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func parseQuotedFieldWithComma() {
        let rows = CSVConverter.parse("name,desc\n\"Smith, John\",hello")
        #expect(rows == [["name", "desc"], ["Smith, John", "hello"]])
    }

    @Test func parseEscapedQuotes() {
        let rows = CSVConverter.parse("a\n\"he said \"\"hi\"\"\"")
        #expect(rows == [["a"], ["he said \"hi\""]])
    }

    @Test func parseNewlineInQuotedField() {
        let rows = CSVConverter.parse("a,b\n\"line1\nline2\",c")
        #expect(rows == [["a", "b"], ["line1\nline2", "c"]])
    }

    @Test func parseEmptyFields() {
        let rows = CSVConverter.parse("a,,c\n,2,")
        #expect(rows == [["a", "", "c"], ["", "2", ""]])
    }

    @Test func parseSingleColumn() {
        let rows = CSVConverter.parse("header\nvalue1\nvalue2")
        #expect(rows == [["header"], ["value1"], ["value2"]])
    }

    @Test func parseTrailingNewline() {
        let rows = CSVConverter.parse("a,b\n1,2\n")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test func parseCRLFLineEndings() {
        let rows = CSVConverter.parse("a,b\r\n1,2\r\n")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test func parseCROnlyLineEndings() {
        let rows = CSVConverter.parse("a,b\r1,2")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test func parseEmptyInput() {
        let rows = CSVConverter.parse("")
        #expect(rows.isEmpty)
    }

    @Test func parseTrimUnquotedWhitespace() {
        let rows = CSVConverter.parse("a , b \n 1 , 2 ")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    // MARK: — Delimiter detection

    @Test func detectCommaDelimiter() {
        #expect(CSVConverter.detectDelimiter("a,b,c") == ",")
    }

    @Test func detectSemicolonDelimiter() {
        #expect(CSVConverter.detectDelimiter("a;b;c") == ";")
    }

    @Test func detectTabDelimiter() {
        #expect(CSVConverter.detectDelimiter("a\tb\tc") == "\t")
    }

    @Test func detectCommaDefault() {
        #expect(CSVConverter.detectDelimiter("abc") == ",")
    }

    @Test func parseSemicolonDelimited() {
        let rows = CSVConverter.parse("a;b;c\n1;2;3")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func parseTabDelimited() {
        let rows = CSVConverter.parse("a\tb\tc\n1\t2\t3")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    // MARK: — Markdown conversion

    @Test func convertToMarkdownTable() {
        let result = CSVConverter.convert("Name,Age\nAlice,30\nBob,25")
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == "| Name | Age |")
        #expect(lines[1] == "| --- | --- |")
        #expect(lines[2] == "| Alice | 30 |")
        #expect(lines[3] == "| Bob | 25 |")
    }

    @Test func convertEscapesPipesInCells() {
        let result = CSVConverter.convert("col\nval|ue")
        #expect(result.contains("val\\|ue"))
    }

    @Test func convertPadsShortRows() {
        let result = CSVConverter.convert("a,b,c\n1,2")
        let lines = result.components(separatedBy: "\n")
        #expect(lines[2] == "| 1 | 2 |  |")
    }

    @Test func convertTrimsLongRows() {
        let result = CSVConverter.convert("a,b\n1,2,3,4")
        let lines = result.components(separatedBy: "\n")
        #expect(lines[2] == "| 1 | 2 |")
    }

    @Test func convertMaxRowsLimit() {
        var csv = "h\n"
        for i in 1...10 { csv += "\(i)\n" }
        let result = CSVConverter.convert(csv, maxRows: 3)
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 5) // header + separator + 3 data rows
    }

    @Test func convertEmptyReturnsOriginal() {
        #expect(CSVConverter.convert("") == "")
    }

    @Test func convertHeaderOnlyNoData() {
        let result = CSVConverter.convert("Name,Age")
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 2) // header + separator, no data rows
        #expect(lines[0] == "| Name | Age |")
    }

    @Test func convertNewlineInCellFlattened() {
        let result = CSVConverter.convert("a,b\n\"line1\nline2\",c")
        #expect(result.contains("line1 line2"))
        #expect(!result.contains("line1\nline2"))
    }
}
