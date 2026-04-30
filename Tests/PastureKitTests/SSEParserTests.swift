import Testing
@testable import PastureKit

@Suite("SSEParser")
struct SSEParserTests {

    @Test("Empty line with empty buffer returns nil")
    func emptyLineEmptyBuffer() {
        var buffer = SSELineBuffer()
        let event = SSEParser.parse(line: "", buffer: &buffer)
        #expect(event == nil)
    }

    @Test("Event type parsed from event: prefix")
    func eventTypeParsed() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "event: content_block_delta", buffer: &buffer)
        #expect(buffer.eventType == "content_block_delta")
    }

    @Test("Data parsed from data: prefix")
    func dataParsed() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "data: {\"text\":\"hello\"}", buffer: &buffer)
        #expect(buffer.dataLines.count == 1)
        #expect(buffer.dataLines[0] == "{\"text\":\"hello\"}")
    }

    @Test("Complete event dispatched on empty line")
    func completeEventDispatched() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "event: message_start", buffer: &buffer)
        _ = SSEParser.parse(line: "data: {\"type\":\"message_start\"}", buffer: &buffer)
        let event = SSEParser.parse(line: "", buffer: &buffer)
        #expect(event != nil)
        #expect(event?.event == "message_start")
        #expect(event?.data == "{\"type\":\"message_start\"}")
    }

    @Test("Buffer resets after dispatch")
    func bufferResetsAfterDispatch() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "event: test", buffer: &buffer)
        _ = SSEParser.parse(line: "data: payload", buffer: &buffer)
        _ = SSEParser.parse(line: "", buffer: &buffer)
        #expect(buffer.eventType == nil)
        #expect(buffer.dataLines.isEmpty)
    }

    @Test("Multi-line data concatenated with newline")
    func multiLineData() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "data: line1", buffer: &buffer)
        _ = SSEParser.parse(line: "data: line2", buffer: &buffer)
        let event = SSEParser.parse(line: "", buffer: &buffer)
        #expect(event?.data == "line1\nline2")
    }

    @Test("Comment lines (colon prefix) ignored")
    func commentIgnored() {
        var buffer = SSELineBuffer()
        let event = SSEParser.parse(line: ": this is a comment", buffer: &buffer)
        #expect(event == nil)
        #expect(buffer.dataLines.isEmpty)
    }

    @Test("Event without event type has nil event field")
    func noEventType() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "data: test", buffer: &buffer)
        let event = SSEParser.parse(line: "", buffer: &buffer)
        #expect(event?.event == nil)
        #expect(event?.data == "test")
    }

    @Test("No event returned mid-stream")
    func noEventMidStream() {
        var buffer = SSELineBuffer()
        let e1 = SSEParser.parse(line: "event: delta", buffer: &buffer)
        let e2 = SSEParser.parse(line: "data: chunk", buffer: &buffer)
        #expect(e1 == nil)
        #expect(e2 == nil)
    }

    @Test("[DONE] data parsed correctly")
    func doneMarker() {
        var buffer = SSELineBuffer()
        _ = SSEParser.parse(line: "data: [DONE]", buffer: &buffer)
        let event = SSEParser.parse(line: "", buffer: &buffer)
        #expect(event?.data == "[DONE]")
    }
}
