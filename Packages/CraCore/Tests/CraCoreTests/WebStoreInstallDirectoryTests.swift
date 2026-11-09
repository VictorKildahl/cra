import CraCore
import Foundation
import Testing

struct WebStoreInstallDirectoryTests {
    let id = "aaaabbbbccccddddeeeeffffgggghhhh"
    let profile = URL(fileURLWithPath: "/fixture/Chromium/Default", isDirectory: true)

    func installed(_ path: String, location: Int = 1, fromWebStore: Bool = true, extensionID: String? = nil) -> URL? {
        WebStoreInstalls.storeInstallDirectory(settings: ["location": location, "from_webstore": fromWebStore, "path": path],
                                              extensionID: extensionID ?? id, profileDirectory: profile)
    }

    @Test func resolvesRelativeAndAbsoluteStorePaths() {
        let expected = profile.appendingPathComponent("Extensions/\(id)/1.0_0", isDirectory: true)
        #expect(installed("\(id)/1.0_0") == expected)
        #expect(installed(expected.path) == expected)
    }

    @Test func rejectsImportedDirectoriesDespiteWebStoreFlags() {
        #expect(installed("/fixture/Extensions/\(id)") == nil)
        #expect(installed("/fixture/Extensions/\(id)/1.0_0") == nil)
        #expect(installed("/fixture/Chromium/Profile 1/Extensions/\(id)/1.0_0") == nil)
    }

    @Test func rejectsMissingPathsAndDifferentExtensionDirectories() {
        #expect(WebStoreInstalls.storeInstallDirectory(settings: nil, extensionID: id, profileDirectory: profile) == nil)
        #expect(WebStoreInstalls.storeInstallDirectory(settings: ["location": 1, "from_webstore": true],
                                                     extensionID: id, profileDirectory: profile) == nil)
        #expect(installed("") == nil)
        #expect(installed(id) == nil)
        #expect(installed("bbbbccccddddeeeeffffgggghhhhiiii/1.0_0") == nil)
        #expect(installed("\(id)/1.0_0/icons") == nil)
        #expect(installed("../../Extensions/\(id)/1.0_0") == nil)
        #expect(installed("\(id)/1.0_0", extensionID: "not-an-extension-id") == nil)
    }

    @Test func requiresAStoreInstallation() {
        #expect(installed("\(id)/1.0_0", location: 8) == nil)
        #expect(installed("\(id)/1.0_0", location: 4) == nil)
        #expect(installed("\(id)/1.0_0", fromWebStore: false) == nil)
    }
}
