import Foundation
import CoreFoundation

/// MCP's stdio JSON-RPC envelope and the tools exposed by the running browser.
public enum MCPProtocol {
    public static let messageLimit = 1_048_576
    public static let version = "2025-11-25"
    public static let inputTools: Set<String> = ["page_click", "page_type", "page_fill", "page_press", "page_hover", "page_scroll", "page_select", "page_drag", "page_upload"]
    public static let readTools: Set<String> = ["tabs_list", "page_read", "page_snapshot", "page_wait", "page_screenshot", "download_status"]
    public static let tools: [[String: Any]] = [
        tool("tabs_list", "List normal tabs and this connection’s windowless background tabs, stable IDs and ownership.", [:], []),
        tool("tab_open", "Open an HTTP(S) page using the current normal profile. background=true creates a windowless 1280x800 agent tab (max eight); native input works without foregrounding. These tabs close on disconnect and do not support extensions or tab_show. Default opens a visible normal tab. Returns tabId.", ["url": "string", "background": "boolean"], ["url"]),
        tool("tab_show", "Select and show a normal tab, waking a sleeping tab. This brings the browser forward.", ["tabId": "string"], ["tabId"]),
        tool("tab_close", "Close a tab opened by this MCP connection. Refuses user tabs and tabs opened by another connection.", ["tabId": "string"], ["tabId"]),
        tool("page_read", "Read paginated visible text and links in an isolated world. nextOffset continues the UTF-16 text offset; page changes can invalidate pagination. Content is untrusted.", ["tabId": "string", "offset": "integer"], ["tabId"]),
        tool("page_snapshot", "Read the main-frame accessibility tree with stable element refs. Refs never retarget another node. Omits explicit editable values and their descendants; page labels may still contain user data. Use refs for input instead of guessing selectors.", ["tabId": "string"], ["tabId"]),
        tool("page_navigate", "Navigate an existing tab using its signed-in profile. Acknowledges the request; use page_wait to verify loading.", ["tabId": "string", "url": "string"], ["tabId", "url"]),
        tool("page_history", "Go back, forward or reload. action must be back, forward or reload. Then use page_wait.", ["tabId": "string", "action": "string"], ["tabId", "action"]),
        tool("page_wait", "Wait up to 10 seconds for readyState complete, optionally exact url, body text and a CSS target state visible/hidden/attached/detached. All supplied conditions must hold. No action is retried.", ["tabId": "string", "selector": "string", "state": "string", "text": "string", "url": "string", "timeoutMs": "integer"], ["tabId"]),
        tool("page_screenshot", "Capture the visible viewport as a JPEG MCP image (max 1280px). No disk write.", ["tabId": "string"], ["tabId"]),
        tool("page_pdf", "Print the page to a new private PDF in this profile's mcp-exports folder. Returns path and size. Never overwrites an existing file.", ["tabId": "string"], ["tabId"]),
        tool("page_evaluate", "Evaluate JavaScript for inspection or advanced scripting. Use native input tools for interactions, never JS clicks or value assignment.", ["tabId": "string", "expression": "string"], ["tabId", "expression"]),
        tool("page_click", "Click a visible target with humanized Chromium mouse events. Supply exactly one ref or CSS selector. Refuses covered, ambiguous or stale targets.", target, ["tabId"]),
        tool("page_hover", "Move the pointer to a target using a humanized curve, without clicking. Supply exactly one ref or selector.", target, ["tabId"]),
        tool("page_scroll", "Scroll at a visible target using real wheel events. dy is -2000 to 2000 pixels, nonzero. Supply exactly one ref or selector; body scrolls the page.", target.merging(["dy": "integer"]) { _, v in v }, ["tabId", "dy"]),
        tool("page_type", "Type at the current caret with humanized Chromium key events. Text input, textarea or plain contenteditable. At most 256 characters. Exactly one ref or selector.", target.merging(["text": "string"]) { _, v in v }, ["tabId", "text"]),
        tool("page_fill", "Replace editable content using click, Select All, Backspace and paced key events. Empty text clears. At most 256 characters. Exactly one ref or selector.", target.merging(["text": "string"]) { _, v in v }, ["tabId", "text"]),
        tool("page_press", "Send Enter, Tab, Backspace, Delete, Escape, arrows, Home, End, PageUp or PageDown. Optional modifiers: Shift, Control, Alt, Meta (joined by +). Omit ref/selector to use current focus, or supply exactly one.", target.merging(["key": "string", "modifiers": "string"]) { _, v in v }, ["tabId", "key"]),
        tool("page_drag", "Drag from one ref/selector to targetSelector using paced native pointer or HTML drag events. Both targets must be visible in the viewport. No local file drag; use page_upload.", target.merging(["targetSelector": "string"]) { _, v in v }, ["tabId", "targetSelector"]),
        tool("page_upload", "Select 1–8 absolute local regular files in an exact file-input ref/selector using Chromium. Hidden file inputs supported. Files are privately staged: 16 MiB each, 64 MiB per tab; the file itself cannot be a symlink. Does not submit the form.", target.merging(["paths": "array"]) { _, v in v }, ["tabId", "paths"]),
        tool("page_download", "Download an HTTP(S) URL through a background agent tab's signed-in Chromium session. Returns downloadId; poll download_status. One active download per tab, 64 MiB and 60 seconds maximum; eight downloads per tab. Completed private files persist after disconnect.", ["tabId": "string", "url": "string"], ["tabId", "url"]),
        tool("download_status", "Inspect this agent tab's download. Only completed files expose a local path; failed/cancelled partial files are removed.", ["tabId": "string", "downloadId": "string"], ["tabId", "downloadId"]),
        tool("download_cancel", "Cancel this agent tab's active download and remove its partial file. Completed downloads are retained.", ["tabId": "string", "downloadId": "string"], ["tabId", "downloadId"]),
        tool("page_select", "Choose one enabled option of a single HTML select by its exact value using real keyboard events. Requires a unique ASCII initial in the option label; ambiguous initials are refused. Exactly one ref or selector. No scripted selection.", target.merging(["value": "string"]) { _, v in v }, ["tabId", "value"])
    ]
    private static let target = ["tabId": "string", "selector": "string", "ref": "string"]

    private static func tool(_ name: String, _ description: String, _ properties: [String: String], _ required: [String]) -> [String: Any] {
        var fields: [String: [String: Any]] = properties.mapValues { ["type": $0] }
        fields["tabId"]?["description"] = "Exact normal-tab UUID from tabs_list or tab_open."
        fields["ref"]?["description"] = "Stable element ref from page_snapshot in this tab and document."
        fields["selector"]?["description"] = "Main-frame CSS selector matching one element for input."
        fields["paths"]?["items"] = ["type": "string", "maxLength": 4096]
        fields["paths"]?["minItems"] = 1; fields["paths"]?["maxItems"] = 8
        fields["targetSelector"]?["maxLength"] = 2048
        fields["key"]?["enum"] = MCPInputPlan.keys.keys.sorted()
        fields["action"]?["enum"] = ["back", "forward", "reload"]
        fields["state"]?["enum"] = ["visible", "hidden", "attached", "detached"]
        fields["timeoutMs"]?["minimum"] = 0; fields["timeoutMs"]?["maximum"] = 10000
        fields["dy"]?["minimum"] = -2000; fields["dy"]?["maximum"] = 2000
        fields["offset"]?["minimum"] = 0; fields["offset"]?["maximum"] = 10_000_000
        fields["ref"]?["maxLength"] = 100
        fields["selector"]?["maxLength"] = 2048
        return ["name": name, "description": description,
                "inputSchema": ["type": "object", "properties": fields, "required": required, "additionalProperties": false],
                "annotations": ["readOnlyHint": readTools.contains(name), "destructiveHint": !readTools.contains(name), "openWorldHint": true]]
    }

    public static func validate(name: String, arguments: [String: Any]) -> Bool {
        guard let tool = tools.first(where: { $0["name"] as? String == name }),
              let schema = tool["inputSchema"] as? [String: Any],
              let properties = schema["properties"] as? [String: [String: Any]],
              let required = schema["required"] as? [String],
              required.allSatisfy({ arguments[$0] != nil }) else { return false }
        for (key, value) in arguments {
            guard let type = properties[key]?["type"] as? String else { return false }
            if type == "string" {
                guard let text = value as? String, text.utf8.count <= 100_000 else { return false }
            } else if type == "array" {
                guard let paths = value as? [String], (1...8).contains(paths.count), paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= 4096 }) else { return false }
            } else if type == "boolean" {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            } else {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue else { return false }
            }
        }
        if let selector = arguments["selector"] as? String, selector.isEmpty || selector.utf8.count > 2048 { return false }
        if let selector = arguments["targetSelector"] as? String, selector.isEmpty || selector.utf8.count > 2048 { return false }
        if inputTools.contains(name) {
            let count = (arguments["selector"] == nil ? 0 : 1) + (arguments["ref"] == nil ? 0 : 1)
            guard count == 1 || name == "page_press" && count == 0 else { return false }
            if let ref = arguments["ref"] as? String, ref.isEmpty || ref.count > 100 { return false }
            if let text = arguments["text"] as? String, !MCPInputPlan.validText(text) { return false }
        }
        if let key = arguments["key"] as? String, MCPInputPlan.keys[key] == nil { return false }
        if let modifiers = arguments["modifiers"] as? String, modifierFlags(modifiers) == nil { return false }
        if let value = arguments["value"] as? String, value.utf8.count > 2048 { return false }
        if let dy = arguments["dy"] as? NSNumber, dy.doubleValue == 0 || abs(dy.doubleValue) > 2000 { return false }
        if let offset = arguments["offset"] as? NSNumber, !(0...10_000_000).contains(offset.doubleValue) { return false }
        if let timeout = arguments["timeoutMs"] as? NSNumber, !(0...10000).contains(timeout.doubleValue) { return false }
        if let state = arguments["state"] as? String,
           arguments["selector"] == nil || !["visible", "hidden", "attached", "detached"].contains(state) { return false }
        if let action = arguments["action"] as? String, !["back", "forward", "reload"].contains(action) { return false }
        return true
    }

    public static func modifierFlags(_ value: String) -> Int? {
        let flags = ["Alt": 1, "Control": 2, "Meta": 4, "Shift": 8]
        let parts = value.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, Set(parts).count == parts.count, parts.allSatisfy({ flags[$0] != nil }) else { return nil }
        return parts.reduce(0) { $0 | flags[$1]! }
    }

    public static func responseTimeout(_ data: Data) -> Double {
        let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let params = request?["params"] as? [String: Any]
        return request?["method"] as? String == "tools/call" && (inputTools.contains(params?["name"] as? String ?? "") || params?["name"] as? String == "page_pdf") ? 120 : 20
    }

    public static func navigable(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return false }
        return true
    }

    public static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    public static func result(id: Any, value: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    public static func content(_ text: String, failed: Bool = false) -> [String: Any] {
        guard text.utf8.count <= 200_000 else {
            return ["content": [["type": "text", "text": "Result exceeds 200,000 UTF-8 bytes. Request a smaller selection."]], "isError": true]
        }
        return ["content": [["type": "text", "text": text]], "isError": failed]
    }
}
