import CraCore
import Foundation
import Testing

struct MCPProtocolTests {
    @Test func toolArguments() {
        #expect(MCPProtocol.validate(name: "tabs_list", arguments: [:]))
        #expect(!MCPProtocol.validate(name: "tabs_list", arguments: ["extra": "x"]))
        #expect(!MCPProtocol.validate(name: "unknown", arguments: [:]))
        #expect(!MCPProtocol.validate(name: "page_read", arguments: [:]))
        #expect(!MCPProtocol.validate(name: "page_read", arguments: ["tabId": 42]))
        #expect(MCPProtocol.validate(name: "page_read", arguments: ["tabId": "id"]))
        #expect(!MCPProtocol.validate(name: "page_navigate", arguments: ["tabId": "id"]))
        #expect(MCPProtocol.validate(name: "page_navigate", arguments: ["tabId": "id", "url": "https://example.com"]))
        #expect(MCPProtocol.validate(name: "page_evaluate", arguments: ["tabId": "id", "expression": "document.title"]))
    }

    @Test func backgroundAndTransferArguments() {
        #expect(MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.com", "windowless": true]))
        #expect(!MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.com", "windowless": 1]))
        #expect(MCPProtocol.validate(name: "page_upload", arguments: ["tabId": "id", "selector": "input", "paths": ["/tmp/sample.txt"]]))
        for paths in [[], ["relative"], ["/tmp/a\0b"], Array(repeating: "/tmp/a", count: 9), ["/" + String(repeating: "a", count: 4096)]] {
            #expect(!MCPProtocol.validate(name: "page_upload", arguments: ["tabId": "id", "selector": "input", "paths": paths]))
        }
        #expect(!MCPProtocol.validate(name: "page_upload", arguments: ["tabId": "id", "paths": ["/tmp/a"]]))
        #expect(MCPProtocol.validate(name: "page_drag", arguments: ["tabId": "id", "ref": "r1", "targetSelector": "#drop"]))
        #expect(!MCPProtocol.validate(name: "page_drag", arguments: ["tabId": "id", "selector": "#a", "targetSelector": ""]))
        #expect(!MCPProtocol.validate(name: "page_drag", arguments: ["tabId": "id", "selector": "#a", "targetSelector": String(repeating: "a", count: 2049)]))
        #expect(MCPProtocol.validate(name: "download_status", arguments: ["tabId": "id", "downloadId": "d"]))
        #expect(!MCPProtocol.validate(name: "download_cancel", arguments: ["tabId": "id"]))
    }

    @Test func pointsTargetsAndReasons() {
        #expect(MCPProtocol.validate(name: "page_click", arguments: ["tabId": "id", "x": 10.5, "y": 20, "button": "right", "clickCount": 2, "modifiers": "Meta"]))
        #expect(MCPProtocol.problem(name: "page_click", arguments: ["tabId": "id", "x": 10]) == "x and y go together.")
        #expect(MCPProtocol.problem(name: "page_click", arguments: ["tabId": "id"]) == "page_click needs a target: ref, selector or x/y.")
        #expect(MCPProtocol.problem(name: "page_click", arguments: ["tabId": "id", "x": -1, "y": 2]) == "x must not be negative.")
        #expect(MCPProtocol.problem(name: "page_click", arguments: ["tabId": "id", "selector": "a", "button": "back"]) == "button must be one of left, right, middle.")
        #expect(MCPProtocol.problem(name: "page_click", arguments: ["tabId": "id", "selector": "a", "clickCount": 4]) == "clickCount must be at most 3.")
        // Points only where an element isn't needed to act on.
        #expect(!MCPProtocol.validate(name: "page_fill", arguments: ["tabId": "id", "x": 1, "y": 1, "text": "a"]))
        #expect(!MCPProtocol.validate(name: "page_upload", arguments: ["tabId": "id", "x": 1, "y": 1, "paths": ["/tmp/a"]]))
        // Typing and keys without a target go to what has focus; scrolling to the middle.
        #expect(MCPProtocol.validate(name: "page_type", arguments: ["tabId": "id", "text": "hello"]))
        #expect(MCPProtocol.validate(name: "page_scroll", arguments: ["tabId": "id", "dy": 300]))
        #expect(MCPProtocol.validate(name: "page_scroll", arguments: ["tabId": "id", "dx": -40]))
        #expect(MCPProtocol.problem(name: "page_scroll", arguments: ["tabId": "id", "dy": 0]) == "page_scroll needs a nonzero dy or dx.")
        #expect(MCPProtocol.problem(name: "page_fill", arguments: ["tabId": "id", "text": "a"]) == "page_fill needs a target: ref or selector.")
        #expect(MCPProtocol.problem(name: "tab_open", arguments: [:]) == "tab_open needs url.")
        #expect(MCPProtocol.problem(name: "tab_open", arguments: ["url": "https://a.b", "extra": 1]) == "tab_open has no argument extra.")
        #expect(MCPProtocol.problem(name: "nope", arguments: [:]) == "Unknown tool nope.")
    }

    @Test func selectDialogConsoleAndSnapshotArguments() {
        #expect(MCPProtocol.validate(name: "page_select", arguments: ["tabId": "id", "selector": "s", "label": "Spain"]))
        #expect(MCPProtocol.problem(name: "page_select", arguments: ["tabId": "id", "selector": "s"]) == "page_select needs value or label (one of them).")
        #expect(!MCPProtocol.validate(name: "page_select", arguments: ["tabId": "id", "selector": "s", "label": "a", "value": "a"]))
        #expect(MCPProtocol.validate(name: "page_dialog", arguments: ["tabId": "id", "action": "accept", "promptText": "Victor"]))
        #expect(MCPProtocol.problem(name: "page_dialog", arguments: ["tabId": "id", "action": "back"]) == "action must be one of accept, dismiss.")
        #expect(MCPProtocol.problem(name: "page_history", arguments: ["tabId": "id", "action": "accept"]) == "action must be one of back, forward, reload.")
        #expect(MCPProtocol.validate(name: "page_console", arguments: ["tabId": "id", "level": "error", "clear": true]))
        #expect(!MCPProtocol.validate(name: "page_console", arguments: ["tabId": "id", "level": "debug"]))
        #expect(MCPProtocol.validate(name: "page_snapshot", arguments: ["tabId": "id", "interactive": true, "query": "search"]))
        #expect(MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://a.b", "space": "Work", "select": true, "activate": false]))
        #expect(MCPProtocol.validate(name: "tab_show", arguments: ["tabId": "id", "activate": true]))
        #expect(MCPProtocol.readTools.contains("page_console") && !MCPProtocol.readTools.contains("page_dialog"))
        #expect(MCPProtocol.tools.count == 33)
    }

    @Test func navigationSchemes() {
        for url in ["https://example.com/a", "http://localhost:8080", "HTTPS://example.com"] {
            #expect(MCPProtocol.navigable(url))
        }
        for url in ["javascript:alert(1)", "file:///etc/passwd", "cra://action/quit", "/relative", "https:missing-host"] {
            #expect(!MCPProtocol.navigable(url))
        }
    }

    @Test func envelopesRoundTrip() throws {
        let error = MCPProtocol.error(id: "request-1", code: -32602, message: "Invalid")
        let encoded = try JSONSerialization.data(withJSONObject: error)
        let decoded = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(decoded["id"] as? String == "request-1")
        #expect((decoded["error"] as? [String: Any])?["code"] as? Int == -32602)
        let result = MCPProtocol.result(id: 3, value: MCPProtocol.content("Failure", failed: true))
        #expect((result["result"] as? [String: Any])?["isError"] as? Bool == true)
        #expect(JSONSerialization.isValidJSONObject(MCPProtocol.tools))
    }
}
