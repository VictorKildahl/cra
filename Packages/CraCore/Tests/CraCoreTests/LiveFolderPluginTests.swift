import CraCore
import Foundation
import Testing

struct LiveFolderPluginTests {
    @Test func packageRejectsEscapingSymlinksAndCatalogKeepsValidPackages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid")
        let invalid = root.appendingPathComponent("invalid")
        for directory in [valid, invalid] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(#"{"id":"test.plugin","name":"Test","version":"1","apiVersion":1,"entry":"main.js","sessionOrigins":[]}"#.utf8)
                .write(to: directory.appendingPathComponent("manifest.json"))
        }
        try Data("return {};".utf8).write(to: valid.appendingPathComponent("main.js"))
        try FileManager.default.createSymbolicLink(at: invalid.appendingPathComponent("main.js"), withDestinationURL: valid.appendingPathComponent("main.js"))
        #expect(throws: LiveFolderPluginError.self) { try LiveFolderPluginPackage(directory: invalid) }
        let catalog = LiveFolderPluginCatalog(directories: [invalid, valid, valid])
        #expect(catalog.packages.count == 1 && catalog.failures.count == 2)
    }

    /// An app run from a path under /private (App Translocation from Downloads or the DMG,
    /// /private/tmp) saw its own GitHub and GitLab plugins as installed ones and refused them:
    /// the package path is resolved to /tmp/…, the bundle's path is not.
    @Test func builtInPluginsStayBuiltInUnderASymlinkedPath() throws {
        let root = URL(fileURLWithPath: "/private/tmp/cra-plugins-\(UUID().uuidString)/Resources/live-folder-plugins")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
        let github = root.appendingPathComponent("github")
        try FileManager.default.createDirectory(at: github, withIntermediateDirectories: true)
        try Data(#"{"id":"cra.github","name":"GitHub","version":"1","apiVersion":1,"entry":"main.js","sessionOrigins":[]}"#.utf8)
            .write(to: github.appendingPathComponent("manifest.json"))
        try Data("return {};".utf8).write(to: github.appendingPathComponent("main.js"))
        let package = try LiveFolderPluginPackage(directory: github)
        #expect(package.isInside(root))
        #expect(package.isInside(root.deletingLastPathComponent()))
        #expect(!package.isInside(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")))
    }

    @Test func pluginConfigurationRoundTripsWithSessionIsolation() throws {
        var folder = LiveFolderData()
        folder.plugin = LiveFolderPluginConfiguration(id: "custom.feed", settings: ["server": "https://example.test:8443/app"],
            filters: ["unread"], sessionOrigins: ["https://example.test:8443"])
        let restored = try JSONDecoder().decode(LiveFolderData.self, from: JSONEncoder().encode(folder))
        #expect(restored == folder)
        #expect(LiveFolderPluginConfiguration.normalizedAddress(" HTTPS://Example.test:443/app/ ") == "https://example.test/app")
        #expect(LiveFolderPluginConfiguration.normalizedAddress("https://user:secret@example.test") == nil)
    }

    @Test func sessionRequestsStayOnTheGrantedOrigin() throws {
        let origin = try LiveFolderSessionOrigin("https://git.example.test:8443")
        #expect(origin.permits(URL(string: "https://git.example.test:8443/api/v4/user")!))
        for address in ["http://git.example.test:8443/api", "https://git.example.test/api",
                        "https://sub.git.example.test:8443/api", "https://git.example.test.evil.test:8443/api",
                        "https://git.example.test:8443@evil.test/api", "file:///api",
                        "https://user:password@git.example.test:8443/api"] {
            #expect(!origin.permits(URL(string: address)!))
        }
    }

    @Test func defaultPortsAndHostCaseAreEquivalent() throws {
        let origin = try LiveFolderSessionOrigin("https://GIT.EXAMPLE.TEST/")
        #expect(origin.permits(URL(string: "https://git.example.test:443/api")!))
        #expect(!origin.permits(URL(string: "https://git.example.test:444/api")!))
    }

    @Test func originsCannotContainPathsOrCredentials() {
        for value in ["https://*.example.test", "https://example.test/path", "https://example.test?x=1",
                      "https://example.test#fragment", "https://user@example.test", "file://example.test",
                      "example.test", "https://example.test:0"] {
            #expect(throws: LiveFolderPluginError.self) { try LiveFolderSessionOrigin(value) }
        }
    }

    @Test func manifestRejectsUnsupportedVersionsAndEscapingEntries() throws {
        func manifest(entry: String = "main.js", apiVersion: Int = 1) throws -> LiveFolderPluginManifest {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": "cra.gitlab", "name": "GitLab", "version": "1.0.0",
                "apiVersion": apiVersion, "entry": entry, "sessionOrigins": ["https://gitlab.com"]
            ])
            return try JSONDecoder().decode(LiveFolderPluginManifest.self, from: data)
        }
        try manifest().validate()
        for entry in ["../main.js", "/main.js", "lib/../../main.js", "lib\\main.js", "https://example.test/main.js", ""] {
            #expect(throws: LiveFolderPluginError.self) { try manifest(entry: entry).validate() }
        }
        #expect(throws: LiveFolderPluginError.self) { try manifest(apiVersion: 2).validate() }
    }
}
