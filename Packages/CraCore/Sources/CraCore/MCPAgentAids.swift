import Foundation

/// What an action changed on the page: the interactive elements before and after it, compared by
/// ref, so an agent sees a dialog's new fields (with refs to use) without another snapshot.
public enum MCPChanges {
    public struct Element: Equatable {
        public let ref: String
        public let role: String
        public let name: String
        /// Checked, selected, expanded, disabled… as "key=value", sorted, for spotting changes.
        public let state: String
        public init(ref: String, role: String, name: String, state: String = "") {
            self.ref = ref; self.role = role; self.name = name; self.state = state
        }
        var line: String { role + " \"" + name + "\"" + (state.isEmpty ? "" : " [" + state + "]") + " " + ref }
    }

    /// At most `limit` lines in each list; a run of six or more added elements of one role folds
    /// into one line ("48 option: 12:00 AM … 11:30 PM"), so a long menu doesn't drown the rest.
    public static func diff(before: [Element], after: [Element], limit: Int = 40) -> [String: Any] {
        let old = Dictionary(before.map { ($0.ref, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Set(after.map(\.ref))
        var added: [Element] = []
        var changed: [String] = []
        for element in after {
            guard let was = old[element.ref] else { added.append(element); continue }
            if was != element {
                var parts: [String] = []
                if was.name != element.name { parts.append("name was \"\(was.name)\"") }
                if was.state != element.state { parts.append("was [\(was.state)]") }
                if was.role != element.role { parts.append("role was \(was.role)") }
                changed.append(element.line + " (" + parts.joined(separator: ", ") + ")")
            }
        }
        let removed = before.filter { !new.contains($0.ref) }.map { $0.role + " \"" + $0.name + "\" " + $0.ref }
        var result: [String: Any] = [:]
        if !added.isEmpty { result["added"] = capped(fold(added), limit) }
        if !changed.isEmpty { result["changed"] = capped(changed, limit) }
        if !removed.isEmpty { result["removed"] = removed.count > 5 ? ["\(removed.count) elements"] + Array(removed.prefix(3)) : removed }
        return result
    }

    static func fold(_ elements: [Element]) -> [String] {
        var lines: [String] = []
        var index = 0
        while index < elements.count {
            var end = index
            while end + 1 < elements.count, elements[end + 1].role == elements[index].role { end += 1 }
            let run = elements[index...end]
            if run.count >= 6 {
                lines.append("\(run.count) \(run.first!.role): \(run.first!.name) … \(run.last!.name) (\(run.first!.ref) … \(run.last!.ref))")
                lines += run.filter { !$0.state.isEmpty && $0.state != "disabled=false" }.prefix(3).map(\.line)
            } else {
                lines += run.map(\.line)
            }
            index = end + 1
        }
        return lines
    }

    static func capped(_ lines: [String], _ limit: Int) -> [String] {
        lines.count <= limit ? lines : Array(lines.prefix(limit)) + ["… \(lines.count - limit) more; page_snapshot interactive=true for all"]
    }
}

/// URLs as an agent sees them in network reports: no user info or fragment, and the values of
/// query keys that look like credentials (and path segments that look like tokens) shown as "…".
public enum MCPRedaction {
    static let secretKeys = ["code", "token", "pass", "secret", "key", "sig", "auth", "session", "state", "nonce", "jwt", "otp", "ticket", "credential", "sid"]

    public static func url(_ text: String) -> String {
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased() else { return "…" }
        guard scheme == "http" || scheme == "https", let host = parts.host else { return scheme + ":…" }
        var out = scheme + "://" + host + (parts.port.map { ":\($0)" } ?? "")
        out += parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            let s = String(segment)
            let mixed = s.count >= 20 && s.contains(where: \.isLetter) && s.contains(where: \.isNumber)
            return mixed || s.contains(":") ? "…" : s
        }.joined(separator: "/")
        if let query = parts.percentEncodedQuery, !query.isEmpty {
            out += "?" + query.split(separator: "&").map { pair -> String in
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(kv[0])
                let plain = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || "_.-[]".contains($0) }
                if !plain { return "…=…" }
                if kv.count == 1 { return name }
                return secretKeys.contains(where: name.lowercased().contains) ? name + "=…" : name + "=" + kv[1]
            }.joined(separator: "&")
        }
        return String(out.prefix(500))
    }
}

/// Values for inputs that can't be typed into (date, time, colour, range): their format checked
/// and normalised before Cra sets one, as Playwright's fill does.
public enum MCPFieldValue {
    public static let types: Set<String> = ["date", "time", "datetime-local", "month", "week", "color", "range"]

    /// The value the input takes, or nil when `value` isn't in the type's format. Empty clears.
    public static func normalized(type: String, value raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return "" }
        switch type {
        case "date": return date(value)
        case "time": return time(value)
        case "datetime-local":
            let parts = value.split(whereSeparator: { $0 == "T" || $0 == " " }).map(String.init)
            guard parts.count == 2 || parts.count == 3, let d = date(parts[0]),
                  let t = time(parts.dropFirst().joined(separator: " ")) else { return nil }
            return d + "T" + t
        case "month":
            return value.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil ? value : nil
        case "week":
            guard value.range(of: #"^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
            return value.uppercased()
        case "color":
            let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            if hex.count == 6 { return "#" + hex.lowercased() }
            if hex.count == 3 { return "#" + hex.lowercased().map { "\($0)\($0)" }.joined() }
            return nil
        case "range": return Double(value).map { _ in value }
        default: return nil
        }
    }

    static func date(_ value: String) -> String? {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), parts[1].count == 2, parts[2].count == 2 else { return nil }
        var components = DateComponents(); components.year = y; components.month = m; components.day = d
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == d else { return nil }
        return value
    }

    /// "14:30", "14:30:05", "14:30:05.250", "2:30 PM" → 24-hour "HH:MM[:SS[.mmm]]".
    static func time(_ value: String) -> String? {
        let upper = value.uppercased()
        let pm = upper.hasSuffix("PM"), am = upper.hasSuffix("AM")
        let clock = (pm || am) ? String(upper.dropLast(2)).trimmingCharacters(in: .whitespaces) : upper
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count), var hour = Int(parts[0]), let minute = Int(parts[1]), parts[1].count == 2,
              (0...59).contains(minute) else { return nil }
        if pm || am {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (pm ? 12 : 0)
        }
        guard (0...23).contains(hour) else { return nil }
        var out = String(format: "%02d:%02d", hour, minute)
        if parts.count == 3 {
            let seconds = parts[2].split(separator: ".", omittingEmptySubsequences: false)
            guard let s = Int(seconds[0]), seconds[0].count == 2, (0...59).contains(s), seconds.count <= 2 else { return nil }
            out += ":" + seconds[0]
            if seconds.count == 2 {
                guard (1...3).contains(seconds[1].count), Int(seconds[1]) != nil else { return nil }
                out += "." + seconds[1]
            }
        }
        return out
    }
}

/// Plain-text notes an agent keeps per site (Cra never reads them): one file per `host[:port]`.
public enum MCPSiteNotes {
    public static let limit = 8192

    /// "https://Mail.Google.com:443/x" or "mail.google.com" → "mail.google.com"; nil when it isn't
    /// a host (paths, schemes other than http(s), anything that could leave the notes folder).
    public static func site(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parsed = URLComponents(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
        guard let parts = parsed, let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host?.lowercased(), !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }), !host.hasPrefix("."), !host.contains("..") else { return nil }
        if trimmed.contains("://") == false, trimmed.contains("/") { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        if let port = parts.port, port != defaultPort, !(port == 443 && scheme == "http") { return host + ":" + String(port) }
        return host
    }

    public static func fileName(_ site: String) -> String { site.replacingOccurrences(of: ":", with: "_") + ".md" }
}

/// The browsing history an agent searches (history_search), newest first.
public enum MCPHistory {
    public static func search(_ entries: [HistoryEntry], query: String?, since: Date, limit: Int) -> [HistoryEntry] {
        let words = (query ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in
            let lower = entry.url.lowercased()
            guard entry.lastVisit >= since, lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
            let text = entry.title.lowercased() + " " + lower
            return words.allSatisfy(text.contains)
        }
        .sorted { $0.lastVisit > $1.lastVisit }
        .prefix(max(0, limit))
        .map { $0 }
    }
}
