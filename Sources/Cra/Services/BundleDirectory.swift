import Foundation

/// A folder in a sync or export bundle, held open by descriptor and reached without following a link below the bundle
/// folder: a peer on a shared folder can swap a folder for a link at any moment. Every bundle write and prune, and every
/// read of an easel file or picture, uses it.
final class BundleDirectory {
    private let fd: Int32

    /// The bundle folder, through a link as any folder the user set up, then each of `path`'s folders in turn, made when
    /// missing and `create`. Throws when one of those is a link (ELOOP) or not a folder (ENOTDIR).
    init(_ folder: URL, path: [String] = [], create: Bool = false) throws {
        var fd = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure() }
        for name in path {
            var next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, create, mkdirat(fd, name, 0o755) == 0 || errno == EEXIST {
                next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            let failed = Self.failure()
            close(fd)
            guard next >= 0 else { throw failed }
            fd = next
        }
        self.fd = fd
    }

    private init(fd: Int32) { self.fd = fd }

    deinit { close(fd) }

    /// Writes `data` at a path under `folder` ("Easels/<id>/<name>"), making the folders on its way.
    static func write(_ data: Data, to path: String, in folder: URL) throws {
        var parts = path.split(separator: "/").map(String.init)
        guard let name = parts.popLast() else { throw POSIXError(.EINVAL) }
        try BundleDirectory(folder, path: parts, create: true).write(data, as: name)
    }

    /// Writes a temp file beside `name`, syncs it to disk and renames it over `name`: a link there is replaced, not followed.
    func write(_ data: Data, as name: String) throws {
        let temp = ".\(name).\(UUID().uuidString)\(Self.tempSuffix)"
        let file = openat(fd, temp, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard file >= 0 else { throw Self.failure() }
        let written = data.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(file, bytes.baseAddress! + offset, bytes.count - offset)
                if n < 0, errno != EINTR { return false }
                offset += max(n, 0)
            }
            return true
        } && fsync(file) == 0
        let writeFailure = Self.failure()
        close(file)
        guard written else {
            unlinkat(fd, temp, 0)
            throw writeFailure
        }
        guard renameat(fd, temp, fd, name) == 0 else {
            let renameFailure = Self.failure()
            unlinkat(fd, temp, 0)
            throw renameFailure
        }
    }

    /// The bytes of the regular file at a path under `folder` ("Easels/<id>.json"); nil when a folder on its way is a
    /// link, or the file is a link, a FIFO or a device, which it never waits on.
    static func read(_ path: String, in folder: URL) -> Data? {
        var parts = path.split(separator: "/").map(String.init)
        guard let name = parts.popLast() else { return nil }
        return (try? BundleDirectory(folder, path: parts))?.read(name)
    }

    /// Opens `name` without waiting on a FIFO, checks that what it opened is a regular file, then reads it.
    func read(_ name: String) -> Data? {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var found = stat()
        // O_NONBLOCK only kept the open from waiting on a FIFO: a regular file is read as any other.
        guard fstat(file, &found) == 0, found.st_mode & S_IFMT == S_IFREG,
              fcntl(file, F_SETFL, fcntl(file, F_GETFL) & ~O_NONBLOCK) == 0 else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n >= 0 else { return nil }
            if n == 0 { return data }
            data.append(contentsOf: buffer[..<n])
        }
    }

    private static let tempSuffix = ".tmp"

    /// The name a temp file `write` left behind was for, when a crash stopped it before its rename; nil for any other name.
    static func leftOver(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(tempSuffix) else { return nil }
        let core = name.dropFirst().dropLast(tempSuffix.count)
        guard let dot = core.lastIndex(of: "."), UUID(uuidString: String(core[core.index(after: dot)...])) != nil else { return nil }
        return String(core[..<dot])
    }

    /// The folder `name` in this one; nil when it is a link, not a folder, or not there.
    func folder(_ name: String) -> BundleDirectory? {
        let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        return next >= 0 ? BundleDirectory(fd: next) : nil
    }

    /// The names of what this folder holds.
    func names() -> [String] {
        let listed = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard listed >= 0 else { return [] }
        guard let dir = fdopendir(listed) else {
            close(listed)
            return []
        }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self) }
            if name != ".", name != ".." { names.append(name) }
        }
        return names
    }

    /// Whether `name` is a regular file (true) or a link (false); nil for anything else or nothing.
    func isFile(_ name: String) -> Bool? {
        var found = stat()
        guard fstatat(fd, name, &found, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        switch found.st_mode & S_IFMT {
        case S_IFREG: return true
        case S_IFLNK: return false
        default: return nil
        }
    }

    /// Removes the file or link `name`, or with `folder` the empty folder `name`; false when it couldn't.
    @discardableResult
    func remove(_ name: String, folder: Bool = false) -> Bool {
        unlinkat(fd, name, folder ? AT_REMOVEDIR : 0) == 0
    }

    private static func failure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
