import Foundation
import Darwin

/// Local-only transport. File permissions on the Unix socket restrict access to this user.
enum MCPConnection {
    static let limit = MCPProtocol.messageLimit

    static func address(_ path: String) throws -> sockaddr_un {
        var value = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else {
            throw NSError(domain: "CraMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "MCP socket path is too long."])
        }
        value.sun_family = sa_family_t(AF_UNIX)
        value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &value.sun_path) { $0.copyBytes(from: bytes) }
        return value
    }

    static func socket() -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd >= 0 { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        return fd
    }

    /// Input gestures stop when their owner closes its write side. Non-input replies still drain at EOF.
    static func peerIsOpen(_ fd: Int32) -> Bool {
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count > 0 || count < 0 && [EAGAIN, EWOULDBLOCK, EINTR].contains(errno)
    }

    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
    }

    /// A bounded newline reader retains any following messages from the same read.
    final class Reader {
        private var pending = Data()
        func next(_ fd: Int32) -> Data? {
            while true {
                if let end = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<end])
                    pending.removeSubrange(...end)
                    return line.count <= limit ? line : nil
                }
                guard pending.count <= limit else { return nil }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(fd, &buffer, buffer.count)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { return nil }
                pending.append(contentsOf: buffer.prefix(n))
            }
        }
    }

    /// Runs before AppKit/CEF initialization. The client launches this mode as its MCP server.
    static func bridge(path: String) -> Never {
        do {
            var addr = try address(path)
            let fd = socket()
            guard fd >= 0 else { throw POSIXError(.ENFILE) }
            let connected = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                throw POSIXError(.EACCES)
            }
            DispatchQueue.global().async {
                let reader = Reader()
                while let line = reader.next(fd) {
                    guard write(line + Data([10]), to: STDOUT_FILENO) else { break }
                }
                exit(0)
            }
            let reader = Reader()
            while let line = reader.next(STDIN_FILENO) {
                guard write(line + Data([10]), to: fd) else { break }
            }
            shutdown(fd, SHUT_WR)
            // The receiving worker exits when the server has drained and closed.
            dispatchMain()
        } catch {
            FileHandle.standardError.write(Data("Cra MCP is unavailable. Enable it in the running browser's Advanced settings. \(error)\n".utf8))
            exit(1)
        }
    }
}
