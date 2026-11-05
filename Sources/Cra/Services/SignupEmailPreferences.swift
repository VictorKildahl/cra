import Foundation

/// One explicit, local choice in each Chromium profile. ProfileCleanup removes it with that
/// profile. Incognito callers must skip lookup because their Chromium path can also be nil.
@MainActor
enum SignupEmailPreferences {
    static let didChange = Notification.Name("CraSignupEmailDidChange")
    private static var addresses: [URL: String] = [:]

    static func address(profilePath: String?) -> String? {
        let url = file(profilePath)
        if let cached = addresses[url] { return cached.isEmpty ? nil : cached }
        let value = (try? String(contentsOf: url, encoding: .utf8)).flatMap(SignupEmail.address)
        addresses[url] = value ?? ""
        return value
    }

    static func set(_ text: String, profilePath: String?) throws {
        let url = file(profilePath)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else {
            guard let address = SignupEmail.address(trimmed) else { throw CocoaError(.formatting) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(address.utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        addresses[url] = trimmed
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func file(_ path: String?) -> URL {
        let folder = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        return folder.appendingPathComponent("Cra Signup Email")
    }
}
