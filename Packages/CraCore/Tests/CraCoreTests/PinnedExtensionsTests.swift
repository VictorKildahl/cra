import CraCore
import Foundation
import Testing

/// Pinned extensions belong to a profile, like Arc's (GitHub #107).
struct PinnedExtensionsTests {
    /// The list Cra kept before #107 serves every profile until one changes its own.
    @Test func oldListServesEveryProfile() throws {
        let pins = try JSONDecoder().decode(PinnedExtensions.self, from: Data(#"["a","b"]"#.utf8))
        #expect(pins.ids(inProfile: "Default") == ["a", "b"])
        #expect(pins.ids(inProfile: "Profile 1") == ["a", "b"])
        // Written back unchanged.
        #expect(String(decoding: try JSONEncoder().encode(pins), as: UTF8.self) == #"["a","b"]"#)
    }

    @Test func pinningInOneProfileLeavesTheOthers() {
        var pins = PinnedExtensions(shared: ["a", "b"])
        pins.setPinned("c", true, inProfile: "Profile 1")
        pins.setPinned("a", false, inProfile: "Profile 1")
        #expect(pins.ids(inProfile: "Profile 1") == ["b", "c"])
        #expect(pins.ids(inProfile: "Default") == ["a", "b"])
        #expect(pins.isPinned("c", inProfile: "Profile 1"))
        #expect(!pins.isPinned("c", inProfile: "Default"))
    }

    @Test func noChangeKeepsTheSharedList() {
        var pins = PinnedExtensions(shared: ["a"])
        pins.setPinned("a", true, inProfile: "Default")
        pins.setPinned("z", false, inProfile: "Default")
        pins.move("z", to: 0, inProfile: "Default")
        #expect(pins.profiles.isEmpty)
    }

    @Test func moveReordersOneProfile() {
        var pins = PinnedExtensions(shared: ["a", "b", "c"])
        pins.move("c", to: 0, inProfile: "Default")
        pins.move("a", to: 99, inProfile: "Default")
        #expect(pins.ids(inProfile: "Default") == ["c", "b", "a"])
        #expect(pins.ids(inProfile: "Profile 2") == ["a", "b", "c"])
    }

    @Test func removedExtensionsLeaveEveryList() {
        var pins = PinnedExtensions(shared: ["a", "b"], profiles: ["Profile 1": ["b", "c"]])
        pins.removeAll { $0 == "b" }
        #expect(pins == PinnedExtensions(shared: ["a"], profiles: ["Profile 1": ["c"]]))
    }

    @Test func profileListsRoundTrip() throws {
        let pins = PinnedExtensions(shared: ["a"], profiles: ["Default": [], "Profile 1": ["c", "a"]])
        let data = try JSONEncoder().encode(pins)
        #expect(try JSONDecoder().decode(PinnedExtensions.self, from: data) == pins)
        // An unpinned-everything profile keeps its empty list rather than falling back.
        #expect(pins.ids(inProfile: "Default").isEmpty)
    }

    @Test func unreadableFileMeansNoPins() throws {
        #expect((try? JSONDecoder().decode(PinnedExtensions.self, from: Data(#"{"shared": 3}"#.utf8))) == nil)
        #expect(try JSONDecoder().decode(PinnedExtensions.self, from: Data("{}".utf8)) == PinnedExtensions())
    }
}
