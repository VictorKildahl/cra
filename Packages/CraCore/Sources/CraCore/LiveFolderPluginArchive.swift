import Foundation
import Darwin

public final class LiveFolderPluginArchive {
    public let package: LiveFolderPluginPackage
    private let temporaryDirectory: URL

    public init(url: URL) throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
            guard data.count <= 10 * 1024 * 1024 else { throw Self.failure("Plugin ZIP exceeds 10 MiB") }
            let entries = try Self.entries(data)
            let archive = temporary.appendingPathComponent("package.zip")
            try data.write(to: archive)
            let contents = temporary.appendingPathComponent("contents", isDirectory: true)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            for entry in entries where !entry.name.hasSuffix("/") {
                let output = try Self.extract(entry.name, size: entry.size, archive: archive)
                let target = contents.appendingPathComponent(entry.name)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try output.write(to: target, options: .withoutOverwriting)
            }
            let manifests = entries.filter { $0.name == "manifest.json" ||
                ($0.name.split(separator: "/").count == 2 && $0.name.hasSuffix("/manifest.json")) }
            guard manifests.count == 1 else { throw Self.failure("ZIP must contain one plugin with manifest.json at its root or inside one folder") }
            package = try LiveFolderPluginPackage(directory: contents.appendingPathComponent(manifests[0].name).deletingLastPathComponent())
            temporaryDirectory = temporary
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: temporaryDirectory) }

    private static func failure(_ message: String) -> LiveFolderPluginError { .invalidManifest(message) }

    private static func entries(_ data: Data) throws -> [(name: String, size: Int)] {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= bytes.count else { throw failure("Truncated plugin ZIP") }
            return (0..<count).reduce(0) { $0 | (Int(bytes[offset + $1]) << (8 * $1)) }
        }
        guard bytes.count >= 22 else { throw failure("Invalid plugin ZIP") }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try number(offset, 4) == 0x06054b50,
               try offset + 22 + number(offset + 20, 2) == bytes.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 8, 2) == number(end + 10, 2) else { throw failure("Unsupported plugin ZIP") }
        let count = try number(end + 10, 2)
        guard count > 0, count <= 100 else { throw failure("Plugin ZIP must contain between 1 and 100 entries") }
        var offset = try number(end + 16, 4)
        guard try offset + number(end + 12, 4) == end else { throw failure("Invalid ZIP directory") }
        var result: [(name: String, size: Int)] = []
        var names = Set<String>()
        var total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50,
                  try number(offset + 8, 2) & 1 == 0,
                  try [0, 8].contains(number(offset + 10, 2)), try number(offset + 34, 2) == 0 else {
                throw failure("Encrypted or unsupported ZIP entry")
            }
            let length = try number(offset + 28, 2)
            let next = try offset + 46 + length + number(offset + 30, 2) + number(offset + 32, 2)
            guard next <= end, let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + length)], encoding: .utf8) else {
                throw failure("Invalid ZIP entry name")
            }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            let path = name.hasSuffix("/") ? Array(parts.dropLast()) : parts
            guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix("-") }),
                  !name.contains(where: { "\\:*?[]".contains($0) || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }),
                  names.insert(name.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()).inserted else {
                throw failure("Unsafe or duplicate ZIP entry: \(name)")
            }
            let kind = try (number(offset + 38, 4) >> 16) & 0xf000
            guard kind == 0 || kind == (name.hasSuffix("/") ? 0x4000 : 0x8000) else {
                throw failure("ZIP links and special files are not allowed")
            }
            let size = try number(offset + 24, 4)
            total += size
            guard size <= 4 * 1024 * 1024, total <= 20 * 1024 * 1024 else { throw failure("Expanded plugin ZIP is too large") }
            result.append((name, size))
            offset = next
        }
        guard offset == end else { throw failure("Invalid ZIP directory size") }
        return result
    }

    private static func extract(_ name: String, size: Int, archive: URL) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, name]
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        var output = Data()
        while true {
            let chunk = try pipe.fileHandleForReading.read(upToCount: min(65536, size + 1 - output.count)) ?? Data()
            if chunk.isEmpty { break }
            output.append(chunk)
            guard output.count <= size else { throw failure("ZIP entry exceeds its declared size") }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, output.count == size else { throw failure("Could not unpack ZIP entry: \(name)") }
        return output
    }
}
