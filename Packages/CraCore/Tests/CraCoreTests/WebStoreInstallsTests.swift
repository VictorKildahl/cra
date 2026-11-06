import CraCore
import Foundation
import Testing

/// Imported Web Store extensions become the store's own installs (GitHub #203).
struct WebStoreInstallsTests {
    let id = "bcjindcccaagfpapjjmafapmmgkkhgoa"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/203"))
    func onlyStoreCopiesNamedAfterTheirID() {
        let store = WebStoreInstalls.storeUpdateURL
        #expect(WebStoreInstalls.isWebStoreCopy(folder: id, extensionID: id, updateURL: store))
        #expect(WebStoreInstalls.isWebStoreCopy(folder: id, extensionID: id, updateURL: store + "/"))
        #expect(WebStoreInstalls.isWebStoreCopy(folder: id, extensionID: id, updateURL: "http://clients2.google.com/service/update2/crx"))
        #expect(!WebStoreInstalls.isWebStoreCopy(folder: id, extensionID: id, updateURL: nil), "an unpacked extension of someone's own")
        #expect(!WebStoreInstalls.isWebStoreCopy(folder: id, extensionID: id, updateURL: "https://example.com/updates.xml"),
                "self-hosted updates are not the store's")
        #expect(!WebStoreInstalls.isWebStoreCopy(folder: "my-extension", extensionID: id, updateURL: store),
                "Add Unpacked Extension… copies keep their folder name")
        #expect(!WebStoreInstalls.isWebStoreCopy(folder: "x", extensionID: "x", updateURL: store), "not an extension ID")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/203"))
    func storeInstallsAreInternalFromTheWebStore() {
        #expect(WebStoreInstalls.isStoreInstall(settings: ["location": 1, "from_webstore": true]))
        #expect(!WebStoreInstalls.isStoreInstall(settings: ["location": 8, "from_webstore": false]), "--load-extension")
        #expect(!WebStoreInstalls.isStoreInstall(settings: ["location": 4]), "unpacked")
        #expect(!WebStoreInstalls.isStoreInstall(settings: ["location": 1, "from_webstore": false]), "an off-store CRX")
        #expect(!WebStoreInstalls.isStoreInstall(settings: nil))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/203"))
    func pendingWhereTheFolderLoadsAndTheStoreHasNotInstalledIt() {
        let profiles = ["Default", "Profile 1", "Profile 2"]
        let settings: [String: [String: Any]] = [
            "Default": [id: ["location": 8]],
            "Profile 1": [id: ["location": 1, "from_webstore": true]],
        ]
        let everywhere = WebStoreInstalls.pendingProfiles(folder: id, extensionID: id, scopes: ExtensionProfiles(),
                                                          profiles: profiles, settings: { settings[$0] ?? [:] })
        #expect(everywhere == ["Default", "Profile 2"])
        let scoped = WebStoreInstalls.pendingProfiles(folder: id, extensionID: id, scopes: ExtensionProfiles(folders: [id: ["Profile 1"]]),
                                                      profiles: profiles, settings: { settings[$0] ?? [:] })
        #expect(scoped.isEmpty, "loads only where the store already has it")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/203"))
    func folderStopsLoadingWhereTheStoreHasIt() {
        var scopes = ExtensionProfiles()
        let all: Set<String> = ["Default", "Profile 1"]
        let goneAfterDefault = scopes.movedToWebStore(folder: id, profile: "Default", allProfiles: all)
        #expect(!goneAfterDefault)
        #expect(scopes.folders[id] == ["Profile 1"], "a folder that loaded everywhere keeps the other profiles")
        #expect(scopes.commandLineValue(forFolders: [id]) == "Profile 1")
        let goneAfterBoth = scopes.movedToWebStore(folder: id, profile: "Profile 1", allProfiles: all)
        #expect(goneAfterBoth, "loads nowhere: the folder can go")
        #expect(scopes.folders[id] == nil)

        var listed = ExtensionProfiles(folders: [id: ["Profile 2"]])
        let gone = listed.movedToWebStore(folder: id, profile: "Profile 2", allProfiles: all)
        #expect(gone)
        #expect(listed.folders.isEmpty)
    }
}
