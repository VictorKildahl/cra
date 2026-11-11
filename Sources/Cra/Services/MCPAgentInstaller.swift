import AppKit
import Observation

/// Settings ▸ Advanced ▸ Agents: adds Cra to an agent's MCP settings with one click
/// (MCPAgentSetup decides what goes in each file; this reads and writes them).
@MainActor @Observable
final class MCPAgentInstaller {
    static let shared = MCPAgentInstaller()

    private(set) var states: [String: MCPEntryState] = [:]
    /// What the last click did, said under the tiles.
    private(set) var message = ""
    private(set) var messageIsError = false
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var installed: [String: Bool] = [:]

    /// The home folder whose agent settings Cra edits. CRA_AGENT_CONFIG_HOME points a test copy
    /// at a made-up one, so trying the tiles never touches the real agents.
    private let home: URL = ProcessInfo.processInfo.environment["CRA_AGENT_CONFIG_HOME"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser

    /// The development build adds itself as "cra-dev", next to the installed Cra.
    var entry: MCPServerEntry {
        MCPServerEntry(name: Bundle.main.bundleIdentifier == "dk.kildahl.cra.dev" ? "cra-dev" : "cra",
                       command: Bundle.main.executablePath ?? "",
                       args: ["--mcp", AppPaths.file("mcp.sock").path])
    }

    func refresh() {
        let entry = entry
        installed = [:]
        for agent in MCPAgentSetup.agents {
            let files = targets(agent)
            states[agent.id] = MCPAgentSetup.combined(files.map {
                MCPAgentSetup.state(of: entry, in: try? Data(contentsOf: url($0)), format: $0.format)
            })
        }
    }

    func state(_ agent: MCPAgentApp) -> MCPEntryState { states[agent.id] ?? .absent }

    func add(_ agent: MCPAgentApp) {
        let entry = entry
        do {
            for file in targets(agent) {
                try edit(file) { try MCPAgentSetup.adding(entry, to: $0, format: file.format) }
            }
            say("Cra is added to \(agent.name). \(agent.afterAdding) Cra asks before it’s used the first time.")
        } catch let failure as Failure {
            say("Cra couldn’t change \(failure.path), so it left the file as it was. Copy the configuration and add it by hand.", error: true)
        } catch {
            say("Cra couldn’t add itself to \(agent.name): \(error.localizedDescription)", error: true)
        }
        refresh()
    }

    func remove(_ agent: MCPAgentApp) {
        let name = entry.name
        do {
            for file in targets(agent) where FileManager.default.fileExists(atPath: url(file).path) {
                try edit(file) { try MCPAgentSetup.removing(name, from: $0, format: file.format) }
            }
            say("Cra is removed from \(agent.name).")
        } catch let failure as Failure {
            say("Cra couldn’t change \(failure.path), so it left the file as it was.", error: true)
        } catch {
            say("Cra couldn’t remove itself from \(agent.name): \(error.localizedDescription)", error: true)
        }
        refresh()
    }

    func reveal(_ agent: MCPAgentApp) {
        let urls = targets(agent).map(url).filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// The agent's app or the folder its CLI keeps, so tiles for agents not on this Mac are off.
    func isInstalled(_ agent: MCPAgentApp) -> Bool {
        if let known = installed[agent.id] { return known }
        let found = appURL(agent) != nil || agent.markers.contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
        installed[agent.id] = found
        return found
    }

    /// The agent's own app icon; nil for a CLI with no app (the tile draws a terminal).
    func icon(_ agent: MCPAgentApp) -> NSImage? {
        if let icon = icons[agent.id] { return icon }
        guard let app = appURL(agent) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icons[agent.id] = icon
        return icon
    }

    // MARK: Files

    private struct Failure: Error { let path: String }

    private func targets(_ agent: MCPAgentApp) -> [MCPConfigFile] {
        MCPAgentSetup.targets(for: agent) { folder in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: home.appendingPathComponent(folder).path, isDirectory: &isFolder) && isFolder.boolValue
        }
    }

    /// The file itself when the path is a link (dotfiles kept in a repo), so it stays a link.
    private func url(_ file: MCPConfigFile) -> URL {
        home.appendingPathComponent(file.path).resolvingSymlinksInPath()
    }

    /// Reads, changes and writes one file atomically, keeping its permissions (Claude Code's
    /// file is the owner's only); a new file is the owner's only too.
    private func edit(_ file: MCPConfigFile, _ change: (Data?) throws -> Data) throws {
        let url = url(file)
        let shown = "~/" + file.path
        let manager = FileManager.default
        let existing = manager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let updated: Data
        do { updated = try change(existing) } catch { throw Failure(path: shown) }
        if updated == existing { return }
        let mode = (try? manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func appURL(_ agent: MCPAgentApp) -> URL? {
        for id in agent.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        for name in agent.apps {
            for folder in folders {
                let url = folder.appendingPathComponent(name + ".app")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private func say(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
    }
}
