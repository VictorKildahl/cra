import AppKit
import Darwin
import Security

/// Who is on the other end of an MCP connection: the program that started the `Cra --mcp`
/// bridge (Claude Code, Cursor…), told apart by its code-signing team (or its path when it
/// isn't signed), and the app it runs in, for the approval prompt.
struct MCPPeer {
    /// Team ID of the launcher's signature, or its executable path.
    let signer: String
    /// The nearest app bundle above the bridge ("Visual Studio Code", "Terminal"), or "".
    let via: String

    /// The peer of an accepted Unix socket, from its process id (LOCAL_PEERPID).
    static func of(socket fd: Int32) -> MCPPeer {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return MCPPeer(signer: "unknown", via: "") }
        // The bridge is Cra itself; what launched it is the agent.
        let launcher = parent(of: pid) ?? pid
        let signer = teamID(of: launcher).map { "team:" + $0 } ?? path(of: launcher).map { "path:" + $0 } ?? "unknown"
        var via = ""
        var current: pid_t? = launcher
        for _ in 0..<12 {
            guard let process = current, process > 1 else { break }
            if let name = appName(containing: path(of: process)) { via = name; break }
            current = parent(of: process)
        }
        return MCPPeer(signer: signer, via: via)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func teamID(of pid: pid_t) -> String? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The name of the outermost .app bundle around an executable path.
    private static func appName(containing path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        let info = Bundle(path: bundle)?.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String
            ?? URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
    }
}
