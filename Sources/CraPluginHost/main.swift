import Foundation
import JavaScriptCore

var errorState: [String: String] = [:]

func send(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
}

do {
    guard let line = readLine(), let data = line.data(using: .utf8),
          let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let script = request["script"] as? String,
          let method = request["method"] as? String,
          let context = JSContext() else {
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
