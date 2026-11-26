import Foundation

/// Desktop apps whose browser extension reaches them through a native messaging host, and that install the host's
/// manifest only into the browsers they know, never into Cra's profile. Cra links other browsers' manifests only for
/// the browsers the person imported from (reading Chrome's folder unasked set off macOS's "Data Access Blocked",
/// #757), so someone who never imported had no 1Password connection: the extension found no host and fell back to
/// signing in on the web (#847). For these apps Cra writes the manifest itself when the app's helper is installed,
/// with what the app writes for Chrome; a manifest linked from a browser, or the person's own file, comes first.
public enum KnownNativeHosts {
    public struct Host: Equatable, Sendable {
        /// The host's name, which the extension passes to `connectNative`; the manifest is `<name>.json`.
        public let name: String
        public let description: String
        /// The helper, as the app installs it; the first one that exists goes in the manifest.
        public let paths: [String]
        public let allowedOrigins: [String]

        public var fileName: String { name + ".json" }

        /// The manifest, as Chromium reads it (and as the app writes it for Chrome), for the helper at `path`.
        public func manifest(path: String) -> Data {
            let object: [String: Any] = [
                "name": name, "description": description, "path": path, "type": "stdio", "allowed_origins": allowedOrigins,
            ]
            return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        }
    }

    /// 1Password 8, from the manifest it installs for Chrome (26 Nov 2026): its extensions' ids, the Web Store's
    /// aeblfdkhhhdcdjpifhhbdiojplfjncoa among them, and its Browser Helper inside 1Password.app.
    public static let onePassword = Host(
        name: "com.1password.1password", description: "1Password BrowserSupport",
        paths: ["/Applications/1Password.app/Contents/Library/LoginItems/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport"],
        allowedOrigins: [
            "chrome-extension://hjlinigoblmkhjejkmbegnoaljkphmgo/", "chrome-extension://bkpbhnjcbehoklfkljkkbbmipaphipgl/",
            "chrome-extension://gejiddohjgogedgjnonbofjigllpkmbf/", "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/",
            "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/", "chrome-extension://dppgmdbiimibapkepcbdbmkaabgiofem/",
        ])

    public static let all: [Host] = [onePassword]

    /// The manifests Cra writes: each known host whose helper `exists`, unless `linked` (the file names already in
    /// Cra's NativeMessagingHosts folder: linked from a browser, or the person's own) has it. File name → contents.
    public static func manifests(linked: Set<String>, exists: (String) -> Bool, hosts: [Host] = all) -> [(file: String, data: Data)] {
        hosts.compactMap { host in
            guard !linked.contains(host.fileName), let path = host.paths.first(where: exists) else { return nil }
            return (host.fileName, host.manifest(path: path))
        }
    }
}
