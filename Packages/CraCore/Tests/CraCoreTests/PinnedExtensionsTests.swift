import CraCore
import Foundation
import Testing

/// Pinned extensions belong to a profile, like Arc's (GitHub #107).
struct PinnedExtensionsTests {
    /// The list Cra kept before #107 serves every profile until one changes its own.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func oldListServesEveryProfile() throws {
        let pins = try JSONDecoder().decode(PinnedExtensions.self, from: Data(#"["a","b"]"#.utf8))
        #expect(pins.ids(inProfile: "Default") == ["a", "b"])
        #expect(pins.ids(inProfile: "Profile 1") == ["a", "b"])
        // Written back unchanged.
        #expect(String(decoding: try JSONEncoder().encode(pins), as: UTF8.self) == #"["a","b"]"#)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func pinningInOneProfileLeavesTheOthers() {
        var pins = PinnedExtensions(shared: ["a", "b"])
        pins.setPinned("c", true, inProfile: "Profile 1")
        pins.setPinned("a", false, inProfile: "Profile 1")
        #expect(pins.ids(inProfile: "Profile 1") == ["b", "c"])
        #expect(pins.ids(inProfile: "Default") == ["a", "b"])
        #expect(pins.isPinned("c", inProfile: "Profile 1"))
        #expect(!pins.isPinned("c", inProfile: "Default"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func noChangeKeepsTheSharedList() {
        var pins = PinnedExtensions(shared: ["a"])
        pins.setPinned("a", true, inProfile: "Default")
        pins.setPinned("z", false, inProfile: "Default")
        pins.move("z", to: 0, inProfile: "Default")
        #expect(pins.profiles.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func moveReordersOneProfile() {
        var pins = PinnedExtensions(shared: ["a", "b", "c"])
        pins.move("c", to: 0, inProfile: "Default")
        pins.move("a", to: 99, inProfile: "Default")
        #expect(pins.ids(inProfile: "Default") == ["c", "b", "a"])
        #expect(pins.ids(inProfile: "Profile 2") == ["a", "b", "c"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func removedExtensionsLeaveEveryList() {
        var pins = PinnedExtensions(shared: ["a", "b"], profiles: ["Profile 1": ["b", "c"]])
        pins.removeAll { $0 == "b" }
        #expect(pins == PinnedExtensions(shared: ["a"], profiles: ["Profile 1": ["c"]]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func profileListsRoundTrip() throws {
        let pins = PinnedExtensions(shared: ["a"], profiles: ["Default": [], "Profile 1": ["c", "a"]])
        let data = try JSONEncoder().encode(pins)
        #expect(try JSONDecoder().decode(PinnedExtensions.self, from: data) == pins)
        // An unpinned-everything profile keeps its empty list rather than falling back.
        #expect(pins.ids(inProfile: "Default").isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func unreadableFileMeansNoPins() throws {
        #expect((try? JSONDecoder().decode(PinnedExtensions.self, from: Data(#"{"shared": 3}"#.utf8))) == nil)
        #expect(try JSONDecoder().decode(PinnedExtensions.self, from: Data("{}".utf8)) == PinnedExtensions())
    }
}

/// The extensions menu lists each extension once. Two installs of one extension (two folders
/// with the same manifest key) or a pin saved twice listed it twice, and the menu's icon map
/// trapped on the repeated ID (crash reports from 0.1.42 and 0.1.43, SiteControlCenterView.liveIcons).
struct ExtensionsMenuOrderTests {
    struct E: Equatable { let id: String, name: String }

    func order(_ entries: [E], pins: PinnedExtensions) -> [String] {
        pins.menuOrder(entries, inProfile: "Default", id: \.id, name: \.name).map(\.id)
    }

    @Test func pinnedFirstThenByName() {
        let entries = [E(id: "c", name: "Charlie"), E(id: "a", name: "alpha"), E(id: "b", name: "Bravo")]
        #expect(order(entries, pins: PinnedExtensions(shared: ["c"])) == ["c", "a", "b"])
    }

    @Test(.bug(id: "crash-duplicate-extension-ids")) func twoInstallsOfOneExtensionShowOnce() {
        let entries = [E(id: "a", name: "Alpha"), E(id: "b", name: "Bravo"), E(id: "a", name: "Alpha copy")]
        #expect(order(entries, pins: PinnedExtensions()) == ["a", "b"])
        #expect(order(entries, pins: PinnedExtensions(shared: ["a"])) == ["a", "b"])
    }

    @Test(.bug(id: "crash-duplicate-extension-ids")) func aPinSavedTwiceShowsOnce() {
        let entries = [E(id: "a", name: "Alpha"), E(id: "b", name: "Bravo")]
        #expect(order(entries, pins: PinnedExtensions(shared: ["b", "a", "b"])) == ["b", "a"])
    }

    @Test func aPinOfAnotherProfileIsNotShown() {
        let entries = [E(id: "a", name: "Alpha")]
        #expect(order(entries, pins: PinnedExtensions(shared: ["z"])) == ["a"])
    }
}
