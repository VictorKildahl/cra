import CraCore
import Foundation
import Testing

struct MCPAgentSetupTests {
    let cra = MCPServerEntry(name: "cra", command: "/Applications/Cra.app/Contents/MacOS/Cra",
                             args: ["--mcp", "/Users/me/Library/Application Support/Cra/mcp.sock"])
    let claude = MCPConfigFormat.json(key: "mcpServers", stdioType: true)
    let cursor = MCPConfigFormat.json(key: "mcpServers", stdioType: false)

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: JSON agents

    @Test func addsToAMissingFileTheWayTheAgentsOwnCommandDoes() throws {
        #expect(MCPAgentSetup.state(of: cra, in: nil, format: claude) == .absent)
        let data = try MCPAgentSetup.adding(cra, to: nil, format: claude)
        let server = try #require((try json(data)["mcpServers"] as? [String: Any])?["cra"] as? [String: Any])
        #expect(server["type"] as? String == "stdio")
        #expect(server["command"] as? String == cra.command)
        #expect(server["args"] as? [String] == cra.args)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: claude) == .current)
        // Paths keep their slashes, so the file reads like one the agent wrote.
        #expect(String(decoding: data, as: UTF8.self).contains("/Applications/Cra.app"))
        let plain = try MCPAgentSetup.adding(cra, to: Data(), format: cursor)
        #expect(((try json(plain)["mcpServers"] as? [String: Any])?["cra"] as? [String: Any])?["type"] == nil)
    }

    @Test func keepsTheRestOfTheFileAndOtherServers() throws {
        let existing = Data("""
        {"numStartups": 12, "theme": "dark", "flag": true,
         "mcpServers": {"other": {"command": "npx", "args": ["-y", "x"], "env": {"K": "v"}}},
         "projects": {"/a": {"allowedTools": []}}}
        """.utf8)
        let data = try MCPAgentSetup.adding(cra, to: existing, format: claude)
        let root = try json(data)
        #expect(root["numStartups"] as? Int == 12)
        #expect(root["theme"] as? String == "dark")
        #expect(root["flag"] as? Bool == true)
        #expect(root["projects"] != nil)
        let servers = try #require(root["mcpServers"] as? [String: Any])
        #expect(((servers["other"] as? [String: Any])?["env"] as? [String: String]) == ["K": "v"])
        #expect(servers["cra"] != nil)
    }

    @Test func movedAppIsOutdatedAndAddingAgainKeepsTheEntrysOwnKeys() throws {
        let old = Data("""
        {"mcpServers": {"cra": {"command": "/Users/me/Downloads/Cra.app/Contents/MacOS/Cra",
          "args": ["--mcp", "/old.sock"], "env": {"A": "1"}}}}
        """.utf8)
        #expect(MCPAgentSetup.state(of: cra, in: old, format: cursor) == .outdated)
        let data = try MCPAgentSetup.adding(cra, to: old, format: cursor)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: cursor) == .current)
        let server = try #require((try json(data)["mcpServers"] as? [String: Any])?["cra"] as? [String: Any])
        #expect(server["env"] as? [String: String] == ["A": "1"])
    }

    @Test func refusesFilesItCantEditSafely() {
        // VS Code's mcp.json may hold comments; a broken file is never overwritten.
        let comments = Data("{ // mine\n \"servers\": {} }".utf8)
        let vscode = MCPConfigFormat.json(key: "servers", stdioType: true)
        #expect(MCPAgentSetup.state(of: cra, in: comments, format: vscode) == .unreadable)
        #expect(throws: (any Error).self) { try MCPAgentSetup.adding(cra, to: comments, format: vscode) }
        #expect(throws: MCPAgentSetupError.notAnObject) { try MCPAgentSetup.adding(cra, to: Data("[1]".utf8), format: cursor) }
        let odd = Data(#"{"mcpServers": ["cra"]}"#.utf8)
        #expect(MCPAgentSetup.state(of: cra, in: odd, format: cursor) == .unreadable)
        #expect(throws: MCPAgentSetupError.serversNotAnObject) { try MCPAgentSetup.adding(cra, to: odd, format: cursor) }
    }

    @Test func removesOnlyCra() throws {
        let both = try MCPAgentSetup.adding(cra, to: Data(#"{"mcpServers": {"other": {"command": "x"}}}"#.utf8), format: cursor)
        let data = try MCPAgentSetup.removing("cra", from: both, format: cursor)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: cursor) == .absent)
        #expect((try json(data)["mcpServers"] as? [String: Any])?["other"] != nil)
        #expect(try json(MCPAgentSetup.removing("cra", from: nil, format: cursor)).isEmpty)
    }

    // MARK: Codex config.toml

    @Test func codexGetsItsOwnTableAppended() throws {
        let existing = Data("""
        model = "gpt-5-codex"

        [mcp_servers.other]
        command = "npx"

        """.utf8)
        let data = try MCPAgentSetup.adding(cra, to: existing, format: .codexTOML)
        #expect(String(decoding: data, as: UTF8.self) == """
        model = "gpt-5-codex"

        [mcp_servers.other]
        command = "npx"

        [mcp_servers.cra]
        command = "/Applications/Cra.app/Contents/MacOS/Cra"
        args = ["--mcp", "/Users/me/Library/Application Support/Cra/mcp.sock"]

        """)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: .codexTOML) == .current)
        #expect(String(decoding: try MCPAgentSetup.adding(cra, to: nil, format: .codexTOML), as: UTF8.self).hasPrefix("[mcp_servers.cra]\n"))
    }

    @Test func codexUpdateRewritesCommandAndArgsOnly() throws {
        let old = Data("""
        [mcp_servers."cra"]
        command = '/Old/Cra.app/Contents/MacOS/Cra'
        args = [
          "--mcp",
          "/old.sock",
        ]
        startup_timeout_sec = 20

        [mcp_servers.cra.env]
        A = "1"

        [profiles.fast]
        model = "x"
        """.utf8)
        #expect(MCPAgentSetup.state(of: cra, in: old, format: .codexTOML) == .outdated)
        let data = try MCPAgentSetup.adding(cra, to: old, format: .codexTOML)
        #expect(String(decoding: data, as: UTF8.self) == """
        [mcp_servers."cra"]
        command = "/Applications/Cra.app/Contents/MacOS/Cra"
        args = ["--mcp", "/Users/me/Library/Application Support/Cra/mcp.sock"]
        startup_timeout_sec = 20

        [mcp_servers.cra.env]
        A = "1"

        [profiles.fast]
        model = "x"

        """)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: .codexTOML) == .current)
    }

    @Test func codexReadsMultiLineArgsAndEscapes() {
        let entry = MCPServerEntry(name: "cra", command: #"/A "quoted"\Cra"#, args: ["--mcp", "/s.sock"])
        let file = Data(#"""
        [mcp_servers.cra]
        command = "/A \"quoted\"\\Cra"
        args = [
          "--mcp", # the socket follows
          '/s.sock',
        ]
        """#.utf8)
        #expect(MCPAgentSetup.state(of: entry, in: file, format: .codexTOML) == .current)
    }

    @Test func codexRemovesTheTableAndItsSubtables() throws {
        let file = Data("""
        model = "x"

        [mcp_servers.cra]
        command = "c"

        [mcp_servers.cra.env]
        A = "1"

        [mcp_servers.other]
        command = "o"
        """.utf8)
        let data = try MCPAgentSetup.removing("cra", from: file, format: .codexTOML)
        #expect(String(decoding: data, as: UTF8.self) == """
        model = "x"

        [mcp_servers.other]
        command = "o"

        """)
        #expect(MCPAgentSetup.state(of: cra, in: data, format: .codexTOML) == .absent)
    }

    @Test func codexInlineDefinitionsAreLeftAlone() {
        let inline = Data("""
        [mcp_servers]
        cra = { command = "c", args = [] }
        """.utf8)
        let dotted = Data(#"mcp_servers.cra.command = "c""#.utf8)
        for file in [inline, dotted] {
            #expect(MCPAgentSetup.state(of: cra, in: file, format: .codexTOML) == .unreadable)
            #expect(throws: MCPAgentSetupError.definedInline) { try MCPAgentSetup.adding(cra, to: file, format: .codexTOML) }
        }
        // Another server's table under the same parent is fine.
        let other = Data("[mcp_servers]\ncrab = { command = \"c\" }\n".utf8)
        #expect(MCPAgentSetup.state(of: cra, in: other, format: .codexTOML) == .absent)
    }

    // MARK: Agents

    @Test func tilesAreTheSixMostUsedAgents() {
        #expect(MCPAgentSetup.agents.filter(\.popular).map(\.name) == ["Claude Code", "Claude Cowork", "Codex", "Cursor", "T3 Code", "Conductor"])
        #expect(Set(MCPAgentSetup.agents.map(\.id)).count == MCPAgentSetup.agents.count)
    }

    @Test func agentsThatRunOthersWriteOnlyTheFilesInUse() throws {
        let t3 = try #require(MCPAgentSetup.agents.first { $0.id == "t3-code" })
        // Codex has never run here: only Claude Code's file (in the home folder) is written.
        #expect(MCPAgentSetup.targets(for: t3, folderExists: { $0.isEmpty }).map(\.path) == [".claude.json"])
        #expect(MCPAgentSetup.targets(for: t3, folderExists: { _ in true }).count == 2)
        // A single-file agent is written even before its folder exists.
        let cursor = try #require(MCPAgentSetup.agents.first { $0.id == "cursor" })
        #expect(MCPAgentSetup.targets(for: cursor, folderExists: { _ in false }).map(\.path) == [".cursor/mcp.json"])
    }

    @Test func anAgentIsAddedWhenEveryFileIs() {
        #expect(MCPAgentSetup.combined([.current, .current]) == .current)
        #expect(MCPAgentSetup.combined([.current, .absent]) == .outdated)
        #expect(MCPAgentSetup.combined([.absent, .absent]) == .absent)
        #expect(MCPAgentSetup.combined([.current, .unreadable]) == .unreadable)
        #expect(MCPAgentSetup.combined([]) == .absent)
    }
}
