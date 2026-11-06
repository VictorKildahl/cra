import Foundation
import Darwin

@main
enum MCPTransportTests {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--mcp" {
            MCPConnection.bridge(path: CommandLine.arguments[2])
        }
        _ = try MCPConnection.address("/tmp/mcp-test.sock")
        do {
            _ = try MCPConnection.address(String(repeating: "x", count: 110))
            fatalError("Overlong socket path accepted")
        } catch {}
        let folder = URL(fileURLWithPath: "/tmp").appendingPathComponent("cra-listener-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("mcp.sock").path
        let owner = try MCPListener(path: path)
        let listener = try owner.bind()
        defer { close(listener) }
        do { _ = try MCPListener(path: path); fatalError("Second owner stole socket") } catch {}
        var before = stat(); precondition(lstat(path, &before) == 0)
        precondition(before.st_mode & 0o777 == 0o600)
        precondition(unlink(path) == 0)
        try Data("replacement".utf8).write(to: URL(fileURLWithPath: path))
        owner.stop()
        let replacement = try String(contentsOfFile: path, encoding: .utf8)
        precondition(replacement == "replacement")
        let next = try MCPListener(path: path)
        do { _ = try next.bind(); fatalError("Regular file removed") } catch {}
        next.stop()
        try FileManager.default.removeItem(atPath: path)
        let recovered = try MCPListener(path: path)
        let recoveredFD = try recovered.bind(); close(recoveredFD); recovered.stop()
        precondition(!FileManager.default.fileExists(atPath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: folder.path)
        do { _ = try MCPListener(path: path); fatalError("Unsafe directory accepted") } catch {}
        var fds: [Int32] = [-1, -1]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        let input = fds[0], output = fds[1]
        precondition(MCPConnection.peerIsOpen(input))
        precondition(!MCPConnection.peerIsOpen(-1))
        let reader = MCPConnection.Reader()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            precondition(MCPConnection.write(Data("first".utf8), to: output))
            precondition(MCPConnection.write(Data("\n🦊\n".utf8), to: output))
            precondition(MCPConnection.write(Data(repeating: 120, count: MCPConnection.limit) + Data([10]), to: output))
            precondition(MCPConnection.write(Data(repeating: 120, count: MCPConnection.limit + 1) + Data([10]), to: output))
            done.signal()
        }
        precondition(reader.next(input) == Data("first".utf8))
        precondition(reader.next(input) == Data("🦊".utf8))
        precondition(reader.next(input)?.count == MCPConnection.limit)
        precondition(reader.next(input) == nil)
        done.wait()
        shutdown(output, SHUT_WR)
        precondition(MCPConnection.Reader().next(input) == nil)
        precondition(!MCPConnection.peerIsOpen(input))
        precondition(!MCPConnection.write(Data([1]), to: -1))
        print("MCP transport: fragmentation, batching, Unicode, limits and EOF passed")
    }
}
