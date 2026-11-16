import Foundation

@main
@MainActor enum LinkSummaryImageTests {
    private static var checks = 0
    static func main() async throws {
        let port = Int(CommandLine.arguments[1])!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
                                                     "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port]
        let clock = ManualScheduler()
        let fetch = LinkSummaryImageFetch(configuration: configuration, clock: clock)
        func load(_ path: String) async -> Data? {
            await fetch.load(URL(string: "http://images.example\(path)")!, httpsOnly: false)
        }
        let image = await load("/image")
        expect(image?.starts(with: [137, 80, 78, 71]) == true, "a valid image travels through the real local proxy and delegate")
        let redirected = await load("/redirect-public")
        expect(redirected == image, "a validated cross-host redirect returns the actual image bytes")
        expect(await load("/redirect-relative") == image, "a relative redirect resolves against its actual image response URL")
        for path in ["/redirect-private", "/redirect-credentials", "/redirect-file", "/redirect-loop", "/chain"] {
            expect(await load(path) == nil, "unsafe, looping or excessive image redirect is rejected: \(path)")
        }
        var stats = try await records(port)
        expect(stats["/forbidden"] == nil, "rejected redirect destinations receive no wire request")
        expect(stats["/redirect-loop"]?["hits"] as? Int == 1, "the repeated redirect URL is not requested again")
        expect(stats["/chain"]?["hits"] as? Int == LinkSummaryFetchPolicy.maximumRedirects + 1,
               "redirect count is bounded before another wire request")
        for raw in ["http://127.0.0.1:\(port)/forbidden", "http://user:pass@images.example/forbidden", "file:///etc/hosts"] {
            expect(await fetch.load(URL(string: raw)!, httpsOnly: false) == nil,
                   "invalid initial image target never starts transport: \(raw)")
        }
        stats = try await records(port)
        expect(stats["/forbidden"] == nil, "invalid initial URLs also leave the forbidden destination untouched")
        expect(await fetch.load(URL(string: "http://images.example/secure-only")!, httpsOnly: true) == nil,
               "a failed secure connection is not downgraded to HTTP")
        stats = try await records(port)
        expect(stats["/secure-only"] == nil && stats["CONNECT"]?["target"] as? String == "images.example:443",
               "HTTPS-only upgrades before the first wire request")
        for path in ["/status", "/mime"] {
            expect(await load(path) == nil, "non-success status or non-image MIME is rejected: \(path)")
        }
        expect(await load("/boundary")?.count == LinkSummaryImageFetch.maximumBytes,
               "an image exactly at the byte boundary is accepted")
        expect(await load("/oversized-header") == nil, "oversized declared length is rejected before receiving the body")
        expect(try await wait(port, path: "/oversized-header", event: "disconnected"),
               "declared-length rejection physically closes its socket")
        expect(await load("/stream") == nil, "chunked image exceeding the cap is rejected during receipt")
        expect(try await wait(port, path: "/stream", event: "disconnected"),
               "stream cap physically disconnects the active download")
        stats = try await records(port)
        let sent = stats["/stream"]?["bytes"] as? Int ?? 0
        expect(sent > 0 && sent < 192 * 65536 && stats["/stream"]?["completed"] == nil,
               "stream cancellation stops wire transfer before the complete oversized image")
        expect(await load("/cookie") == image, "Set-Cookie does not prevent an otherwise usable image")
        stats = try await records(port)
        expect(stats["/image"]?["cookie"] as? String == "", "the redirected image sends no response cookie")
        let before = stats["/image"]?["hits"] as? Int ?? 0
        _ = await load("/image")
        stats = try await records(port)
        expect(stats["/image"]?["hits"] as? Int == before + 1, "the transport keeps no response cache between operations")

        let cancelled = Task { await load("/cancel-hold") }
        expect(try await wait(port, path: "/cancel-hold", event: "body"), "cancellation fixture reached real body delivery")
        cancelled.cancel()
        expect(await cancelled.value == nil, "owned cancellation returns without waiting for an unfinished body")
        expect(try await wait(port, path: "/cancel-hold", event: "disconnected"), "owned cancellation physically closes the body socket")
        stats = try await records(port)
        expect(stats["/cancel-hold"]?["completed"] == nil, "cancellation ends transfer before the finite body completes")
        let timed = Task { await load("/redirect-hold") }
        expect(try await wait(port, path: "/deadline-hold", event: "body"), "deadline spans a redirect and the subsequent body")
        clock.advance(by: LinkSummaryImageFetch.timeout)
        expect(await timed.value == nil, "one aggregate deadline ends a stalled redirected image")
        expect(try await wait(port, path: "/deadline-hold", event: "disconnected"), "aggregate deadline physically closes transport")
        stats = try await records(port)
        expect(stats["/deadline-hold"]?["completed"] == nil, "aggregate deadline ends transfer before the finite body completes")
        expect(clock.pendingCount == 0, "terminal operations release all owned deadline handles")
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await load("/never-started")
        }
        expect(await early.value == nil, "already-cancelled image work returns immediately")
        stats = try await records(port)
        expect(stats["/never-started"] == nil, "already-cancelled image work makes no wire request")
        print("Link summary image transport: \(checks) checks passed")
    }

    private static func records(_ port: Int) async throws -> [String: [String: Any]] {
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: URL(string: "http://127.0.0.1:\(port)/stats")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12))
        return try JSONSerialization.jsonObject(with: data) as! [String: [String: Any]]
    }

    private static func wait(_ port: Int, path: String, event: String) async throws -> Bool {
        var url = URLComponents(string: "http://127.0.0.1:\(port)/wait")!
        url.queryItems = [.init(name: "path", value: path), .init(name: "event", value: event)]
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["ready"] as? Bool == true
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
}
