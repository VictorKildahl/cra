import Foundation

/// How an agent keeps its MCP servers in a file Cra can add itself to.
public enum MCPConfigFormat: Sendable, Equatable {
    /// A JSON object with the servers under `key` ("mcpServers"; VS Code's is "servers").
    /// `stdioType` writes "type": "stdio" too, as Claude Code's own `claude mcp add` does.
    case json(key: String, stdioType: Bool)
    /// Codex's config.toml: one `[mcp_servers.<name>]` table per server.
    case codexTOML
}

/// One agent's MCP settings file, by its path in the home folder.
public struct MCPConfigFile: Sendable, Equatable, Hashable {
    public let path: String
    public let format: MCPConfigFormat

    public init(_ path: String, _ format: MCPConfigFormat) { self.path = path; self.format = format }

    /// The folder the file goes in ("" for the home folder itself).
    public var folder: String { (path as NSString).deletingLastPathComponent }

    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

/// An agent Settings ▸ Advanced ▸ Agents can add Cra to with one click, like the setup screens
/// of apps that work inside agents: the agent's own MCP settings file, written the way the
/// agent's `mcp add` command writes it.
public struct MCPAgentApp: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// What it covers, under its name ("Desktop or Terminal").
    public let detail: String
    /// One of the tiles; the rest are in the Other menu.
    public let popular: Bool
    /// T3 Code and Conductor run Claude Code and Codex, so they read those agents' files.
    public let files: [MCPConfigFile]
    /// App bundles that show it's installed and lend the tile their icon ("Cursor" for Cursor.app).
    public let apps: [String]
    public let bundleIDs: [String]
    /// Paths in the home folder that show it's installed when no app is (a CLI's own folder).
    public let markers: [String]
    /// What happens next, said once Cra is added.
    public let afterAdding: String
}

/// Cra's own entry: the bridge command an agent starts (`Cra --mcp <socket>`).
public struct MCPServerEntry: Sendable, Equatable {
    public let name: String
    public let command: String
    public let args: [String]

    public init(name: String, command: String, args: [String]) {
        self.name = name; self.command = command; self.args = args
    }
}

public enum MCPEntryState: Sendable, Equatable {
    case absent
    /// Present with this app's command and socket.
    case current
    /// Present for another copy of Cra or an older location: adding again fixes it.
    case outdated
    /// The file isn't one Cra can edit safely (JSON with comments, servers kept inline in TOML).
    case unreadable
}

public enum MCPAgentSetupError: Error, Equatable {
    case notAnObject
    case serversNotAnObject
    /// Codex has the server as dotted keys or an inline table, which Cra doesn't rewrite.
    case definedInline
}

public enum MCPAgentSetup {
    private static let claudeCode = MCPConfigFile(".claude.json", .json(key: "mcpServers", stdioType: true))
    private static let codex = MCPConfigFile(".codex/config.toml", .codexTOML)

    /// The agents in the order Settings shows them: the six most people use as tiles, then the rest.
    public static let agents: [MCPAgentApp] = [
        MCPAgentApp(id: "claude-code", name: "Claude Code", detail: "Desktop or Terminal", popular: true,
                    files: [claudeCode], apps: ["Claude"], bundleIDs: ["com.anthropic.claudefordesktop"],
                    markers: [".claude.json", ".claude"], afterAdding: "New Claude Code sessions can use Cra."),
        MCPAgentApp(id: "claude-cowork", name: "Claude Cowork", detail: "Claude app", popular: true,
                    files: [MCPConfigFile("Library/Application Support/Claude/claude_desktop_config.json", .json(key: "mcpServers", stdioType: false))],
                    apps: ["Claude"], bundleIDs: ["com.anthropic.claudefordesktop"],
                    markers: ["Library/Application Support/Claude"], afterAdding: "Quit and reopen Claude to use Cra in its chats and Cowork."),
        MCPAgentApp(id: "codex", name: "Codex", detail: "Desktop or Terminal", popular: true,
                    files: [codex], apps: ["Codex"], bundleIDs: ["com.openai.codex"],
                    markers: [".codex"], afterAdding: "New Codex sessions can use Cra."),
        MCPAgentApp(id: "cursor", name: "Cursor", detail: "", popular: true,
                    files: [MCPConfigFile(".cursor/mcp.json", .json(key: "mcpServers", stdioType: false))],
                    apps: ["Cursor"], bundleIDs: ["com.todesktop.230313mzl4w4u92"],
                    markers: [".cursor"], afterAdding: "Cursor lists Cra in Settings ▸ MCP; new chats can use it."),
        MCPAgentApp(id: "t3-code", name: "T3 Code", detail: "", popular: true,
                    files: [codex, claudeCode], apps: ["T3 Code", "T3 Code (Alpha)"], bundleIDs: [],
                    markers: [], afterAdding: "New T3 Code threads can use Cra."),
        MCPAgentApp(id: "conductor", name: "Conductor", detail: "", popular: true,
                    files: [claudeCode, codex], apps: ["Conductor"], bundleIDs: ["com.conductor.app"],
                    markers: [], afterAdding: "New Conductor workspaces can use Cra."),
        MCPAgentApp(id: "vscode", name: "VS Code", detail: "", popular: false,
                    files: [MCPConfigFile("Library/Application Support/Code/User/mcp.json", .json(key: "servers", stdioType: true))],
                    apps: ["Visual Studio Code"], bundleIDs: ["com.microsoft.VSCode"],
                    markers: ["Library/Application Support/Code"], afterAdding: "VS Code lists Cra under MCP Servers; start it from there."),
        MCPAgentApp(id: "windsurf", name: "Windsurf", detail: "", popular: false,
                    files: [MCPConfigFile(".codeium/windsurf/mcp_config.json", .json(key: "mcpServers", stdioType: false))],
                    apps: ["Windsurf"], bundleIDs: ["com.exafunction.windsurf"],
                    markers: [".codeium/windsurf"], afterAdding: "Refresh Windsurf's MCP servers to use Cra."),
        MCPAgentApp(id: "gemini-cli", name: "Gemini CLI", detail: "", popular: false,
                    files: [MCPConfigFile(".gemini/settings.json", .json(key: "mcpServers", stdioType: false))],
                    apps: [], bundleIDs: [], markers: [".gemini"], afterAdding: "New Gemini CLI sessions can use Cra."),
        MCPAgentApp(id: "lm-studio", name: "LM Studio", detail: "", popular: false,
                    files: [MCPConfigFile(".lmstudio/mcp.json", .json(key: "mcpServers", stdioType: false))],
                    apps: ["LM Studio"], bundleIDs: ["ai.elementlabs.lmstudio"],
                    markers: [".lmstudio"], afterAdding: "LM Studio's chats can use Cra once it's turned on in Program ▸ Integrations."),
    ]

    /// The files to write for an agent: those whose folder exists (T3 Code writes Codex's only
    /// when Codex has run here), or all of them when none does.
    public static func targets(for agent: MCPAgentApp, folderExists: (String) -> Bool) -> [MCPConfigFile] {
        let present = agent.files.filter { folderExists($0.folder) }
        return present.isEmpty ? agent.files : present
    }

    /// One state for an agent from its files' states: added only when every file is current.
    public static func combined(_ states: [MCPEntryState]) -> MCPEntryState {
        if states.contains(.unreadable) { return .unreadable }
        if states.isEmpty || states.allSatisfy({ $0 == .absent }) { return .absent }
        return states.allSatisfy { $0 == .current } ? .current : .outdated
    }

    // MARK: Reading and editing a file

    public static func state(of entry: MCPServerEntry, in data: Data?, format: MCPConfigFormat) -> MCPEntryState {
        switch format {
        case .json(let key, _):
            guard let root = try? jsonObject(data) else { return .unreadable }
            guard let servers = root[key] else { return .absent }
            guard let servers = servers as? [String: Any] else { return .unreadable }
            guard let server = servers[entry.name] else { return .absent }
            guard let server = server as? [String: Any] else { return .outdated }
            return server["command"] as? String == entry.command && server["args"] as? [String] == entry.args ? .current : .outdated
        case .codexTOML:
            let lines = tomlLines(data)
            if hasInlineDefinition(entry.name, lines) { return .unreadable }
            guard let block = tomlBlock(entry.name, lines) else { return .absent }
            let body = lines[(block.lowerBound + 1)..<block.upperBound].joined(separator: "\n")
            return tomlValue("command", in: body).flatMap(tomlString) == entry.command
                && tomlValue("args", in: body).flatMap(tomlStringArray) == entry.args ? .current : .outdated
        }
    }

    /// The file with Cra's entry added or brought up to date. The rest stays as it was, the
    /// entry's other keys (env, a timeout) included.
    public static func adding(_ entry: MCPServerEntry, to data: Data?, format: MCPConfigFormat) throws -> Data {
        switch format {
        case .json(let key, let stdioType):
            var root = try jsonObject(data)
            var servers: [String: Any] = [:]
            if let existing = root[key] {
                guard let existing = existing as? [String: Any] else { throw MCPAgentSetupError.serversNotAnObject }
                servers = existing
            }
            var server = servers[entry.name] as? [String: Any] ?? [:]
            if stdioType { server["type"] = "stdio" }
            server["command"] = entry.command
            server["args"] = entry.args
            servers[entry.name] = server
            root[key] = servers
            return try jsonData(root)
        case .codexTOML:
            var lines = tomlLines(data)
            if hasInlineDefinition(entry.name, lines) { throw MCPAgentSetupError.definedInline }
            let fresh = ["command = \(tomlQuoted(entry.command))",
                         "args = [\(entry.args.map(tomlQuoted).joined(separator: ", "))]"]
            if let block = tomlBlock(entry.name, lines) {
                let kept = tomlKeysKept(Array(lines[(block.lowerBound + 1)..<block.upperBound]), dropping: ["command", "args"])
                lines.replaceSubrange((block.lowerBound + 1)..<block.upperBound, with: fresh + kept)
            } else {
                while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
                if !lines.isEmpty { lines.append("") }
                lines += ["[mcp_servers.\(entry.name)]"] + fresh
            }
            return tomlData(lines)
        }
    }

    /// The file without Cra's entry (and, in TOML, its subtables such as `.env`).
    public static func removing(_ name: String, from data: Data?, format: MCPConfigFormat) throws -> Data {
        switch format {
        case .json(let key, _):
            var root = try jsonObject(data)
            guard let existing = root[key] else { return try jsonData(root) }
            guard var servers = existing as? [String: Any] else { throw MCPAgentSetupError.serversNotAnObject }
            servers[name] = nil
            root[key] = servers
            return try jsonData(root)
        case .codexTOML:
            var lines = tomlLines(data)
            if hasInlineDefinition(name, lines) { throw MCPAgentSetupError.definedInline }
            let headers = tomlHeaders(lines)
            for (i, header) in headers.enumerated().reversed()
            where header.name == "mcp_servers.\(name)" || header.name.hasPrefix("mcp_servers.\(name).") {
                let end = i + 1 < headers.count ? headers[i + 1].line : lines.count
                lines.removeSubrange(header.line..<end)
            }
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            return tomlData(lines)
        }
    }

    // MARK: JSON

    private static func jsonObject(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPAgentSetupError.notAnObject
        }
        return object
    }

    private static func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }

    // MARK: TOML (just what Codex's config needs: tables, one-line strings and string arrays)

    private static func tomlLines(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func tomlData(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
    }

    /// Every table header with its line and dotted name, quotes and spaces taken out
    /// (`[ mcp_servers."cra" ]` is `mcp_servers.cra`).
    private static func tomlHeaders(_ lines: [String]) -> [(line: Int, name: String)] {
        lines.enumerated().compactMap { index, raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { return nil }
            if let hash = line.firstIndex(of: "#"), !line[..<hash].contains("\"") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            let inner = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            let name = inner.split(separator: ".").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }.joined(separator: ".")
            return (index, name)
        }
    }

    /// The lines of `[mcp_servers.<name>]`: its header up to the next header.
    private static func tomlBlock(_ name: String, _ lines: [String]) -> Range<Int>? {
        let headers = tomlHeaders(lines)
        guard let i = headers.firstIndex(where: { $0.name == "mcp_servers.\(name)" }) else { return nil }
        var end = i + 1 < headers.count ? headers[i + 1].line : lines.count
        // Blank lines and comments before the next table belong to it.
        while end > headers[i].line + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        return headers[i].line..<end
    }

    /// `cra = { … }` or `cra.command = …` under `[mcp_servers]`, or `mcp_servers.cra…` at the top.
    private static func hasInlineDefinition(_ name: String, _ lines: [String]) -> Bool {
        var table = ""
        let headers = Dictionary(uniqueKeysWithValues: tomlHeaders(lines).map { ($0.line, $0.name) })
        for (index, raw) in lines.enumerated() {
            if let header = headers[index] { table = header; continue }
            let key = raw.split(separator: "=", maxSplits: 1).first.map {
                $0.split(separator: ".").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")) }
            } ?? []
            guard raw.contains("=") else { continue }
            if table == "mcp_servers", key.first == name { return true }
            if table.isEmpty, key.count > 1, key[0] == "mcp_servers", key[1] == name { return true }
        }
        return false
    }

    /// The table's key lines other than `dropping`, a multi-line array value skipped whole.
    private static func tomlKeysKept(_ body: [String], dropping: Set<String>) -> [String] {
        var kept: [String] = []
        var skippingArray = false
        for line in body {
            if skippingArray {
                if line.contains("]") { skippingArray = false }
                continue
            }
            let key = line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")) ?? ""
            if line.contains("="), dropping.contains(key) {
                let value = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
                skippingArray = value.contains("[") && !value.contains("]")
                continue
            }
            kept.append(line)
        }
        return kept
    }

    /// The text after `key =` up to the line's end, or to the closing `]` of a multi-line array.
    private static func tomlValue(_ key: String, in body: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")) == key else { continue }
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            var next = i + 1
            if value.hasPrefix("[") {
                while !tomlArrayClosed(value), next < lines.count { value += "\n" + lines[next]; next += 1 }
            }
            return value
        }
        return nil
    }

    private static func tomlArrayClosed(_ value: String) -> Bool {
        var scanner = Substring(value)
        scanner.removeFirst()
        while let c = scanner.first {
            if c == "\"" || c == "'" { guard tomlTakeString(&scanner) != nil else { return false }; continue }
            if c == "]" { return true }
            scanner.removeFirst()
        }
        return false
    }

    private static func tomlString(_ value: String) -> String? {
        var scanner = Substring(value.trimmingCharacters(in: .whitespaces))
        return tomlTakeString(&scanner)
    }

    private static func tomlStringArray(_ value: String) -> [String]? {
        var scanner = Substring(value.trimmingCharacters(in: .whitespaces))
        guard scanner.first == "[" else { return nil }
        scanner.removeFirst()
        var items: [String] = []
        while true {
            scanner = scanner.drop { " \t\n\r,".contains($0) }
            if scanner.hasPrefix("#") { scanner = scanner.drop { $0 != "\n" }; continue }
            if scanner.first == "]" { return items }
            guard let item = tomlTakeString(&scanner) else { return nil }
            items.append(item)
        }
    }

    /// Reads one basic ("…" with escapes) or literal ('…') string off the front.
    private static func tomlTakeString(_ scanner: inout Substring) -> String? {
        guard let quote = scanner.first, quote == "\"" || quote == "'" else { return nil }
        scanner.removeFirst()
        var out = ""
        while let c = scanner.first {
            scanner.removeFirst()
            if c == quote { return out }
            guard quote == "\"", c == "\\" else { out.append(c); continue }
            guard let e = scanner.first else { return nil }
            scanner.removeFirst()
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "\"", "\\": out.append(e)
            case "u", "U":
                let count = e == "u" ? 4 : 8
                guard let code = UInt32(scanner.prefix(count), radix: 16), let scalar = Unicode.Scalar(code) else { return nil }
                scanner.removeFirst(count)
                out.unicodeScalars.append(scalar)
            default: return nil
            }
        }
        return nil
    }

    private static func tomlQuoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}
