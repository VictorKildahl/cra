import Foundation
import Darwin

/// Owns one profile endpoint. A second instance must never unlink the live server's socket.
final class MCPListener {
    private var lockFD: Int32 = -1
    private let path: String
    private var identity: (dev_t, ino_t)?
    init(path: String) throws {
        self.path = path
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var directory = stat()
        guard lstat(parent, &directory) == 0, directory.st_mode & S_IFMT == S_IFDIR,
              directory.st_uid == getuid(), directory.st_mode & 0o022 == 0 else { throw POSIXError(.EACCES) }
        lockFD = open(path + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw POSIXError(.EACCES) }
        var lock = stat()
        guard fstat(lockFD, &lock) == 0, lock.st_mode & S_IFMT == S_IFREG, lock.st_uid == getuid(),
              lock.st_nlink == 1, lock.st_mode & 0o077 == 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1; throw POSIXError(.EADDRINUSE)
        }
    }
    func bind() throws -> Int32 {
        var previous = stat()
        if lstat(path, &previous) == 0 {
            guard previous.st_uid == getuid(), previous.st_mode & S_IFMT == S_IFSOCK else { throw POSIXError(.EACCES) }
            guard unlink(path) == 0 else { throw POSIXError(.EACCES) }
        } else if errno != ENOENT { throw POSIXError(.EACCES) }
        var address = try MCPConnection.address(path)
        let fd = MCPConnection.socket()
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        var current = stat()
        guard lstat(path, &current) == 0 else { close(fd); throw POSIXError(.EACCES) }
        identity = (current.st_dev, current.st_ino)
        guard chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); throw POSIXError(.EACCES) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        return fd
    }
    func stop() {
        if let identity {
            var current = stat()
            if lstat(path, &current) == 0, current.st_dev == identity.0, current.st_ino == identity.1 { unlink(path) }
            self.identity = nil
        }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }
    deinit { stop() }
}
