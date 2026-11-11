import Foundation
import JavaScriptCore

// Runs one call into a live folder plugin: the script and its input arrive as one line on stdin, the
// result (or a session request, answered on stdin) goes out on stdout. Plugins can come from a ZIP
// someone downloaded, so this process gives up files, network and every other service before it
// reads the script: all a plugin can reach is the pipe to Cra, which checks each request.

/// <sandbox.h>, which Swift doesn't import. Chromium's helpers use the same call.
@_silgen_name("sandbox_init")
private func sandbox_init(_ profile: UnsafePointer<CChar>, _ flags: UInt64,
                          _ errorbuf: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

var errorState: [String: String] = [:]

func send(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
}

/// JavaScriptCore loads ICU's data and its regular expression engine on first use: use them once
/// while files can still be read, then deny access to new OS resources before reading plugin code.
func enterSandbox(_ context: JSContext) throws {
    context.evaluateScript(#"""
        /\p{L}+/u.test("é"); "Ä".normalize("NFD").toLowerCase(); "a".localeCompare("b");
        Date.parse("2026-11-06T12:00:00.123+0300"); new Date(0).toISOString(); JSON.stringify({a: [1]});
        encodeURIComponent("é ?"); parseInt("ff", 16); String.fromCodePoint(0x1F600);
        """#)
    var error: UnsafeMutablePointer<CChar>?
    // macOS kills processes built with SDK 27 or newer that enter a built-in named profile.
    guard sandbox_init("(version 1)(deny default)", 0, &error) == 0 else {
        let message = error.map { String(cString: $0) } ?? "unknown"
        throw NSError(domain: "CraPluginHost", code: 5, userInfo: [NSLocalizedDescriptionKey: "Sandbox failed: \(message)"])
    }
}

do {
    guard let context = JSContext() else {
        throw NSError(domain: "CraPluginHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid plugin invocation"])
    }
    try enterSandbox(context)
    guard let line = readLine(), let data = line.data(using: .utf8),
          let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let script = request["script"] as? String,
          let method = request["method"] as? String else {
        throw NSError(domain: "CraPluginHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid plugin invocation"])
    }
    var exception: String?
    context.exceptionHandler = { _, value in
        exception = value?.toString() ?? "JavaScript exception"
        errorState = value?.forProperty("state")?.toDictionary() as? [String: String] ?? [:]
    }
    let fetch: @convention(block) (String) -> String = { request in
        do {
            try send(["type": "fetch", "request": request])
            guard let response = readLine() else { return "{\"error\":\"Session transport closed\"}" }
            return response
        } catch {
            return "{\"error\":\"Session transport failed\"}"
        }
    }
    context.setObject(fetch, forKeyedSubscript: "__sessionFetch" as NSString)
    context.evaluateScript("""
        const cra = Object.freeze({session: Object.freeze({fetch(url, options = {}) {
            const response = JSON.parse(__sessionFetch(JSON.stringify({url, ...options})));
            if (response.error) throw new Error(response.error);
            return response;
        }})});
        const plugin = (function () {
        \(script)
        })();
        """)
    if let exception { throw NSError(domain: "CraPluginHost", code: 2, userInfo: [NSLocalizedDescriptionKey: exception]) }
    context.setObject(method, forKeyedSubscript: "__method" as NSString)
    context.setObject(request["input"] ?? [:], forKeyedSubscript: "__input" as NSString)
    let result = context.evaluateScript("""
        (() => {
            if (!Object.prototype.hasOwnProperty.call(plugin, __method) || typeof plugin[__method] !== 'function')
                throw new Error('Unknown plugin method');
            const result = plugin[__method](__input);
            if (result && typeof result.then === 'function') throw new Error('Plugin methods must return synchronously');
            const json = JSON.stringify(result);
            if (json === undefined) throw new Error('Plugin returned no result');
            return json;
        })()
        """)
    if let exception { throw NSError(domain: "CraPluginHost", code: 3, userInfo: [NSLocalizedDescriptionKey: exception]) }
    guard let json = result?.toString() else {
        throw NSError(domain: "CraPluginHost", code: 4, userInfo: [NSLocalizedDescriptionKey: "Plugin returned no result"])
    }
    try send(["type": "result", "json": json])
} catch {
    try? send(["type": "error", "message": error.localizedDescription, "state": errorState])
    exit(1)
}
