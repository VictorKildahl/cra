import CraCore
import Foundation
import Testing

/// Extensions and sign-ins follow the Arc profile a space was on (GitHub #131).
struct ExtensionProfilesTests {
    @Test func aFolderWithoutAListLoadsEverywhere() {
        let p = ExtensionProfiles(folders: ["a": ["Profile 1"]])
        #expect(p.loads(folder: "b", inProfile: "Default") && p.profiles(ofFolder: "b") == nil)
        #expect(p.loads(folder: "a", inProfile: "Profile 1") && !p.loads(folder: "a", inProfile: "Default"))
    }

    @Test func importAddsProfiles() {
        var p = ExtensionProfiles()
        p.add(folder: "a", profiles: ["Profile 1"], folderExisted: false)
        p.add(folder: "a", profiles: ["Default"], folderExisted: true)
        #expect(p.folders["a"] == ["Default", "Profile 1"], "a second import adds its profiles")
        p.add(folder: "b", profiles: ["Profile 1"], folderExisted: true)
        #expect(p.profiles(ofFolder: "b") == nil, "an extension already loading everywhere keeps doing so")
        p.add(folder: "a", profiles: nil, folderExisted: true)
        #expect(p.profiles(ofFolder: "a") == nil, "imported for every profile: the list goes")
        p.add(folder: "c", profiles: ["Profile 2"], folderExisted: false)
        p.remove(folder: "c")
        #expect(p.folders.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func commandLineFollowsTheLoadExtensionOrder() {
        let p = ExtensionProfiles(folders: ["b": ["Profile 2", "Default"]])
        #expect(p.commandLineValue(forFolders: ["a", "b", "c"]) == "*,Default|Profile 2,*")
        #expect(p.commandLineValue(forFolders: ["a", "c"]) == nil, "no switch when every folder loads everywhere")
        #expect(ExtensionProfiles(folders: ["a": []]).commandLineValue(forFolders: ["a"]) == "", "an empty list loads nowhere")
    }

    @Test func savedAsAPlainObject() throws {
        let p = ExtensionProfiles(folders: ["a": ["Default"]])
        #expect(String(decoding: try JSONEncoder().encode(p), as: UTF8.self) == #"{"a":["Default"]}"#)
        #expect(try JSONDecoder().decode(ExtensionProfiles.self, from: Data("{}".utf8)) == ExtensionProfiles())
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func arcSpaceProfiles() throws {
        func parse(_ json: String) throws -> String? {
            ImportProfileMap.arcProfileFolder(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        }
        #expect(try parse(#"{"custom": {"_0": {"directoryBasename": "Profile 2", "machineID": "m"}}}"#) == "Profile 2")
        #expect(try parse(#"{"default": true}"#) == nil)
        #expect(try parse(#"{"custom": {"_0": {"directoryBasename": "Default"}}}"#) == nil)
        #expect(ImportProfileMap.arcProfileFolder(nil) == nil)
        #expect(try parse(#"{"custom": {"_0": {"directoryBasename": "Profile 2/../../x"}}}"#) == nil, "never a path out of User Data")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func importedExtensionsGoWhereTheirProfilesWent() {
        let map = ImportProfileMap(folders: ["Profile 2": "Profile A", "Profile 7": "Profile B"])
        let all: Set<String> = ["Default", "Profile A", "Profile B"]
        #expect(map.craFolder(forSource: "Profile 2") == "Profile A")
        #expect(map.craFolder(forSource: "Profile 5") == "Default", "a profile no imported space uses goes to Default")
        #expect(map.craFolder(forSource: nil) == "Default")
        #expect(map.extensionProfiles(sources: ["Profile 2"], allFolders: all) == ["Profile A"])
        #expect(map.extensionProfiles(sources: ["Profile 2", "Profile 5"], allFolders: all) == ["Profile A", "Default"])
        #expect(map.extensionProfiles(sources: ["Default", "Profile 2", "Profile 7"], allFolders: all) == nil,
                "in every profile: loads everywhere, as before")
        #expect(ImportProfileMap(folders: ["Default": "Default"]).extensionProfiles(sources: ["Profile 3"], allFolders: all) == nil,
                "an import that bound no profiles changes nothing")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func importedPinsSeedOnlyNewLists() {
        var pins = PinnedExtensions(shared: ["a"])
        pins.seed(["b", "c"], inProfile: "Profile A")
        pins.seed(["a"], inProfile: "Profile B")
        pins.seed(["z"], inProfile: "Profile A")
        #expect(pins.ids(inProfile: "Profile A") == ["b", "c"])
        #expect(pins.profiles["Profile B"] == nil, "the same list as everyone's stays shared")
    }

    /// Rebuild from Arc (#131): spaces an older import left on Default go back to their Arc profiles.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func rebuildMatchesSpacesByName() {
        let home = UUID(), work = UUID(), client = UUID(), mine = UUID(), twin1 = UUID(), twin2 = UUID(), shared = UUID()
        let cra = [
            ArcProfileRebuild.CraSpace(id: home, title: "Home", movable: true),
            .init(id: work, title: "work", movable: true),
            .init(id: client, title: "Client", movable: false),
            .init(id: mine, title: "Mine", movable: true),
            .init(id: twin1, title: "Twin", movable: true), .init(id: twin2, title: "Twin", movable: true),
            .init(id: shared, title: "Shared", movable: true),
        ]
        let arc = [
            ArcProfileRebuild.ArcSpace(title: "Home", folder: nil, name: "Personal"),
            .init(title: "Work", folder: "Profile 2", name: "Work"),
            .init(title: "Client", folder: "Profile 3", name: "Client"),
            .init(title: "Twin", folder: "Profile 2", name: "Work"),
            .init(title: "Shared", folder: "Profile 2", name: "Work"), .init(title: "Shared", folder: "Profile 3", name: "Client"),
        ]
        let moves = ArcProfileRebuild.moves(cra: cra, arc: arc)
        #expect(moves.map(\.spaceID) == [work], "only a movable space whose name is one Arc space's on a profile")
        #expect(moves.first?.folder == "Profile 2" && moves.first?.profileName == "Work" && moves.first?.spaceTitle == "work")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func rebuildKeepsExtensionsInProfilesMadeInCra() {
        let map = ImportProfileMap(folders: ["Default": "Default", "Profile 2": "Profile W"])
        let all: Set<String> = ["Default", "Profile W", "Profile Mine"]
        #expect(map.extensionProfiles(sources: ["Profile 2"], allFolders: all, keepUnmapped: true) == ["Profile W", "Profile Mine"])
        #expect(map.extensionProfiles(sources: ["Default"], allFolders: all, keepUnmapped: true) == ["Default", "Profile Mine"])
        #expect(map.extensionProfiles(sources: ["Default", "Profile 2"], allFolders: all, keepUnmapped: true) == nil)
        #expect(map.extensionProfiles(sources: [], allFolders: all, keepUnmapped: true) == nil, "not in Arc: left alone")
    }
}
