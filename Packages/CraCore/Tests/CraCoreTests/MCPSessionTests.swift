import CraCore
import Foundation
import Testing

@MainActor
struct MCPSessionTests {
    private func request(_ session: MCPSession, _ method: String, params: Any = [:], id: Any = 1) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        var response: Data?
        session.receive(data, perform: { _, _, done in done(MCPProtocol.content("fixture")) }) { response = $0 }
        let bytes = try #require(response)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func initialize(_ session: MCPSession, version: String = MCPProtocol.version) throws -> [String: Any] {
        try request(session, "initialize", params: ["protocolVersion": version, "capabilities": [:],
                                                  "clientInfo": ["name": "test", "version": "1"]])
    }

    private func notify(_ session: MCPSession, method: String) {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": method])
        session.receive(data, perform: { _, _, _ in Issue.record("A notification executed a tool") }) {
            #expect($0 == nil)
        }
    }

    @Test func handshakeAndTools() throws {
        let session = MCPSession()
        #expect(try request(session, "ping")["result"] != nil)
        #expect(try request(session, "tools/list")["error"] != nil)
        notify(session, method: "notifications/initialized")
        #expect(try request(session, "initialize")["error"] != nil)
        #expect(try initialize(session)["result"] != nil)
        #expect(try request(session, "tools/list")["error"] != nil)
        notify(session, method: "notifications/initialized")
        #expect(try (request(session, "tools/list")["result"] as? [String: Any])?["tools"] != nil)
        #expect(try request(session, "tools/call", params: ["name": "tabs_list"])["result"] != nil)
        #expect(try request(session, "tools/call", params: ["name": "unknown"])["error"] != nil)
        #expect(try request(session, "tools/call", params: ["name": "page_read", "arguments": ["tabId": 7]])["error"] != nil)
        #expect(try request(session, "tools/call", params: ["name": "tabs_list", "arguments": []])["error"] != nil)
        #expect(try request(session, "unknown")["error"] != nil)
        #expect(try initialize(session)["error"] != nil)
    }

    @Test func negotiation() throws {
        for version in ["2024-11-05", "2025-03-26", "2025-06-18", MCPProtocol.version, "future"] {
            let result = try initialize(MCPSession(), version: version)["result"] as? [String: Any]
            #expect(result?["protocolVersion"] as? String == (version == "future" ? MCPProtocol.version : version))
        }
    }

    @Test func malformedRequests() throws {
        for text in ["broken", "null", "[]", "7", "{}", "{\"jsonrpc\":\"1.0\",\"method\":\"ping\"}"] {
            var response: Data?
            MCPSession().receive(Data(text.utf8), perform: { _, _, _ in Issue.record("Invalid request executed") }) { response = $0 }
            let bytes = try #require(response)
            let decoded = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(decoded["error"] != nil)
        }
        let invalidIDs: [Any] = [true, NSNull(), ["invalid"], String(repeating: "x", count: 257)]
        for id in invalidIDs {
            #expect(try request(MCPSession(), "ping", id: id)["error"] != nil)
        }
        #expect(try request(MCPSession(), "ping", params: [])["error"] != nil)
        #expect(try request(MCPSession(), "ping", id: "string-id")["id"] as? String == "string-id")
    }

    @Test func oversizedResultsStayValid() throws {
        #expect(MCPProtocol.content(String(repeating: "🦊", count: 60_000))["isError"] as? Bool == true)
        let session = MCPSession()
        _ = try initialize(session)
        notify(session, method: "notifications/initialized")
        let request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "tabs_list"]])
        var response: Data?
        session.receive(request, perform: { _, _, done in done(["value": String(repeating: "x", count: MCPProtocol.messageLimit)]) }) { response = $0 }
        let bytes = try #require(response)
        #expect(bytes.count < MCPProtocol.messageLimit)
        #expect(try (JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["error"] != nil)
    }
}
