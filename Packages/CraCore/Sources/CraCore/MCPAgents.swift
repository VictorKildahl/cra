import Foundation

/// An agent the user allowed, or refused, to use Cra over MCP: one per client name and the
/// program that started the bridge (its code-signing team, or its path when unsigned).
public struct MCPAgent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// What the client calls itself in `initialize` ("claude-code"), as the user sees it.
    public var name: String
    /// The app it runs in ("Visual Studio Code", "Terminal"), when one could be found.
    public var via: String
    public var allowed: Bool
    public var decided: Date

    public init(id: String, name: String, via: String, allowed: Bool, decided: Date) {
        self.id = id; self.name = name; self.via = via; self.allowed = allowed; self.decided = decided
    }
}

public enum MCPAgents {
    /// The same agent keeps one identity across its updates: a signed launcher by team, so a
    /// new Claude Code version isn't a new agent; an unsigned one by its path.
    public static func identity(clientName: String, signer: String) -> String {
        clientName.lowercased() + "|" + signer
    }

    /// The user's earlier answer for this identity: true allowed, false refused, nil not asked yet.
    public static func decision(for id: String, in agents: [MCPAgent]) -> Bool? {
        agents.first { $0.id == id }?.allowed
    }

    /// `agents` with this answer replacing any earlier one for the same identity.
    public static func recording(_ agent: MCPAgent, in agents: [MCPAgent]) -> [MCPAgent] {
        agents.filter { $0.id != agent.id } + [agent]
    }

    /// "claude-code" → "Claude Code": known clients by their product name, others as they come.
    public static func displayName(_ clientName: String) -> String {
        let known = ["claude-code": "Claude Code", "claude-ai": "Claude", "cursor-vscode": "Cursor", "cursor": "Cursor",
                     "codex-mcp-client": "Codex", "codex": "Codex", "visual-studio-code": "VS Code", "windsurf": "Windsurf",
                     "zed": "Zed", "goose": "Goose"]
        let trimmed = String(clientName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if let name = known[trimmed.lowercased()] { return name }
        return trimmed.isEmpty ? "An agent" : trimmed
    }

}

/// `mcp.json` in the data folder: the user's MCP answers, kept with the profile (not in
/// UserDefaults, which a test copy run with CRA_DATA_DIR would share with the installed Cra).
public struct MCPSettings: Codable, Equatable, Sendable {
    /// page_evaluate on (Settings ▸ Advanced ▸ Let agents run JavaScript in pages).
    public var allowsScripts = false
    /// history_search on (Settings ▸ Advanced ▸ Let agents read your history).
    public var allowsHistory = false
    public var agents: [MCPAgent] = []

    public init(allowsScripts: Bool = false, allowsHistory: Bool = false, agents: [MCPAgent] = []) {
        self.allowsScripts = allowsScripts; self.allowsHistory = allowsHistory; self.agents = agents
    }

    /// The tools the user's answers leave off.
    public var disabledTools: Set<String> {
        var off: Set<String> = []
        if !allowsScripts { off.insert("page_evaluate") }
        if !allowsHistory { off.insert("history_search") }
        return off
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowsScripts = try c.decodeIfPresent(Bool.self, forKey: .allowsScripts) ?? false
        allowsHistory = try c.decodeIfPresent(Bool.self, forKey: .allowsHistory) ?? false
        agents = try c.decodeIfPresent([MCPAgent].self, forKey: .agents) ?? []
    }

    /// Missing or unreadable: nothing allowed, so every agent is asked again.
    public static func decode(_ data: Data?) -> MCPSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.flatMap { try? decoder.decode(MCPSettings.self, from: $0) } ?? MCPSettings()
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)) ?? Data()
    }
}
