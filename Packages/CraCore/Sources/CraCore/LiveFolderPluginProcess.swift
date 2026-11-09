import Foundation
import Darwin

public struct LiveFolderPluginRequest: Codable, Sendable {
    public let url: String
    public let headers: [String: String]?
}

public struct LiveFolderPluginResponse: Codable, Sendable {
    public var status: Int
    public var url: String
    public var body: String

    public init(status: Int, url: String, body: String) {
        self.status = status
        self.url = url
        self.body = body
    }
}

public enum LiveFolderPluginProcess {
    public static func invoke(executable: URL, script: String, method: String, input: Data,
                              origins: [LiveFolderSessionOrigin], timeout: TimeInterval = 30,
                              fetch: (LiveFolderPluginRequest) throws -> LiveFolderPluginResponse) throws -> Data {
        let process = Process()
        let incoming = Pipe(), outgoing = Pipe()
        process.executableURL = executable
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.nullDevice
        guard fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw failure("Unable to configure plugin transport")
        }
        let inputObject = try JSONSerialization.jsonObject(with: input, options: [.fragmentsAllowed])
        let invocation = try JSONSerialization.data(withJSONObject: ["script": script, "method": method, "input": inputObject])
        try process.run()
        let watchdog = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? incoming.fileHandleForWriting.close()
            try? outgoing.fileHandleForReading.close()
        }
        try incoming.fileHandleForWriting.write(contentsOf: invocation + Data([10]))
        var buffer = Data()
        var requests = 0
        while true {
            while !buffer.contains(10) {
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.read(outgoing.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure("Plugin stopped before returning a result (crash or timeout)") }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 8 * 1024 * 1024 else { throw failure("Plugin message exceeds the size limit") }
            }
            let end = buffer.firstIndex(of: 10)!
            let line = buffer.subdata(in: buffer.startIndex..<end)
            buffer.removeSubrange(buffer.startIndex...end)
            guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = message["type"] as? String else { throw failure("Invalid plugin message") }
            switch type {
            case "result":
                guard let json = message["json"] as? String else { throw failure("Missing plugin result") }
                let data = Data(json.utf8)
                _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                return data
            case "error":
                throw LiveFolderPluginError.pluginFailed(message["message"] as? String ?? "Plugin failed",
                                                        message["state"] as? [String: String] ?? [:])
            case "fetch":
                requests += 1
                guard requests <= 200, let json = message["request"] as? String else { throw failure("Invalid plugin request") }
                let request = try JSONDecoder().decode(LiveFolderPluginRequest.self, from: Data(json.utf8))
                guard let url = URL(string: request.url), origins.contains(where: { $0.permits(url) }) else {
                    throw failure("Plugin requested an origin without permission")
                }
                let blockedHeaders = Set(["cookie", "authorization", "proxy-authorization", "host", "origin", "referer"])
                guard (request.headers ?? [:]).allSatisfy({ key, value in
                    !blockedHeaders.contains(key.lowercased()) && !key.contains("\r") && !key.contains("\n")
                        && !value.contains("\r") && !value.contains("\n")
                }) else { throw failure("Plugin supplied a restricted request header") }
                let response = try fetch(request)
                guard response.body.utf8.count <= 4 * 1024 * 1024 else { throw failure("Session response exceeds the size limit") }
                guard let final = URL(string: response.url), origins.contains(where: { $0.permits(final) }) else {
                    throw failure("Session response is outside the permitted origins")
                }
                try incoming.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(response) + Data([10]))
            default:
                throw failure("Unknown plugin message")
            }
        }
    }

    private static func failure(_ message: String) -> LiveFolderPluginError {
        .executionFailed(message)
    }
}
