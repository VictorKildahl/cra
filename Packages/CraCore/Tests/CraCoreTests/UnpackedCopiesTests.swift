import CraCore
import Foundation
import Testing

/// A copy in Extensions/ steps aside for the same extension loaded in place (GitHub #299).
struct UnpackedCopiesTests {
    let copyPath = "/Users/me/Library/Application Support/Cra/Extensions/my-extension"
    let copyID = "jmeeejjnkkghibefjnhgmkdjgkhmdbfh"
    let originalID = "igfpoiabpjinnjoopogaffjhdcgmkapk"
    let manifests = ["/Users/me/code/my-extension": "My Extension", "/Users/me/code/other/my-extension": "Something Else"]

    func loadedInPlace(folder: String = "my-extension", copyID: String? = nil, name: String? = "My Extension",
                       _ settings: [String: Any]) -> Bool {
        UnpackedCopies.isLoadedInPlace(copyFolder: folder, copyPath: copyPath, copyExtensionID: copyID ?? self.copyID,
                                       copyName: name, settings: settings) { manifests[$0] }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func addUnpackedCopyOfAFolderLoadedInPlace() {
        let unpacked: [String: Any] = [originalID: ["location": 4, "path": "/Users/me/code/my-extension"]]
        #expect(loadedInPlace(unpacked), "chrome://extensions loads the folder Add Unpacked Extension… copied")
        #expect(loadedInPlace(folder: "my-extension-2", unpacked), "the second copy of a name")
        #expect(!loadedInPlace(folder: "my-extension-x", unpacked))
        #expect(!loadedInPlace(folder: "my-extension-1", unpacked), "Add Unpacked Extension… numbers from 2")
        #expect(!loadedInPlace(name: "Another Extension", unpacked), "a different extension in a folder of the same name")
        #expect(!loadedInPlace(name: nil, unpacked))
        #expect(!loadedInPlace([originalID: ["location": 4, "path": "/Users/me/code/other/my-extension"]]),
                "same folder name, another extension")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func importedCopyIsNamedAfterTheOriginalsID() {
        let settings: [String: Any] = [originalID: ["location": 4, "path": "/Users/me/code/renamed"]]
        #expect(loadedInPlace(folder: originalID, name: "Whatever", settings), "the import names the copy after the source's ID")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func aManifestKeyGivesBothTheSameID() {
        let settings: [String: Any] = [copyID: ["location": 4, "path": "/Users/me/code/dist/chrome"]]
        #expect(loadedInPlace(name: "Lumno", settings))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func onlyAnUnpackedInstallFromElsewhereCounts() {
        #expect(!loadedInPlace([copyID: ["location": 8, "path": copyPath]]), "the copy's own --load-extension install")
        #expect(!loadedInPlace([copyID: ["location": 4, "path": copyPath + "/"]]), "the copy itself loaded unpacked")
        #expect(!loadedInPlace([copyID: ["location": 1, "path": "\(copyID)/1.0_0"]]), "a Web Store install (#203 handles those)")
        #expect(!loadedInPlace([originalID: ["location": 4, "path": "relative/my-extension"]]))
        #expect(!loadedInPlace([originalID: "not a dictionary"]))
        #expect(!loadedInPlace([:]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func theCopyStopsLoadingInThatProfileOnly() {
        var scopes = ExtensionProfiles()
        let all: Set<String> = ["Default", "Profile 1"]
        let goneAfterDefault = scopes.stopsLoading(folder: "my-extension", inProfile: "Default", allProfiles: all)
        #expect(!goneAfterDefault)
        #expect(scopes.commandLineValue(forFolders: ["my-extension"]) == "Profile 1")
        let goneAfterBoth = scopes.stopsLoading(folder: "my-extension", inProfile: "Profile 1", allProfiles: all)
        #expect(goneAfterBoth, "loads nowhere: the copy can go")
        #expect(scopes.folders.isEmpty)
    }
}
