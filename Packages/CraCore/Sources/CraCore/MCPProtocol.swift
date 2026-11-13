import Foundation
import CoreFoundation

/// MCP's stdio JSON-RPC envelope and the tools exposed by the running browser.
public enum MCPProtocol {
    public static let messageLimit = 1_048_576
    public static let version = "2025-11-25"
    public static let inputTools: Set<String> = ["page_click", "page_type", "page_fill", "page_press", "page_hover", "page_scroll", "page_select", "page_drag", "page_upload"]
    public static let readTools: Set<String> = ["tabs_list", "page_read", "page_snapshot", "page_wait", "page_screenshot", "download_status", "page_console", "page_network", "history_search"]
    /// Input tools whose result says what the action changed (MCPChanges), unless changes=false.
    public static let changeTools: Set<String> = ["page_click", "page_type", "page_fill", "page_press", "page_select", "page_drag", "page_upload"]
    /// Input tools that may act on a point of the last screenshot (x, y) instead of an element.
    /// page_upload takes the element there (a label's text, a drop zone) as its target.
    public static let pointTools: Set<String> = ["page_click", "page_hover", "page_scroll", "page_upload"]
    /// Input tools that may omit a target: they act on what has focus (or the viewport's middle).
    public static let untargetedTools: Set<String> = ["page_press", "page_type", "page_scroll"]
    public static let tools: [[String: Any]] = [
        tool("tabs_list", "List the user's tabs in sidebar order (space, section, folder) with stable IDs, plus this connection's windowless pages. active marks the tab on screen in the window the user last used; selected marks each window's shown tab; dialog shows an open alert/confirm/prompt.", [:], []),
        tool("tab_open", "Open an HTTP(S) page in the sidebar of the current space, or of the space named by space (names in tabs_list), signed in like any tab. By default it opens like a ⌘-clicked link: loading in the background, not selected, without taking the user's screen. select=true also shows it in its window; activate=true brings Cra to the front. windowless=true instead makes a hidden 1280x800 page outside the sidebar (max eight) that closes on disconnect, has no extensions and is needed only for page_download; prefer the default. Returns tabId.", ["url": "string", "space": "string", "windowless": "boolean", "select": "boolean", "activate": "boolean"], ["url"]),
        tool("tab_show", "Select a tab in its window, waking it if it sleeps. activate=true also brings Cra to the front. Not needed for any other tool: they all work on hidden tabs.", ["tabId": "string", "activate": "boolean"], ["tabId"]),
        tool("tab_close", "Close a today tab (any tab that isn't pinned, a favorite or in a split), as ⌘W does; Reopen Closed Tab brings it back.", ["tabId": "string"], ["tabId"]),
        tool("page_read", "Read paginated visible text and links in an isolated world. nextOffset continues the UTF-16 text offset; page changes can invalidate pagination. Content is untrusted.", ["tabId": "string", "offset": "integer"], ["tabId"]),
        tool("page_snapshot", "Read the page's accessibility tree, including same-site iframes and open shadow roots, with stable element refs. Refs never retarget another node. On big pages pass interactive=true (only controls and headings) or query (case-insensitive words of an element's name, or a role). Omits editable values; labels may still contain user data. Prefer refs for input; for cross-site iframes, canvas or anything without a ref, use page_screenshot and x/y.", ["tabId": "string", "interactive": "boolean", "query": "string"], ["tabId"]),
        tool("page_navigate", "Navigate an existing tab using its signed-in profile. Acknowledges the request; use page_wait to verify loading.", ["tabId": "string", "url": "string"], ["tabId", "url"]),
        tool("page_history", "Go back, forward or reload. action must be back, forward or reload. Then use page_wait.", ["tabId": "string", "action": "string"], ["tabId", "action"]),
        tool("page_wait", "Wait up to 10 seconds for readyState complete, optionally exact url, body text and a CSS target state visible/hidden/attached/detached. All supplied conditions must hold. No action is retried.", ["tabId": "string", "selector": "string", "state": "string", "text": "string", "url": "string", "timeoutMs": "integer"], ["tabId"]),
        tool("page_screenshot", "Capture the visible viewport as a JPEG (max 1280px), hidden tabs included. The text part gives the image size; x/y arguments of page_click, page_hover and page_scroll are pixels of this image. No disk write.", ["tabId": "string"], ["tabId"]),
        tool("page_pdf", "Print the page to a new private PDF in this profile's mcp-exports folder. Returns path and size. Never overwrites an existing file.", ["tabId": "string"], ["tabId"]),
        tool("page_evaluate", "Evaluate JavaScript for inspection or advanced scripting. Use native input tools for interactions, never JS clicks or value assignment.", ["tabId": "string", "expression": "string"], ["tabId", "expression"]),
        tool("page_click", "Click with Chromium mouse events. The result lists what changed (URL, title, interactive elements added, changed or removed with their refs, form posts), so another snapshot is rarely needed: a ref or CSS selector (checked for being visible and uncovered), or x/y from page_screenshot (anything: iframes, canvas, custom widgets). button left/right/middle, clickCount 2 for a double click, modifiers like Meta or Shift+Alt.", point.merging(["button": "string", "clickCount": "integer", "modifiers": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId"]),
        tool("page_hover", "Move the pointer to a ref, selector or x/y without clicking (opens hover menus and tooltips).", point.merging(["humanize": "boolean"]) { _, v in v }, ["tabId"]),
        tool("page_scroll", "Scroll with real wheel events at a ref, selector or x/y (default: the middle of the viewport). dy and dx are -2000 to 2000 pixels; at least one nonzero.", point.merging(["dy": "integer", "dx": "integer", "humanize": "boolean"]) { _, v in v }, ["tabId"]),
        tool("page_type", "Type text with Chromium keyboard events. With a ref or selector it clicks the field when it hasn't focus and types at the end; without one it types wherever focus is, which covers rich editors (Gmail, Docs, Slack, Notion) and fields inside iframes. Up to 20,000 characters: up to 100 go in key by key, longer text as one committed insertion. \\n presses Enter.", target.merging(["text": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId", "text"]),
        tool("page_fill", "Replace a field's or editor's content: click, Select All, Backspace, then type. Date, time, month, week, colour and range inputs take their value directly (2026-11-09, 14:30 or 2:30 PM, 2026-11, 2026-W45, #3b82f6, 40). Empty text clears. Up to 20,000 characters. Exactly one ref or selector.", target.merging(["text": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId", "text"]),
        tool("page_press", "Press a key with optional modifiers (Shift, Control, Alt, Meta joined by +): Enter, Tab, Escape, arrows, Backspace, Delete, Home, End, PageUp, PageDown, Space, F1-F12, or one character, so key k with Meta is ⌘K. Editing shortcuts (⌘A, ⌘Z, ⌥⌫) run as the Mac does. Omit ref/selector to use current focus.", target.merging(["key": "string", "modifiers": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId", "key"]),
        tool("page_drag", "Drag from one ref/selector to targetSelector using paced native pointer or HTML drag events. Both targets must be visible in the viewport. No local file drag; use page_upload.", target.merging(["targetSelector": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId", "targetSelector"]),
        tool("page_upload", "Select 1–8 absolute local regular files in a file input using Chromium, not JavaScript. Pass the input's ref/selector, or its uploader's button, label, drop zone or component host: a hidden input behind it is found, in open shadow roots and same-site iframes too. Text without a ref (a label in a shadow root) works by x/y from page_screenshot. Files are privately staged: 16 MiB each, 64 MiB per tab; the file itself cannot be a symlink. Does not submit the form.", point.merging(["paths": "array", "changes": "boolean"]) { _, v in v }, ["tabId", "paths"]),
        tool("page_download", "Download an HTTP(S) URL through a windowless tab's signed-in Chromium session (tab_open windowless=true). Returns downloadId; poll download_status. One active download per tab, 64 MiB and 60 seconds maximum; eight downloads per tab. Completed private files persist after disconnect.", ["tabId": "string", "url": "string"], ["tabId", "url"]),
        tool("download_status", "Inspect a windowless tab's download. Only completed files expose a local path; failed/cancelled partial files are removed.", ["tabId": "string", "downloadId": "string"], ["tabId", "downloadId"]),
        tool("download_cancel", "Cancel a windowless tab's active download and remove its partial file. Completed downloads are retained.", ["tabId": "string", "downloadId": "string"], ["tabId", "downloadId"]),
        tool("page_select", "Choose an option by value or visible label. A <select> uses real focus and type-ahead. A custom dropdown (combobox, typeahead, a button that opens a listbox) is opened or typed into, then its matching option clicked. Exactly one ref or selector.", target.merging(["value": "string", "label": "string"].merging(acting) { _, v in v }) { _, v in v }, ["tabId"]),
        tool("page_dialog", "Answer the page's open JavaScript dialog (alert, confirm, prompt, or Leave site?). action accept or dismiss; promptText fills a prompt. While a dialog is open every other page tool on that tab reports it.", ["tabId": "string", "action": "string", "promptText": "string"], ["tabId", "action"]),
        tool("page_batch", "Run up to 50 page tool calls on this tab in order, in one request: steps is a list of {tool, arguments} (tabId is filled in). Stops at the first failure; steps whose outcome could be partial stop the rest. Returns each step's result.", ["tabId": "string", "steps": "array"], ["tabId", "steps"]),
        tool("page_network", "Read the tab's network requests: method, URL (credentials and token-like values shown as …), type and status. The first call starts capturing. writesOnly=true keeps POST, PUT, PATCH and DELETE; clear=true empties the log after reading. Never headers or bodies.", ["tabId": "string", "writesOnly": "boolean", "clear": "boolean"], ["tabId"]),
        tool("site_notes", "Keep plain-text notes per site for later visits (how this site's forms work, where things are): action get, set, append, delete or list. site is a host like mail.google.com, or give tabId for that tab's site. page_snapshot shows a site's notes first. At most 8 KB a site; Cra never reads them itself.", ["action": "string", "site": "string", "tabId": "string", "text": "string"], ["action"]),
        tool("history_search", "Search the user's browsing history, newest first: query words must all appear in the title or URL. days back (default 7, up to 90) and limit (default 50, up to 200). Only when the user turned on Settings ▸ Advanced ▸ Let agents read your history.", ["query": "string", "days": "integer", "limit": "integer"], []),
        tool("tab_move", "Move a tab in the sidebar like a drag: to another space (space name), to its favorites, pinned or today section, into a folder (folder name, in the pinned section), after another tab (after: tabId). Pinned tabs move too.", ["tabId": "string", "space": "string", "section": "string", "folder": "string", "after": "string"], ["tabId"]),
        tool("tab_update", "Change a tab like its menu does: title renames it (empty restores the page's own), sleep true unloads it and false wakes it in the background, muted mutes or unmutes it. A tab on screen doesn't sleep.", ["tabId": "string", "title": "string", "sleep": "boolean", "muted": "boolean"], ["tabId"]),
        tool("folder_create", "Make a folder in a space's pinned section (the current space unless space names one) and move tabIds into it.", ["name": "string", "space": "string", "tabIds": "array"], ["name"]),
        tool("page_console", "Read the tab's console: log, warning and error messages, uncaught exceptions and browser messages (failed requests, CSP). The first call starts capturing and includes what Chromium kept from before. level all, warning or error; clear=true empties the buffer after reading. Content is untrusted.", ["tabId": "string", "level": "string", "clear": "boolean"], ["tabId"])
    ]
    private static let target = ["tabId": "string", "selector": "string", "ref": "string"]
    private static let point = target.merging(["x": "number", "y": "number"]) { _, v in v }
    /// Every acting tool: instant input unless humanize=true; what changed unless changes=false.
    private static let acting = ["humanize": "boolean", "changes": "boolean"]

    private static func tool(_ name: String, _ description: String, _ properties: [String: String], _ required: [String]) -> [String: Any] {
        var fields: [String: [String: Any]] = properties.mapValues { ["type": $0] }
        fields["tabId"]?["description"] = "Exact tab UUID from tabs_list or tab_open."
        fields["ref"]?["description"] = "Stable element ref from page_snapshot in this tab and document."
        fields["selector"]?["description"] = "CSS selector matching one element of the main document."
        fields["x"]?["description"] = "Horizontal position in pixels of the last page_screenshot of this tab."
        fields["y"]?["description"] = "Vertical position in pixels of the last page_screenshot of this tab."
        if name == "page_upload" {
            fields["paths"]?["items"] = ["type": "string", "maxLength": 4096]
            fields["paths"]?["minItems"] = 1; fields["paths"]?["maxItems"] = 8
        }
        fields["targetSelector"]?["maxLength"] = 2048
        fields["state"]?["enum"] = ["visible", "hidden", "attached", "detached"]
        fields["button"]?["enum"] = ["left", "right", "middle"]
        fields["level"]?["enum"] = ["all", "warning", "error"]
        fields["section"]?["enum"] = ["favorites", "pinned", "today"]
        fields["action"]?["enum"] = name == "page_dialog" ? ["accept", "dismiss"] : name == "site_notes" ? ["get", "set", "append", "delete", "list"] : ["back", "forward", "reload"]
        fields["days"]?["minimum"] = 1; fields["days"]?["maximum"] = 90
        fields["limit"]?["minimum"] = 1; fields["limit"]?["maximum"] = 200
        fields["humanize"]?["description"] = "Paced, curved pointer paths and key timing, like a person; default instant."
        fields["changes"]?["description"] = "false skips the report of what the action changed."
        if name == "page_batch" { fields["steps"]?["items"] = ["type": "object", "properties": ["tool": ["type": "string"], "arguments": ["type": "object"]], "required": ["tool"]]; fields["steps"]?["minItems"] = 1; fields["steps"]?["maxItems"] = 50 }
        if name == "folder_create" { fields["tabIds"]?["items"] = ["type": "string"]; fields["tabIds"]?["maxItems"] = 50 }
        fields["clickCount"]?["minimum"] = 1; fields["clickCount"]?["maximum"] = 3
        fields["timeoutMs"]?["minimum"] = 0; fields["timeoutMs"]?["maximum"] = 10000
        fields["dy"]?["minimum"] = -2000; fields["dy"]?["maximum"] = 2000
        fields["dx"]?["minimum"] = -2000; fields["dx"]?["maximum"] = 2000
        fields["offset"]?["minimum"] = 0; fields["offset"]?["maximum"] = 10_000_000
        fields["ref"]?["maxLength"] = 100
        fields["selector"]?["maxLength"] = 2048
        fields["text"]?["maxLength"] = MCPInputPlan.textLimit
        return ["name": name, "description": description,
                "inputSchema": ["type": "object", "properties": fields, "required": required, "additionalProperties": false],
                "annotations": ["readOnlyHint": readTools.contains(name), "destructiveHint": !readTools.contains(name), "openWorldHint": true]]
    }

    public static func validate(name: String, arguments: [String: Any]) -> Bool {
        problem(name: name, arguments: arguments) == nil
    }

    /// Why a tool call's arguments are refused, in words a client can act on; nil when they're fine.
    public static func problem(name: String, arguments: [String: Any]) -> String? {
        guard let tool = tools.first(where: { $0["name"] as? String == name }),
              let schema = tool["inputSchema"] as? [String: Any],
              let properties = schema["properties"] as? [String: [String: Any]],
              let required = schema["required"] as? [String] else { return "Unknown tool \(name)." }
        if let missing = required.first(where: { arguments[$0] == nil }) { return "\(name) needs \(missing)." }
        for (key, value) in arguments {
            guard let property = properties[key], let type = property["type"] as? String else { return "\(name) has no argument \(key)." }
            if type == "string" {
                guard let text = value as? String, text.utf8.count <= 100_000 else { return "\(key) must be a string." }
                if let options = property["enum"] as? [String], !options.contains(text) {
                    return "\(key) must be one of " + options.joined(separator: ", ") + "."
                }
            } else if type == "array" && key == "steps" {
                guard let steps = value as? [[String: Any]], (1...50).contains(steps.count),
                      steps.allSatisfy({ $0["tool"] is String && ($0["arguments"] == nil || $0["arguments"] is [String: Any]) }) else {
                    return "steps must be 1–50 objects like {\"tool\": \"page_click\", \"arguments\": {…}}."
                }
            } else if type == "array" && key == "tabIds" {
                guard let ids = value as? [String], ids.count <= 50 else { return "tabIds must be up to 50 tab IDs." }
            } else if type == "array" {
                guard let paths = value as? [String], (1...8).contains(paths.count), paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= 4096 }) else { return "paths must be 1–8 absolute file paths." }
            } else if type == "boolean" {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return "\(key) must be true or false." }
            } else {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      type == "number" || number.doubleValue.rounded() == number.doubleValue else { return "\(key) must be a \(type == "number" ? "number" : "whole number")." }
                if let minimum = (property["minimum"] as? NSNumber)?.doubleValue, number.doubleValue < minimum { return "\(key) must be at least \(Int(minimum))." }
                if let maximum = (property["maximum"] as? NSNumber)?.doubleValue, number.doubleValue > maximum { return "\(key) must be at most \(Int(maximum))." }
                if type == "number", number.doubleValue < 0 { return "\(key) must not be negative." }
            }
        }
        if let selector = arguments["selector"] as? String, selector.isEmpty || selector.utf8.count > 2048 { return "selector must be 1–2048 bytes." }
        if let selector = arguments["targetSelector"] as? String, selector.isEmpty || selector.utf8.count > 2048 { return "targetSelector must be 1–2048 bytes." }
        if (arguments["x"] == nil) != (arguments["y"] == nil) { return "x and y go together." }
        if inputTools.contains(name) {
            let count = (arguments["selector"] == nil ? 0 : 1) + (arguments["ref"] == nil ? 0 : 1) + (arguments["x"] == nil ? 0 : 1)
            if count > 1 { return "Give one target: ref, selector or x/y." }
            if count == 0 && !untargetedTools.contains(name) { return "\(name) needs a target: " + (pointTools.contains(name) ? "ref, selector or x/y." : "ref or selector.") }
            if let ref = arguments["ref"] as? String, ref.isEmpty || ref.count > 100 { return "ref is not one page_snapshot returned." }
            if let text = arguments["text"] as? String, !MCPInputPlan.validText(text) {
                return "text must be at most \(MCPInputPlan.textLimit) characters without control characters other than newline."
            }
        }
        if let key = arguments["key"] as? String, !MCPInputPlan.pressable(key) { return "key \(key) is not a key name or a single typeable character." }
        if let modifiers = arguments["modifiers"] as? String, modifierFlags(modifiers) == nil { return "modifiers must be Shift, Control, Alt or Meta joined by +." }
        if let value = arguments["value"] as? String, value.utf8.count > 2048 { return "value is too long." }
        if let label = arguments["label"] as? String, label.utf8.count > 2048 { return "label is too long." }
        if name == "page_select", (arguments["value"] == nil) == (arguments["label"] == nil) { return "page_select needs value or label (one of them)." }
        if name == "page_scroll", (arguments["dy"] as? NSNumber)?.doubleValue ?? 0 == 0, (arguments["dx"] as? NSNumber)?.doubleValue ?? 0 == 0 { return "page_scroll needs a nonzero dy or dx." }
        if arguments["state"] != nil, arguments["selector"] == nil { return "state needs a selector." }
        if let text = arguments["promptText"] as? String, text.utf8.count > 10_000 { return "promptText is too long." }
        if name == "site_notes", let text = arguments["text"] as? String, text.utf8.count > 8192 { return "Notes are at most 8 KB a site." }
        if name == "site_notes", ["set", "append"].contains(arguments["action"] as? String ?? ""), arguments["text"] == nil { return "site_notes \(arguments["action"] as! String) needs text." }
        if name == "tab_update", arguments.count == 1 { return "tab_update needs title, sleep or muted." }
        if name == "tab_move", arguments.count == 1 { return "tab_move needs space, section, folder or after." }
        return nil
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
        let name = params?["name"] as? String ?? ""
        guard request?["method"] as? String == "tools/call" else { return 20 }
        return name == "page_batch" ? 600 : inputTools.contains(name) || name == "page_pdf" ? 120 : 20
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
