import Foundation
import Testing
@testable import PastureKit

@Suite("PastureURLCommand")
struct PastureURLCommandTests {

    @Test func feedWithoutPreset() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://feed")!)
        #expect(cmd == .feed(presetName: nil))
    }

    @Test func feedWithPercentEncodedPreset() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://feed?preset=Mi%20Preset")!)
        #expect(cmd == .feed(presetName: "Mi Preset"))
    }

    @Test func newWithTitleAndText() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://new?title=Idea&text=hola%20mundo")!)
        #expect(cmd == .new(title: "Idea", text: "hola mundo"))
    }

    @Test func newWithNoParams() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://new")!)
        #expect(cmd == .new(title: nil, text: nil))
    }

    @Test func searchRequiresQuery() {
        #expect(PastureURLCommand.parse(URL(string: "pasture://search?q=mcp")!) == .search(query: "mcp"))
        #expect(PastureURLCommand.parse(URL(string: "pasture://search")!) == nil)
        #expect(PastureURLCommand.parse(URL(string: "pasture://search?q=%20")!) == nil)
    }

    @Test func foreignSchemeAndUnknownHostRejected() {
        #expect(PastureURLCommand.parse(URL(string: "https://feed?preset=x")!) == nil)
        #expect(PastureURLCommand.parse(URL(string: "pasture://selfdestruct")!) == nil)
    }

    @Test func hostIsCaseInsensitive() {
        #expect(PastureURLCommand.parse(URL(string: "pasture://FEED")!) == .feed(presetName: nil))
    }
}
