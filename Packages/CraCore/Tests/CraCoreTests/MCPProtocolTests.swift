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
        #expect(MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.com", "background": true]))
        #expect(!MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.com", "background": 1]))
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
