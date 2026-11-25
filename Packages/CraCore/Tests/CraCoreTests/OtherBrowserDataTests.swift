import CraCore
import Foundation
import Testing

/// GitHub #757: Cra's first launch showed macOS's "Data Access Blocked … tried to access your data
/// from other apps", because it read inside Chrome's and Brave's folders before anything was picked.
struct OtherBrowserDataTests {
    static let support = "/Users/me/Library/Application Support"
    static let chrome = OtherBrowserData.Browser(id: "chrome", folder: "\(support)/Google/Chrome",
                                                 nativeMessagingHosts: "\(support)/Google/Chrome/NativeMessagingHosts")
    static let brave = OtherBrowserData.Browser(id: "brave", folder: "\(support)/BraveSoftware/Brave-Browser",
                                                nativeMessagingHosts: "\(support)/BraveSoftware/Brave-Browser/NativeMessagingHosts")
    static let arc = OtherBrowserData.Browser(id: "arc", folder: "\(support)/Arc",
                                              nativeMessagingHosts: "\(support)/Arc/User Data/NativeMessagingHosts")
    static let firefox = OtherBrowserData.Browser(id: "firefox", folder: "\(support)/Firefox")
    static let safari = OtherBrowserData.Browser(id: "safari", folder: "/Users/me/Library/Safari", alwaysOffered: true)
    static let all = [arc, chrome, brave, firefox, safari]
    static let system = ["/Library/Google/Chrome/NativeMessagingHosts"]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/757"))
    func importListLooksOnlyAtEachBrowsersOwnFolder() {
        var asked: [String] = []
        let there: Set = [Self.chrome.folder, Self.arc.folder]
        let offered = OtherBrowserData.offered(Self.all) { asked.append($0); return there.contains($0) }
        #expect(offered == ["arc", "chrome", "safari"])
        #expect(asked == [Self.arc.folder, Self.chrome.folder, Self.brave.folder, Self.firefox.folder],
                "only the folders themselves: nothing inside them, and Safari's not at all")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/757"))
    func connectorsComeOnlyFromSystemFoldersAndImportedBrowsers() {
        #expect(OtherBrowserData.nativeMessagingFolders(Self.all, imported: ImportedBrowsers(), system: Self.system) == Self.system,
                "a new Mac reads no browser's folder at launch")
        let imported = ImportedBrowsers(ids: ["arc", "chrome"])
        #expect(OtherBrowserData.nativeMessagingFolders(Self.all, imported: imported, system: Self.system)
                == [Self.chrome.nativeMessagingHosts!, Self.arc.nativeMessagingHosts!] + Self.system,
                "Chrome first, where every app installs, then the other imported browsers, then the system")
        #expect(OtherBrowserData.nativeMessagingFolders(Self.all, imported: ImportedBrowsers(ids: ["firefox"]), system: [])
                .isEmpty, "a browser without manifests adds nothing")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/757"))
    func crasFromBeforeTheFixKeepTheirConnectors() {
        let links = ["\(Self.support)/Google/Chrome/NativeMessagingHosts/com.1password.1password.json",
                     "\(Self.support)/Arc/User Data/NativeMessagingHosts/com.bitwarden.desktop.json",
                     "/Library/Google/Chrome/NativeMessagingHosts/com.example.json"]
        #expect(ImportedBrowsers.migrated(linkTargets: links, browsers: Self.all) == ImportedBrowsers(ids: ["arc", "chrome"]),
                "the browsers Cra's links already point into, in import order")
        #expect(ImportedBrowsers.migrated(linkTargets: [], browsers: Self.all) == ImportedBrowsers())
        #expect(ImportedBrowsers.migrated(linkTargets: ["\(Self.support)/Google/ChromeCanary/NativeMessagingHosts/a.json"],
                                          browsers: Self.all) == ImportedBrowsers(), "a folder that only starts the same isn't Chrome's")
    }

    @Test func importedBrowsersKeepOneEntryEach() {
        let list = ImportedBrowsers(ids: ["chrome", "arc", "chrome"])
        #expect(list.ids == ["chrome", "arc"])
        #expect(list.adding("arc") == list && list.adding("dia").ids == ["chrome", "arc", "dia"])
        #expect(list.contains("arc") && !list.contains("brave"))
    }
}
