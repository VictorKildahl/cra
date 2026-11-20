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
        try fullServerSaysWhy()
        bridgeWithoutStderr()
    }

    // promise: crash-mcp-bridge-closed-stderr
    /// An agent launched `Cra --mcp` with its stderr closed while Cra's MCP was off (0.1.50 crash
    /// reports): the "unavailable" line went through FileHandle.standardError, whose write raises
    /// on a closed descriptor, and the bridge aborted with a crash report instead of failing.
    static func bridgeWithoutStderr() {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&actions, STDERR_FILENO)
        let args = [CommandLine.arguments[0], "--mcp", "/tmp/cra-no-mcp-\(UUID().uuidString).sock"]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        precondition(posix_spawn(&pid, args[0], &actions, nil, &argv, environ) == 0)
        var status: Int32 = 0
        precondition(waitpid(pid, &status, 0) == pid)
        let signal = status & 0x7f, code = (status >> 8) & 0xff
        precondition(signal == 0 && code == 1, "a bridge without stderr exits 1, not on signal \(signal) (code \(code))")
        print("MCP bridge without stderr: Cra unavailable exits 1, no crash")
    }

    // promise: #459
    /// Every agent session keeps its connection for as long as it runs, mostly idle, so eight
    /// sessions filled Cra and the ninth was closed with no word: its agent showed only
    /// "Connection closed". Room for many idle sessions, and past the limit the agent and the
    /// bridge's stderr say why.
    static func fullServerSaysWhy() throws {
        precondition(MCPProtocol.clientLimit >= 32)
        let folder = URL(fileURLWithPath: "/tmp").appendingPathComponent("cra-full-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("mcp.sock").path
        let endpoint = try MCPListener(path: path)
        let listener = try endpoint.bind()
        defer { close(listener); endpoint.stop() }
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) & ~O_NONBLOCK)

        let bridge = Process()
        bridge.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        bridge.arguments = ["--mcp", path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        bridge.standardInput = input; bridge.standardOutput = output; bridge.standardError = errors
        try bridge.run()
        let client = accept(listener, nil, nil)
        precondition(client >= 0)
        // One below the limit is let in and left alone; at the limit the connection is answered and closed.
        precondition(MCPConnection.admit(client, open: MCPProtocol.clientLimit - 1))
        precondition(!MCPConnection.admit(client, open: MCPProtocol.clientLimit))
        let initialize = #"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#
        input.fileHandleForWriting.write(Data((initialize + "\n").utf8))
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try? input.fileHandleForWriting.close()
        bridge.waitUntilExit()

        let reply = (try? JSONSerialization.jsonObject(with: stdout.split(separator: 10).first.map { Data($0) } ?? Data())) as? [String: Any]
        let error = reply?["error"] as? [String: Any]
        precondition(reply?["id"] as? Int == 7, "the agent's initialize gets an answer: \(String(decoding: stdout, as: UTF8.self))")
        precondition(error?["code"] as? Int == MCPProtocol.fullCode)
        precondition((error?["message"] as? String)?.contains("\(MCPProtocol.clientLimit) agent connections") == true)
        precondition(stderr.contains("\(MCPProtocol.clientLimit) agent connections"), "the bridge says why on stderr: \(stderr)")
        precondition(bridge.terminationStatus != 0, "a turned-away bridge fails")
        print("MCP full server: room for \(MCPProtocol.clientLimit) agents; past that the agent and stderr say why")
    }
}
