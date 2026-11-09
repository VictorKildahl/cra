import Foundation

public struct LiveFolderPluginPackage {
    public let manifest: LiveFolderPluginManifest
    public let directory: URL
    public let script: String

    public init(directory: URL) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        self.directory = root
        let manifestURL = try Self.resource("manifest.json", under: root)
        let data = try Self.read(manifestURL, limit: 256 * 1024)
        manifest = try JSONDecoder().decode(LiveFolderPluginManifest.self, from: data)
        try manifest.validate()
        let entry = try Self.resource(manifest.entry, under: root)
        guard let script = String(data: try Self.read(entry, limit: 2 * 1024 * 1024), encoding: .utf8) else {
            throw LiveFolderPluginError.invalidManifest("Plugin script must be UTF-8")
        }
        self.script = script
    }

    public func resource(_ path: String) throws -> URL {
        try Self.resource(path, under: directory)
    }

    private static func resource(_ path: String, under root: URL) throws -> URL {
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw LiveFolderPluginError.invalidManifest("Plugin resource must be a file inside its package")
        }
        return url
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw LiveFolderPluginError.invalidManifest("Plugin resource is too large") }
        return data
    }
}

public struct LiveFolderPluginCatalog {
    public struct Failure {
        public let directory: URL
        public let message: String
    }

    public private(set) var packages: [LiveFolderPluginPackage] = []
    public private(set) var failures: [Failure] = []

    public init(directories: [URL]) {
        var ids = Set<String>()
        for directory in directories {
            do {
                let package = try LiveFolderPluginPackage(directory: directory)
                guard ids.insert(package.manifest.id).inserted else {
                    throw LiveFolderPluginError.invalidManifest("Duplicate plugin ID: \(package.manifest.id)")
                }
                packages.append(package)
            } catch {
                failures.append(Failure(directory: directory, message: error.localizedDescription))
            }
        }
    }
}
