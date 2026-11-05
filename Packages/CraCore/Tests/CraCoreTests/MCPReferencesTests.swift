import CraCore
import Foundation
import Testing

struct MCPReferencesTests {
    @Test func identityNeverMoves() throws {
        var refs = MCPReferences()
        let firstValue = refs.reference(node: 7, document: "doc1")
        let first = try #require(firstValue)
        #expect(refs.reference(node: 7, document: "doc1") == first)
        #expect(refs.resolve(first, document: "doc1") == 7)
        #expect(refs.resolve(first, document: "doc2") == nil)
        let nextValue = refs.reference(node: 7, document: "doc2")
        let next = try #require(nextValue)
        #expect(next != first)
        #expect(refs.resolve(first, document: "doc2") == nil)
        var other = MCPReferences()
        #expect(other.reference(node: 7, document: "doc2") != next)
    }
    @Test func boundedWithoutEviction() {
        var refs = MCPReferences()
        let first = refs.reference(node: 1, document: "doc")!
        for node in 2...2000 { #expect(refs.reference(node: node, document: "doc") != nil) }
        #expect(refs.reference(node: 2001, document: "doc") == nil)
        refs.retain(nodes: [1], document: "doc")
        let added = refs.reference(node: 2001, document: "doc")
        #expect(added != nil)
        #expect(refs.resolve(first, document: "doc") == 1)
        #expect(refs.reference(node: 1, document: "doc") == first)
        #expect(refs.reference(node: 2001, document: "next") != nil)
    }
    @Test func expandedArguments() {
        #expect(MCPProtocol.validate(name: "page_click", arguments: ["tabId": "id", "ref": "e1"]))
        #expect(!MCPProtocol.validate(name: "page_click", arguments: ["tabId": "id", "ref": "e1", "selector": "a"]))
        #expect(!MCPProtocol.validate(name: "page_click", arguments: ["tabId": "id"]))
        for value: Any in [true, "100", 0, 2001, 1.5] {
            #expect(!MCPProtocol.validate(name: "page_scroll", arguments: ["tabId": "id", "selector": "body", "dy": value]))
        }
        #expect(MCPProtocol.validate(name: "page_scroll", arguments: ["tabId": "id", "selector": "body", "dy": -800]))
        #expect(MCPProtocol.validate(name: "page_wait", arguments: ["tabId": "id", "timeoutMs": 0]))
        #expect(!MCPProtocol.validate(name: "page_wait", arguments: ["tabId": "id", "timeoutMs": 10001]))
        #expect(!MCPProtocol.validate(name: "page_wait", arguments: ["tabId": "id", "state": "visible"]))
        #expect(!MCPProtocol.validate(name: "page_wait", arguments: ["tabId": "id", "selector": "a", "state": "banana"]))
        #expect(!MCPProtocol.validate(name: "page_history", arguments: ["tabId": "id", "action": "close"]))
        #expect(MCPProtocol.modifierFlags("Meta+Shift") == 12)
        #expect(MCPProtocol.modifierFlags("Shift+Shift") == nil)
        #expect(MCPProtocol.modifierFlags("Meta+") == nil)
        #expect(MCPProtocol.modifierFlags("Hyper") == nil)
    }
}
