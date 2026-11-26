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
        #expect(KnownNativeHosts.manifests(linked: ["com.1password.1password.json"], exists: { _ in true }).isEmpty)
        #expect(KnownNativeHosts.manifests(linked: ["com.other.json"], exists: { $0 == Self.helper }).count == 1)
    }
}
