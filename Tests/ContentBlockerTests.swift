import Foundation

/// The engine's ad and tracker matching (Sources/CraCEF/CraContentBlocker.h) on Cra's own list
/// (resources/blocklist/domains.txt), the list Block Ads & Trackers ships with.
@main
enum ContentBlockerTests {
    private static var checks = 0

    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    private static func blocks(_ request: String, on page: String) -> Bool {
        cra_blocker_should_block(request, page)
    }

    // promise: #586
    /// Reddit stays usable with blocking on. These are the hosts reddit.com's pages loaded in a
    /// signed-in Cra on 20 Nov 2026: the page, its static, image and avatar hosts, chat, telemetry
    /// and Google's reCAPTCHA Enterprise, which its bot check runs. None is blocked on any Reddit
    /// page. Reddit's own trackers on the list are still blocked from other sites, and the cross-site
    /// one is blocked on Reddit too, so the list is in force.
    private static func redditLoadsWithBlockingOn() {
        let pages = ["www.reddit.com", "old.reddit.com", "reddit.com", "new.reddit.com"]
        let needed = [
            "www.reddit.com", "gql.reddit.com", "oauth.reddit.com", "pi.reddit.com", "w3-reporting.reddit.com",
            "www.redditstatic.com", "i.redd.it", "v.redd.it", "preview.redd.it", "external-preview.redd.it",
            "styles.redditmedia.com", "emoji.redditmedia.com", "matrix.redditspace.com",
            "www.google.com", "www.gstatic.com", "www.recaptcha.net", "accounts.google.com",
        ]
        for page in pages {
            for host in needed {
                expect(!blocks(host, on: page), "\(host) is blocked on \(page)")
            }
            // Reddit's own trackers on its own site are first party.
            expect(!blocks("events.reddit.com", on: page), "events.reddit.com is blocked on \(page)")
            expect(!blocks("alb.reddit.com", on: page), "alb.reddit.com is blocked on \(page)")
        }
        expect(blocks("pixel.redditmedia.com", on: "www.reddit.com"), "the list isn't in force on Reddit")
        expect(blocks("events.reddit.com", on: "news.example.com"), "Reddit's tracker isn't blocked on another site")
        expect(blocks("alb.reddit.com", on: "news.example.com"), "Reddit's ad host isn't blocked on another site")
    }

    static func main() {
        let list = try! String(contentsOfFile: "resources/blocklist/domains.txt", encoding: .utf8)
        let count = list.withCString { cra_blocker_load($0) }
        expect(count > 10_000, "Cra's list loaded \(count) domains")
        redditLoadsWithBlockingOn()
        print("Content blocker: \(checks) checks passed")
    }
}
