import CraCore
import Foundation
import Testing

struct LiveFolderPluginArchiveTests {
    private func fixture(nested: Bool = false, symlink: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent(nested ? "source/plugin" : "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"id":"test.zip","name":"ZIP Test","version":"1","apiVersion":1,"entry":"main.js","sessionOrigins":[]}"#.utf8)
            .write(to: source.appendingPathComponent("manifest.json"))
        try Data("return {};".utf8).write(to: source.appendingPathComponent("main.js"))
        if symlink {
            try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "main.js")
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root.appendingPathComponent("source")
        zip.arguments = ["-qry", root.appendingPathComponent("plugin.zip").path] + (nested ? ["plugin"] : ["manifest.json", "main.js"] + (symlink ? ["link"] : []))
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        return root
    }

    @Test(arguments: [false, true]) func extractsPackageAndRemovesTemporaryFiles(nested: Bool) throws {
        let root = try fixture(nested: nested)
        defer { try? FileManager.default.removeItem(at: root) }
        var archive: LiveFolderPluginArchive? = try LiveFolderPluginArchive(url: root.appendingPathComponent("plugin.zip"))
        let directory = try #require(archive?.package.directory)
        #expect(archive?.package.manifest.id == "test.zip")
        #expect(archive?.package.script == "return {};")
        archive = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func rejectsLinks() throws {
        let root = try fixture(symlink: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: LiveFolderPluginError.self) { try LiveFolderPluginArchive(url: root.appendingPathComponent("plugin.zip")) }
    }

    @Test func rejectsTraversalAndTruncatedArchives() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("plugin.zip")
        let original = try Data(contentsOf: url)
        var data = original
        let name = Data("main.js".utf8)
        while let range = data.range(of: name) { data.replaceSubrange(range, with: Data("../x.js".utf8)) }
        try data.write(to: url)
        #expect(throws: LiveFolderPluginError.self) { try LiveFolderPluginArchive(url: url) }
        try original.prefix(50).write(to: url)
        #expect(throws: LiveFolderPluginError.self) { try LiveFolderPluginArchive(url: url) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("x.js").path))
    }

    @Test func rejectsOversizedEntries() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("plugin.zip")
        var data = try Data(contentsOf: url)
        let central = try #require(data.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        data.replaceSubrange((central.lowerBound + 24)..<(central.lowerBound + 28), with: [0xff, 0xff, 0xff, 0x7f])
        try data.write(to: url)
        #expect(throws: LiveFolderPluginError.self) { try LiveFolderPluginArchive(url: url) }
    }
}
