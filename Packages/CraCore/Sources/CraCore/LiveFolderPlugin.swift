import Foundation

public struct LiveFolderPluginManifest: Codable, Equatable {
    public struct Command: Codable, Equatable {
        public let title: String
        public let description: String
        public let triggers: [String]
    }
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let entry: String
    public let sessionOrigins: [String]
    public let legacySource: String?
    public let sessionSetting: String?
    public let legacyCommand: String?
    public let command: Command?

    public func validate() throws {
        guard !id.isEmpty, !id.hasPrefix("."), !id.hasSuffix("."), !id.contains(".."), id.utf8.allSatisfy({
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
        }) else { throw LiveFolderPluginError.invalidManifest("Invalid plugin ID") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !version.isEmpty else {
            throw LiveFolderPluginError.invalidManifest("Plugin name and version are required")
        }
        guard apiVersion == 1 else { throw LiveFolderPluginError.invalidManifest("Unsupported plugin API version") }
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
        guard entry.hasSuffix(".js"), !entry.contains("\\"), !entry.contains(":"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LiveFolderPluginError.invalidManifest("Entry must be a relative JavaScript file path")
        }
        for origin in sessionOrigins { _ = try LiveFolderSessionOrigin(origin) }
    }
}

public enum LiveFolderPluginError: Error, Equatable, LocalizedError {
    case invalidManifest(String)
    case invalidSessionOrigin(String)
    case executionFailed(String)
    case pluginFailed(String, [String: String])

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let message): return message
        case .invalidSessionOrigin(let origin): return "Invalid session origin: \(origin)"
        case .executionFailed(let message): return message
        case .pluginFailed(let message, _): return message
        }
    }
}

public struct LiveFolderSessionOrigin: Hashable {
    private let scheme: String
    private let host: String
    private let port: Int

    public init(_ value: String) throws {
        guard let components = URLComponents(string: value),
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil,
              let origin = Self.parts(components) else {
            throw LiveFolderPluginError.invalidSessionOrigin(value)
        }
        (scheme, host, port) = origin
    }

    public func permits(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let candidate = Self.parts(components) else { return false }
        return candidate == (scheme, host, port)
    }

    private static func parts(_ components: URLComponents) -> (String, String, Int)? {
        guard let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty, !host.contains("*"),
              components.user == nil, components.password == nil else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port) else { return nil }
        return (scheme, host, port)
    }
}
