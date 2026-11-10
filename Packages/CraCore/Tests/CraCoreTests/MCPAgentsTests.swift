import CraCore
import Foundation
import Testing

struct MCPAgentsTests {
    @Test func oneIdentityPerClientAndLauncher() {
        let team = MCPAgents.identity(clientName: "Claude-Code", signer: "team:Q6L2SF6YDW")
        #expect(team == MCPAgents.identity(clientName: "claude-code", signer: "team:Q6L2SF6YDW"))
        #expect(team != MCPAgents.identity(clientName: "claude-code", signer: "path:/opt/homebrew/bin/node"))
        #expect(team != MCPAgents.identity(clientName: "cursor", signer: "team:Q6L2SF6YDW"))
    }

    @Test func answersAreRememberedAndReplaced() {
        let id = MCPAgents.identity(clientName: "claude-code", signer: "team:T")
        var agents: [MCPAgent] = []
        #expect(MCPAgents.decision(for: id, in: agents) == nil)
        agents = MCPAgents.recording(MCPAgent(id: id, name: "Claude Code", via: "Terminal", allowed: true, decided: Date()), in: agents)
        #expect(MCPAgents.decision(for: id, in: agents) == true)
        agents = MCPAgents.recording(MCPAgent(id: id, name: "Claude Code", via: "Terminal", allowed: false, decided: Date()), in: agents)
        #expect(agents.count == 1 && MCPAgents.decision(for: id, in: agents) == false)
        #expect(MCPAgents.decision(for: "other|team:T", in: agents) == nil)
    }

    @Test func displayNames() {
        #expect(MCPAgents.displayName("claude-code") == "Claude Code")
        #expect(MCPAgents.displayName("Cursor") == "Cursor")
        #expect(MCPAgents.displayName("my-tool") == "my-tool")
        #expect(MCPAgents.displayName("  ") == "An agent")
        #expect(MCPAgents.displayName(String(repeating: "x", count: 200)).count == 60)
    }

    @Test func settingsFileRoundTripsAndDefaultsToNothingAllowed() {
        #expect(MCPSettings.decode(nil) == MCPSettings())
        #expect(MCPSettings.decode(Data("not json".utf8)).agents.isEmpty)
        #expect(!MCPSettings.decode(Data("{}".utf8)).allowsScripts)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = MCPSettings(allowsScripts: true, agents: [MCPAgent(id: "a|team:T", name: "A", via: "", allowed: true, decided: date)])
        #expect(MCPSettings.decode(settings.encoded()) == settings)
    }
}
