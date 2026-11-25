import CraCEF
import Darwin
import Foundation

/// Runs the user's ABP rules in Chromium's own request pipeline. The signed bundle supplies
/// the extension code. The native host streams selected rule snapshots from the local data folder.
enum ChromiumFilterLists {
    static let extensionID = "nddccjlgchhhajchaphmkffkclfmcemb"
    static let origin = "chrome-extension://" + extensionID + "/"
    private static let host = "dk.kildahl.cra.filters"
    static var directory: URL { AppPaths.supportDir.appendingPathComponent("NetworkFilters", isDirectory: true) }
    static var available = false // set once before Chromium starts

    static func install() throws -> String {
        let fm = FileManager.default
        let dir = directory
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("blocklist/chromium"),
              let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: dir.appendingPathComponent("revision.json").path) { try publish([]) }
        let manifest: [String: Any] = ["name": host, "description": "Cra filter list updates", "path": executable.path,
                                       "type": "stdio", "allowed_origins": [origin]]
        let hosts = AppPaths.chromiumCache.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        try fm.createDirectory(at: hosts, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: hosts.appendingPathComponent(host + ".json"), options: .atomic)
        setenv("CRA_NETWORK_FILTER_DIR", dir.path, 1)
        available = true
        return source.path
    }

    /// The published framework can provision the startup profile through the installer.
    /// New frameworks set this choice during command-line installation for each profile.
    @MainActor static func finishStartupProfileInstall() {
        let marker = directory.appendingPathComponent("provisioned")
        guard available, !CraCEFRuntime.responds(to: NSSelectorFromString("setBundledNetworkRulesExpected:")),
              !CommandLine.arguments.contains("--force-enterprise-isolated-mode"),
              !FileManager.default.fileExists(atPath: marker.path),
              let source = Bundle.main.resourceURL?.appendingPathComponent("blocklist/chromium") else { return }
        Task {
            for _ in 0..<25 {
                let state = try? Data(contentsOf: AppPaths.chromiumCache.appendingPathComponent("Local State"))
                let local = state.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let name = (local?["profile"] as? [String: Any])?["last_used"] as? String ?? "Default"
                let path = name == "Default" ? nil : AppPaths.chromiumCache.appendingPathComponent(name).path
                if let json = CraCEFRuntime.extensionSettings(forProfile: path),
                   let records = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                   let entry = records[extensionID] as? [String: Any] {
                    guard entry["incognito"] == nil, entry["isolated_mode"] == nil,
                          CraCEFRuntime.preference("enterprise.isolated_mode", forProfile: path) != "1",
                          let params = try? JSONSerialization.data(withJSONObject: [
                            "path": source.path, "enableInIncognito": true
                          ]) else { return }
                    CraCEFRuntime.sendBrowserDevToolsMethod("Extensions.loadUnpacked", params: String(decoding: params, as: UTF8.self)) { result, error in
                        if error == nil, result?.contains(extensionID) == true {
                            try? Data().write(to: marker, options: .atomic)
                        }
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private struct Snapshot: Encodable {
        let revision: String
        let rules: [DesktopNetworkRules.Rule]
        let siteExceptions: [DesktopNetworkRules.Rule]
    }

    /// Publish the notification last, so readers always have a complete replacement.
    @discardableResult
    static func publish(_ rules: [DesktopNetworkRules.Rule], siteExceptions: [DesktopNetworkRules.Rule] = []) throws -> String {
        let revision = UUID().uuidString
        let encoder = JSONEncoder()
        try encoder.encode(Snapshot(revision: revision, rules: rules, siteExceptions: siteExceptions)).write(to: directory.appendingPathComponent("rules.json"), options: .atomic)
        try encoder.encode(["revision": revision]).write(to: directory.appendingPathComponent("revision.json"), options: .atomic)
        expectNetworkRules(!rules.isEmpty)
        return revision
    }

    /// Frameworks that provision the helper per profile also wait for its first
    /// ruleset before navigating in a new profile. The setter is thread-safe.
    static func expectNetworkRules(_ expected: Bool) {
        let selector = NSSelectorFromString("setBundledNetworkRulesExpected:")
        if CraCEFRuntime.responds(to: selector) {
            CraCEFRuntime.setBundledNetworkRulesExpected(expected)
        }
    }

    static func isCurrent(_ revision: String) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("revision.json")) else { return false }
        return (try? JSONDecoder().decode([String: String].self, from: data))?["revision"] == revision
    }

    /// Chromium launches the app executable in native-messaging mode. Exit with the port,
    /// independently of every browser window. Messages never contain a visited URL.
    static func watch() -> Never {
        guard let path = ProcessInfo.processInfo.environment["CRA_NETWORK_FILTER_DIR"] else { exit(1) }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { exit(1) }
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        let queue = DispatchQueue(label: "dk.kildahl.cra.filter-notifications")
        let events = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        let pending = DispatchSource.makeTimerSource(queue: queue)
        var last = Data()
        var awaiting: String?
        func send(_ payload: Data) {
            var size = UInt32(payload.count).littleEndian
            do {
                try output.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) } + payload)
            } catch { exit(0) }
        }
        // A message from a native host is limited to 1 MiB. Read one atomic
        // file version, in chunks small enough even after Base64 encoding.
        func sendSnapshot(_ revision: String) {
            do {
                let file = try FileHandle(forReadingFrom: dir.appendingPathComponent("rules.json"))
                defer { try? file.close() }
                while let chunk = try file.read(upToCount: 384 * 1024), !chunk.isEmpty {
                    send(try JSONEncoder().encode(["id": revision, "chunk": chunk.base64EncodedString()]))
                }
                send(try JSONEncoder().encode(["id": revision, "done": "1"]))
            } catch {
                send(Data("{\"id\":\"\(revision)\",\"error\":true}".utf8))
            }
        }
        func notify() {
            guard let contents = try? Data(contentsOf: dir.appendingPathComponent("revision.json")),
                  contents != last,
                  let revision = (try? JSONDecoder().decode([String: String].self, from: contents))?["revision"],
                  UUID(uuidString: revision) != nil else { return }
            last = contents
            awaiting = revision
            send(contents)
            sendSnapshot(revision)
            // A newly started background worker can defer promise continuations
            // until its next port event. Wake it only while this update is pending.
            pending.schedule(deadline: .now() + 1, repeating: 1)
        }
        pending.setEventHandler { send(Data("{}".utf8)) }
        pending.resume()
        events.setEventHandler { notify() }
        events.resume()
        queue.async { notify() }
        // The helper reports the outcome of Chromium’s atomic update.
        func read(_ length: Int) -> Data? {
            var data = Data()
            while data.count < length {
                guard let chunk = try? input.read(upToCount: length - data.count), !chunk.isEmpty else { return nil }
                data.append(chunk)
            }
            return data
        }
        while let header = read(4) {
            let size = header.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
            guard (1...256).contains(size), let payload = read(size) else { break }
            guard let reply = try? JSONDecoder().decode([String: String].self, from: payload), reply.count == 1,
                  let (status, revision) = reply.first, UUID(uuidString: revision) != nil else { continue }
            switch status {
            case "applied", "failed":
                queue.sync {
                    guard awaiting == revision else { return }
                    pending.schedule(deadline: .distantFuture)
                    awaiting = nil
                    try? Data(revision.utf8).write(to: dir.appendingPathComponent(status), options: .atomic)
                }
            default: continue
            }
        }
        exit(0)
    }
}
