import Foundation

/// Which releases a Mac updates to (GitHub #476). New takes each release the day it ships; Stable takes a release
/// once Victor has promoted it (`scripts/promote.sh`), so a release that breaks something can be left behind.
/// Each Mac keeps its own choice, next to Sparkle's own settings, and starts on New: it is on a New build already,
/// and Sparkle never installs an older version, so Stable would hold a Mac on what it has.
///
/// Every release carries three feeds per CPU (docs/release.md, "Channels"):
/// - `appcast.xml`: what every Cra reads, and New. The Stable release, then the newest one, which only a Cra on
///   Chrome's engine (0.1.44 and later) may install (`AppcastRelease.firstEngineBuild`), so a Cra on CEF
///   (0.1.43 and before) takes Stable. Cra up to 0.1.45 has no channel switch and reads only this feed.
/// - `appcast-stable.xml`: only the Stable release.
public enum UpdateChannel: String, CaseIterable, Sendable {
    case new
    case stable

    /// The choice stored in user defaults; anything else is New.
    public init(stored: String?) {
        self = stored.flatMap(UpdateChannel.init(rawValue:)) ?? .new
    }

    public var title: String {
        switch self {
        case .new: "New"
        case .stable: "Stable"
        }
    }

    /// The channel's feed, from the build's own (`SUFeedURL`, or a test's `CRA_UPDATE_FEED`): New reads it as it
    /// is, Stable reads the `appcast-stable` feed beside it (`appcast-intel.xml` → `appcast-stable-intel.xml`).
    public func feedURL(from feed: String) -> String {
        guard self == .stable, let slash = feed.lastIndex(of: "/"),
              feed[feed.index(after: slash)...].hasPrefix("appcast") else { return feed }
        let name = feed[feed.index(after: slash)...]
        return String(feed[...slash]) + "appcast-stable" + name.dropFirst("appcast".count)
    }
}

/// One release in a Sparkle feed.
public struct AppcastRelease: Equatable, Sendable {
    /// The build of Cra 0.1.44, the first on Chrome's engine. A New release in `appcast.xml` asks for it
    /// (`sparkle:minimumUpdateVersion`), which every Cra since 0.1.2 (Sparkle 2.10) reads.
    public static let firstEngineBuild = "202611161309"

    /// "0.1.43" (`sparkle:shortVersionString`).
    public var version: String
    /// "202611131845" (`sparkle:version`), what Sparkle compares.
    public var build: String
    /// The update archive (`Cra.zip`, `Cra-Intel.zip`).
    public var archiveURL: String

    public init(version: String, build: String, archiveURL: String) {
        self.version = version
        self.build = build
        self.archiveURL = archiveURL
    }

    /// The disk image released beside the archive (`Cra.zip` → `Cra.dmg`), what a person downloads to install it.
    public var diskImageURL: String? {
        archiveURL.hasSuffix(".zip") ? String(archiveURL.dropLast(4)) + ".dmg" : nil
    }

    /// Whether this release is older than `build`. Sparkle never installs an older release, so Settings offers its
    /// disk image instead.
    public func isOlder(than build: String) -> Bool {
        self.build.compare(build, options: .numeric) == .orderedAscending
    }

    /// The releases in a feed, in its order. An item without a version or an archive is left out.
    public static func parse(_ data: Data) -> [AppcastRelease] {
        let reader = FeedReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.releases
    }
}

private final class FeedReader: NSObject, XMLParserDelegate {
    var releases: [AppcastRelease] = []
    private var inItem = false
    private var text = ""
    private var version: String?
    private var build: String?
    private var archive: String?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch qualifiedName ?? name {
        case "item":
            inItem = true
            (version, build, archive) = (nil, nil, nil)
        case "enclosure" where inItem:
            archive = attributes["url"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch qualifiedName ?? name {
        case "sparkle:shortVersionString" where inItem: version = value
        case "sparkle:version" where inItem: build = value
        case "item":
            inItem = false
            if let version, let build, let archive {
                releases.append(AppcastRelease(version: version, build: build, archiveURL: archive))
            }
        default:
            break
        }
        text = ""
    }
}
