import CraCore
import Foundation
import Testing

/// Cra's data folder as Chromium sees it (#906).
struct DataFolderPathTests {
    /// The folder moved to another disk with a symbolic link left in its place: Chromium resolves its user data folder
    /// through the link and refuses a profile whose folder is named through it ("Cannot create profile at path"), so
    /// every page in a space on its own profile stayed black. Cra names its folders from the resolved path.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/906"))
    func aLinkedDataFolderIsNamedByWhereItIs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-906-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let real = root.appendingPathComponent("SSD/Cra", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("Cra", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = DataFolderPath.resolved(link)
        #expect(resolved.path == DataFolderPath.resolved(real).path)
        #expect(resolved.path.hasSuffix("/SSD/Cra"))
        #expect(resolved.appendingPathComponent("Chromium").path.hasSuffix("/SSD/Cra/Chromium"))
    }

    /// The way Chromium spells it (realpath): /tmp is /private/tmp, which Foundation's resolvingSymlinksInPath would
    /// turn back into /tmp. A folder that isn't there yet stays as given.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/906"))
    func resolvedAsChromiumResolvesIt() {
        #expect(DataFolderPath.resolved(URL(fileURLWithPath: "/tmp", isDirectory: true)).path == "/private/tmp")
        let missing = URL(fileURLWithPath: "/tmp/cra-906-not-there-\(UUID().uuidString)", isDirectory: true)
        #expect(DataFolderPath.resolved(missing) == missing)
    }
}
