import CraCore
import Foundation
import Testing

struct MCPInputPlanTests {
    @Test func movementIsBoundedAndEndsAtTarget() throws {
        for variation in [-1.0, 0, 0.2, 0.8, 1, 2] {
            for end in [CGPoint.zero, CGPoint(x: 20, y: 40), CGPoint(x: 2000, y: 1200)] {
                let steps = MCPInputPlan.movement(from: .zero, to: end, variation: variation)
                #expect(steps.count >= 8 && steps.count <= 41)
                #expect(try #require(steps.last).point == end)
                #expect(steps.allSatisfy { $0.point.x.isFinite && $0.point.y.isFinite && $0.delay > 0 })
                let total = steps.reduce(0) { $0 + $1.delay }
                #expect(total >= 0.159 && total <= 0.651)
            }
        }
        let straight = MCPInputPlan.movement(from: .zero, to: CGPoint(x: 200, y: 0), variation: 0.5)
        #expect(straight.allSatisfy { $0.point.y == 0 })
        #expect(zip(straight, straight.dropFirst()).allSatisfy { $0.point.x < $1.point.x })
        #expect(MCPInputPlan.movement(from: .zero, to: CGPoint(x: 200, y: 0), variation: 0).contains { $0.point.y != 0 })
    }

    @Test func pacingAndTextBounds() {
        #expect(MCPInputPlan.keyHold(-1) == 0.025)
        #expect(abs(MCPInputPlan.keyHold(2) - 0.060) < 0.000001)
        #expect(MCPInputPlan.keyGap(0) == 0.035)
        #expect(MCPInputPlan.keyGap(1) == 0.095)
        #expect(MCPInputPlan.clickHold(0) == 0.055)
        #expect(MCPInputPlan.clickHold(1) == 0.110)
        for text in ["", "Mäx 🦊", "line\nline", String(repeating: "a", count: 256)] { #expect(MCPInputPlan.validText(text)) }
        for text in ["\t", "\r", "\0", "\u{7f}", String(repeating: "a", count: 257), "a" + String(repeating: "\u{301}", count: 4096)] { #expect(!MCPInputPlan.validText(text)) }
    }

    @Test func keyIdentity() {
        #expect(MCPInputPlan.textKey("a")?.code == "KeyA")
        #expect(MCPInputPlan.textKey("A")?.virtual == 65)
        #expect(MCPInputPlan.textKey("A")?.modifiers == 8)
        #expect(MCPInputPlan.textKey("A")?.unmodified == "a")
        #expect(MCPInputPlan.textKey("7")?.code == "Digit7")
        #expect(MCPInputPlan.textKey("!")?.code == "Digit1")
        #expect(MCPInputPlan.textKey("!")?.modifiers == 8)
        #expect(MCPInputPlan.textKey("/")?.code == "Slash")
        #expect(MCPInputPlan.textKey("?")?.modifiers == 8)
        #expect(MCPInputPlan.textKey(" ")?.modifiers == 0)
        #expect(MCPInputPlan.textKey("🦊") == nil)
        #expect(MCPInputPlan.textKey("ä") == nil)
        #expect(MCPInputPlan.textKey("\t") == nil)
        #expect(MCPInputPlan.keys["Enter"]?.virtual == 13)
        #expect(MCPInputPlan.keys["F999"] == nil)
    }

    @Test func inputSchemaAndDeadline() throws {
        for name in MCPProtocol.inputTools {
            var args: [String: Any] = ["tabId": "id", "selector": "#target"]
            if name == "page_fill" || name == "page_type" { args["text"] = "Mäx 🦊" }
            if name == "page_press" { args["key"] = "Enter" }
            if name == "page_scroll" { args["dy"] = 500 }
            if name == "page_select" { args["value"] = "two" }
            if name == "page_drag" { args["targetSelector"] = "#drop" }
            if name == "page_upload" { args["paths"] = ["/tmp/sample.txt"] }
            #expect(MCPProtocol.validate(name: name, arguments: args))
            args["selector"] = ""
            #expect(!MCPProtocol.validate(name: name, arguments: args))
            args["selector"] = String(repeating: "x", count: 2049)
            #expect(!MCPProtocol.validate(name: name, arguments: args))
            let request = try JSONSerialization.data(withJSONObject: ["method": "tools/call", "params": ["name": name]])
            #expect(MCPProtocol.responseTimeout(request) == 120)
        }
        #expect(!MCPProtocol.validate(name: "page_fill", arguments: ["tabId": "id", "selector": "input", "text": "\t"]))
        #expect(!MCPProtocol.validate(name: "page_press", arguments: ["tabId": "id", "selector": "input", "key": "F999"]))
        #expect(MCPProtocol.responseTimeout(Data()) == 20)
        #expect(MCPProtocol.responseTimeout(Data(#"{"method":"ping"}"#.utf8)) == 20)
    }
}
