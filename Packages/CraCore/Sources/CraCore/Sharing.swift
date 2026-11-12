import Foundation

/// Settings ▸ Privacy ▸ Sharing and onboarding's Privacy step: Dia's DisclosureView has a second
/// row, "Help improve Dia by sharing content data". Cra's shares less: a daily report of ranges
/// and changed settings (UsageStats) and crash reports with nothing that names the user or the
/// Mac (CrashReports). Both are off until the user says so; after a crash Cra asks first.
/// docs/sharing.md lists every field, and crabrowser.app/privacy says the same.
public enum Sharing {
    public static let base = "https://crabrowser.app"

    /// Release builds of the real app report; dev builds (no SUFeedURL), CRA_DATA_DIR test copies
    /// and renamed bundles never do, unless CRA_SHARING_ENDPOINT points them somewhere on purpose.
    public static func mayReport(hasUpdateFeed: Bool, testDataFolder: Bool, bundleID: String?, endpointOverride: Bool) -> Bool {
        endpointOverride || (hasUpdateFeed && !testDataFolder && bundleID == "dk.kildahl.cra")
    }

    public static func statsURL(base: String?) -> URL { url(base, "api/stats") }
    public static func crashURL(base: String?) -> URL { url(base, "api/crash") }

    private static func url(_ base: String?, _ path: String) -> URL {
        var b = base ?? Self.base
        if !b.hasSuffix("/") { b += "/" }
        return URL(string: b + path)!
    }
}

/// sharing.json in the data folder: when the last usage report went out and how far the crash
/// reports have been looked at. In the data folder rather than UserDefaults, so a CRA_DATA_DIR
/// test copy keeps its own.
public struct SharingState: Codable, Equatable, Sendable {
    public var statsSentAt: Date?
    public var crashesSeenUntil: Date?
    public init(statsSentAt: Date? = nil, crashesSeenUntil: Date? = nil) {
        self.statsSentAt = statsSentAt
        self.crashesSeenUntil = crashesSeenUntil
    }
}

/// After a crash: ask before sending the report (the default), send it without asking, or never.
public enum CrashReportChoice: String, Codable, CaseIterable, Sendable {
    case ask, send, never
}

public extension AppSettings {
    /// Onboarding's one row, as Dia's: on shares usage stats and sends crash reports without
    /// asking; off shares nothing and asks after a crash (Never stays Never).
    var sharesToImproveCra: Bool { shareUsageStats && crashReports == .send }

    mutating func setSharesToImproveCra(_ on: Bool) {
        shareUsageStats = on
        if on { crashReports = .send } else if crashReports == .send { crashReports = .ask }
    }
}

/// The sidebar's "Help improve Cra" card (above the space dock, below the update banners): asks a
/// Mac that never answered onboarding's row, such as one that updated from before 0.1.39, until it
/// answers. Only the released app asks, since only it reports (Sharing.mayReport).
public enum SharingPrompt {
    public static func shows(_ settings: AppSettings, mayReport: Bool, onboarding: Bool) -> Bool {
        mayReport && !onboarding && !settings.shareUsageStats && !settings.askedToShare
    }
}

public extension AppSettings {
    /// The card's Share row (true) or its ✕ (false). Usage stats only: crash reports keep asking.
    mutating func answerSharingPrompt(share: Bool) {
        if share { shareUsageStats = true }
        askedToShare = true
    }
}

// MARK: - Usage stats

/// The daily report: one per UTC day, so a day's reports count that day's users per version. A
/// fresh random id each time, so two reports can't be tied together; counts are ranges; settings
/// are only the ones changed from the default, and never a list or text.
public struct UsageStats: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var build: String
    public var macOS: String
    public var arch: String
    public var memoryGB: Int
    public var spaces: String
    public var profiles: String
    public var tabs: String
    public var extensions: String
    public var settings: [String: String]

    public init(id: UUID, version: String, build: String, os: OperatingSystemVersion, arch: String, memoryBytes: UInt64,
                spaces: Int, profiles: Int, tabs: Int, extensions: Int, settings: AppSettings) {
        self.id = id.uuidString
        self.version = version
        self.build = build
        macOS = "\(os.majorVersion).\(os.minorVersion)"
        self.arch = arch
        memoryGB = Int((Double(memoryBytes) / Double(1 << 30)).rounded())
        self.spaces = Self.bucket(spaces)
        self.profiles = Self.bucket(profiles)
        self.tabs = Self.bucket(tabs)
        self.extensions = Self.bucket(extensions)
        self.settings = Self.changedSettings(settings)
    }

    /// Never sent, or not yet on this UTC day. A date ahead of now (the clock went back) counts as due.
    public static func isDue(lastSent: Date?, now: Date) -> Bool {
        guard let lastSent else { return true }
        return lastSent > now || utcDay(lastSent) != utcDay(now)
    }

    private static func utcDay(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 86400).rounded(.down)) }

    public static func bucket(_ n: Int) -> String {
        switch n {
        case ...0: return "0"
        case 1: return "1"
        case 2...3: return "2–3"
        case 4...5: return "4–5"
        case 6...10: return "6–10"
        case 11...20: return "11–20"
        case 21...50: return "21–50"
        case 51...100: return "51–100"
        default: return "101+"
        }
    }

    /// On/off, choice and number settings: the ones a report may name when they differ from the default.
    public static let reportedSettings: Set<String> = [
        "autoArchive", "autoArchiveEnabled", "autoPictureInPicture", "blockAdsAndTrackers", "blockCookieBanners",
        "boostsEnabled", "calendarHoverPreview", "commandBarCurrentSpaceOnly", "calendarMeetingLink", "calendarTimeToNextMeeting", "chromeEngine",
        "crashReports", "defaultLinkDestination", "edgeToEdgeContent", "editAddressInPlace", "favoriteLogoOutline", "favoritePreviews", "fingerprintingProtection", "fiveSecondPreviews",
        "folderPreviews", "hapticFeedbackOnReorder", "httpsOnly", "keepInMenuBar", "littleWindowArchiveAfter",
        "littleWindowOnOptionCommandClick", "littleWindowShortcutEverywhere", "liveCalendar", "mediaLibraryEnabled", "newTabButtonAtTop", "newTabsAtTop",
        "openLinksInForeground", "pageTopWindowDrag", "peekExpandInSourceTab", "peekInEveryTab", "peekLinksToOtherSites", "peekOnShiftClick",
        "perfRecording", "recentPagesPreviews", "restoreWindows", "searchEngine", "searchSuggestions", "shareThemeWithWebsites",
        "sharedFavorites", "showSpaceHeaderOnSingleSpace", "showStatusBar", "showToolbar", "soundEffects",
        "startOnNewTab", "tabSleepAfter", "tabSleepOnMemoryPressure", "tabSleepTimerEnabled", "tidyDownloads",
        "tidyTabTitles", "tidyTabs", "toolbarShowsFullURL", "warnBeforeQuitting", "websiteAppearance",
        "allowAppleEventsJavaScript", "perfHidesSiteNames",
    ]

    /// Lists, folders, sites and one-time marks: never in a report. Sharing itself is always on
    /// when a report goes out.
    public static let unreportedSettings: Set<String> = [
        "developerHosts", "disabledDefaultDeveloperHosts", "autoPictureInPictureSites", "linkRoutes", "mediaFolders", "mediaHidden",
        "downloadLocations", "newDocumentApps", "hasSeenImportPrompt", "toolbarDefaultMigrated", "newTabButtonDefaultMigrated",
        "autoArchiveDays", "shareUsageStats", "askedToShare",
    ]

    public static func changedSettings(_ settings: AppSettings) -> [String: String] {
        guard let now = scalars(settings), let defaults = scalars(AppSettings()) else { return [:] }
        var out: [String: String] = [:]
        for key in reportedSettings {
            guard let value = now[key], value != defaults[key] else { continue }
            out[key] = value
        }
        return out
    }

    /// The settings file's top-level values that are a switch, a choice or a number, as text.
    private static func scalars(_ settings: AppSettings) -> [String: String]? {
        guard let data = try? JSONEncoder().encode(settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (key, value) in json {
            if let n = value as? NSNumber {
                out[key] = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
            } else if let s = value as? String, s.count <= 40, !s.contains("/"), !s.contains(".") {
                out[key] = s
            }
        }
        return out
    }

    public func json() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data()
    }
}

// MARK: - Crash reports

/// macOS's crash reports (~/Library/Logs/DiagnosticReports/*.ips), cut down to what finds the bug.
public enum CrashReports {
    public static let maxPerLaunch = 5
    public static let maxBytes = 512 * 1024

    public struct File: Equatable, Sendable {
        public var name: String
        public var modified: Date
        public init(name: String, modified: Date) {
            self.name = name
            self.modified = modified
        }
    }

    /// Cra's reports written since `seenUntil`, newest first. The first look (no `seenUntil`)
    /// sends nothing: reports from before the user chose are not theirs to send.
    public static func pending(_ files: [File], seenUntil: Date?, now: Date) -> (send: [String], seenUntil: Date) {
        guard let seenUntil else { return ([], now) }
        let new = files.filter { $0.name.hasSuffix(".ips") && DiagnosticsRedaction.isCraCrashReport($0.name) && $0.modified > seenUntil }
            .sorted { $0.modified > $1.modified }
            .prefix(maxPerLaunch)
            .map(\.name)
        return (Array(new), max(now, seenUntil))
    }

    /// Cra itself, not one of its helpers: the report of Cra quitting.
    public static func isAppQuit(_ name: String) -> Bool { name.hasPrefix("Cra-") }

    private static let headerKeys: Set<String> = [
        "app_name", "app_version", "build_version", "slice_uuid", "bundleID", "bug_type", "os_version", "name", "platform",
    ]
    private static let bodyKeys: Set<String> = [
        "bug_type", "cpuType", "translated", "procName", "procRole", "modelCode", "osVersion", "bundleInfo",
        "exception", "termination", "asi", "ktriageinfo", "faultingThread", "threads", "lastExceptionBacktrace",
        "usedImages", "legacyInfo", "sharedCache", "uptime",
    ]
    private static let threadKeys: Set<String> = ["triggered", "id", "name", "queue", "frames"]
    private static let imageKeys: Set<String> = [
        "source", "arch", "base", "size", "uuid", "name", "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
    ]

    /// The report as sent: `{ "id", "header", "body" }` with only the fields above, thread
    /// registers and file paths dropped, and addresses and the home folder redacted as in
    /// Help ▸ Export Diagnostics. Nil for a file that isn't an .ips report.
    public static func reduce(ips: String, id: UUID, home: String) -> Data? {
        let lines = ips.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2,
              let header = try? JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any] else { return nil }
        var keptBody = body.filter { bodyKeys.contains($0.key) }
        if let threads = body["threads"] as? [[String: Any]] {
            keptBody["threads"] = threads.map { $0.filter { threadKeys.contains($0.key) } }
        }
        if let images = body["usedImages"] as? [[String: Any]] {
            keptBody["usedImages"] = images.map { $0.filter { imageKeys.contains($0.key) } }
        }
        let keptHeader = header.filter { headerKeys.contains($0.key) }
        guard var data = encode(id: id, header: keptHeader, body: keptBody, home: home) else { return nil }
        if data.count > maxBytes, let threads = keptBody["threads"] as? [[String: Any]] {
            keptBody["threads"] = threads.filter { $0["triggered"] as? Bool == true }
            guard let smaller = encode(id: id, header: keptHeader, body: keptBody, home: home) else { return nil }
            data = smaller
        }
        return data.count <= maxBytes ? data : nil
    }

    private static func encode(id: UUID, header: [String: Any], body: [String: Any], home: String) -> Data? {
        let report: [String: Any] = ["id": id.uuidString, "header": header, "body": body]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        let text = DiagnosticsRedaction.redact(String(decoding: data, as: UTF8.self), home: home)
        // Any user's home, not only this one's: a report can name a folder of another account,
        // or Cra can run with another home (CFFIXED_USER_HOME). crabrowser.app refuses /Users/.
        return Data(text.replacingOccurrences(of: #"/Users/[^/\s"']+"#, with: "~", options: .regularExpression).utf8)
    }
}
