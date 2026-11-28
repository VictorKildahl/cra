import CraCore
import Foundation
import Testing

/// Desktop apps' native messaging manifests Cra writes itself, for someone who never imported from a browser (#847).
struct KnownNativeHostsTests {
    static let helper = KnownNativeHosts.onePassword.paths[0]

    /// With nothing imported, Cra's folder had no 1Password manifest, so the extension's `connectNative` found no host
    /// and 1Password fell back to signing in on the web. With 1Password installed Cra writes the manifest 1Password
    /// writes for Chrome.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/847"))
    func onePasswordInstalledGetsItsManifestWithoutAnImport() throws {
        let written = KnownNativeHosts.manifests(linked: [], exists: { $0 == Self.helper })
        #expect(written.map(\.file) == ["com.1password.1password.json"])
        let manifest = try #require(try JSONSerialization.jsonObject(with: written[0].data) as? [String: Any])
        #expect(manifest["name"] as? String == "com.1password.1password")
        #expect(manifest["path"] as? String == Self.helper)
        #expect(manifest["type"] as? String == "stdio")
        let origins = try #require(manifest["allowed_origins"] as? [String])
        #expect(origins.contains("chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"), "the Web Store's 1Password")
        #expect(origins.count == 6)
    }

    /// Not installed: nothing written. Already linked from an imported browser, or the person's own file: that one
    /// stays, nothing written over it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/847"))
    func onlyWhenInstalledAndNotAlreadyThere() {
        #expect(KnownNativeHosts.manifests(linked: [], exists: { _ in false }).isEmpty)
        #expect(KnownNativeHosts.manifests(linked: ["com.1password.1password.json"], exists: { $0 == Self.helper }).isEmpty)
        #expect(KnownNativeHosts.manifests(linked: ["com.other.json"], exists: { $0 == Self.helper }).count == 1)
    }

    static let bitwardenProxy = "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy"

    /// Bitwarden also writes its manifest only into the browsers it knows, so with nothing imported from Chrome (or
    /// an import from Zen or Firefox) the extension found no desktop app and "Unlock with biometrics" stayed off.
    /// With Bitwarden installed Cra writes the manifest Bitwarden writes for Chrome: its `desktop_proxy` and the
    /// Chrome Web Store, Chrome beta, Edge and Opera extensions (Bitwarden's native-messaging.main.ts, 28 Nov 2026).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/920"), .bug("https://github.com/VictorKildahl/cra/issues/918"))
    func bitwardenInstalledGetsItsManifestWithoutAnImport() throws {
        let written = KnownNativeHosts.manifests(linked: [], exists: { $0 == Self.bitwardenProxy })
        #expect(written.map(\.file) == ["com.8bit.bitwarden.json"])
        let data = try #require(written.first?.data)
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(manifest["name"] as? String == "com.8bit.bitwarden")
        #expect(manifest["description"] as? String == "Bitwarden desktop <-> browser bridge")
        #expect(manifest["path"] as? String == Self.bitwardenProxy)
        #expect(manifest["type"] as? String == "stdio")
        #expect(manifest["allowed_origins"] as? [String] == [
            "chrome-extension://nngceckbapebfimnlniiiahkandclblb/", "chrome-extension://hccnnhgbibccigepcmlgppchkpfdophk/",
            "chrome-extension://jbkfoedolllekgbhcbcoahefnbanhhlh/", "chrome-extension://ccnckbpmaceehanjmeomladnmlffdjgn/",
        ])
    }

    /// A Bitwarden manifest already linked (from an imported Chrome, or the person's own copy) stays; with both apps
    /// installed and neither linked, both are written.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/920"))
    func bitwardenLinkedStaysAndBothAppsGetTheirs() {
        let both: (String) -> Bool = { $0 == Self.helper || $0 == Self.bitwardenProxy }
        #expect(KnownNativeHosts.manifests(linked: ["com.8bit.bitwarden.json"], exists: both).map(\.file) == ["com.1password.1password.json"])
        #expect(Set(KnownNativeHosts.manifests(linked: [], exists: both).map(\.file)) == ["com.1password.1password.json", "com.8bit.bitwarden.json"])
    }
}
