import CraCore
import Foundation
import Testing

struct PullRequestPreviewTests {
    let now = Date(timeIntervalSince1970: 10_000)

    @Test func settingsAndURLs() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.pullRequestPreviews)
        for url in ["https://github.com/a/b/pull/3", "https://github.com/a/b/pull/3/files"] {
            #expect(SidebarTabPreview.kind(for: url, settings: settings) == .pullRequest)
        }
        for url in ["https://github.com/a/b/issues/3", "http://github.com/a/b/pull/3", "https://github.com/a/b/pull/no", "https://other.com/a/b/pull/3"] {
            #expect(SidebarTabPreview.kind(for: url, settings: settings) == nil)
        }
        #expect(SidebarTabPreview.pullRequest.turnOffTitle == nil)
        SidebarTabPreview.pullRequest.turnOff(&settings)
        #expect(!settings.pullRequestPreviews)
        #expect(SidebarTabPreview.kind(for: "https://github.com/a/b/pull/3", settings: settings) == nil)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).pullRequestPreviews)
    }

    @Test func modelFixtureKeepsSnapshotDetails() throws {
        let (sidebar, _) = try ModelFixtureTests.load("sidebar-plugin-folder.json", as: SidebarDocument.self)
        let items = sidebar.items.flatMap { $0.liveFolder?.plugin?.snapshot?.items ?? [] }
        let item = try #require(items.first { $0.url == "https://github.com/example/app/pull/9" })
        #expect(item.updatedAt == ISO8601DateFormatter().date(from: "2026-11-24T09:00:00Z"))
        #expect(item.revision == String(repeating: "a", count: 40))
        #expect(item.details == .init(draft: true, commentCount: 2, labels: [.init(name: "ui", color: "D97757"), .init(name: "tests")], tasks: .init(done: 2, total: 4)))
    }

    @Test func malformedDetailsKeepTheItem() throws {
        let source = #"{"id":"pr","url":"https://github.com/a/b/pull/3","title":"Keep me","updatedAt":"bad","revision":12,"details":{"draft":true,"commentCount":-1,"tasks":{"done":3,"total":2},"labels":[{"color":"fff"},{"name":""},{"name":"keep","color":12},7]}}"#
        let item = try JSONDecoder().decode(LiveFolderPluginItem.self, from: Data(source.utf8))
        #expect(item.title == "Keep me" && item.details?.draft == true)
        #expect(item.updatedAt == nil && item.revision == nil)
        #expect(item.details?.commentCount == nil && item.details?.tasks == nil)
        #expect(item.details?.labels == [.init(name: "keep")])
        for bad in ["7", "[]", "null", #"{"draft":7,"commentCount":"2","labels":false,"tasks":false}"#] {
            let data = Data("{\"id\":\"pr\",\"url\":\"https://github.com/a/b/pull/3\",\"title\":\"Keep me\",\"details\":\(bad)}".utf8)
            let decoded = try JSONDecoder().decode(LiveFolderPluginItem.self, from: data)
            #expect(decoded.details?.draft == nil && decoded.details?.commentCount == nil)
            #expect(decoded.details?.labels == nil && decoded.details?.tasks == nil)
        }
    }

    @Test func cacheFetchesOncePerKey() {
        var cache = PullRequestChecksCache()
        var item = LiveFolderPluginItem(id: "pr", url: "https://github.com/a/b/pull/3", title: "PR", updatedAt: now, revision: "one")
        for result: PullRequestChecks? in [.init(passed: 2), nil, .init()] {
            let key = PullRequestChecksCache.Key(item)
            #expect({ cache.begin(key) }())
            #expect({ !cache.begin(key) }())
            cache.finish(key, checks: result)
            #expect({ !cache.begin(key) }())
            #expect(cache.checks(for: key) == result)
            item.updatedAt = item.updatedAt?.addingTimeInterval(1)
            #expect({ !cache.begin(.init(item)) }())
            item.revision! += "x"
        }
        item.revision = nil
        let key = PullRequestChecksCache.Key(item)
        #expect({ cache.begin(key) }())
        cache.finish(key, checks: nil)
        #expect({ !cache.begin(key) }())
        item.updatedAt = now.addingTimeInterval(1)
        #expect({ cache.begin(.init(item)) }())
        item.url += "0"
        #expect({ cache.begin(.init(item)) }())
    }

    @Test func structuredCardAndOmissions() {
        var item = LiveFolderPluginItem(id: "pr", url: "https://github.com/a/b/pull/3", title: "A title")
        var card = PullRequestPreview.card(item: item, checks: nil, now: now)
        #expect(card.repo == "a/b" && card.number == "3" && card.title == "A title")
        #expect(card.author == nil && !card.draft && card.age == nil)
        #expect(card.checks == nil && card.failing.isEmpty && card.extraFailing == 0)
        #expect(card.labels.isEmpty && card.extraLabels == 0 && card.commentCount == nil && card.tasks == nil)
        item.subtitle = "author"
        item.details = .init(draft: true, commentCount: 2, labels: [
            .init(name: "one", color: "3FB950"), .init(name: "two", color: "#aAbBcC"),
            .init(name: "three", color: "bad"), .init(name: "four"), .init(name: "five")
        ], tasks: .init(done: 2, total: 5))
        card = PullRequestPreview.card(item: item, checks: .init(passed: 8, failed: 5, pending: 1, skipped: 9, failing: ["a", "b", "c", "d", "e"]), now: now)
        #expect(card.author == "author" && card.draft && card.commentCount == 2 && card.tasks == .init(done: 2, total: 5))
        #expect(card.checks?.state == .failed && card.checks?.passed == 8 && card.checks?.total == 14)
        #expect(card.failing == ["a", "b", "c"] && card.extraFailing == 2)
        #expect(card.labels.map(\.name) == ["one", "two", "three"] && card.extraLabels == 2)
        #expect(card.labels[0].color == RGB(63.0 / 255, 185.0 / 255, 80.0 / 255))
        #expect(card.labels[1].color == RGB(170.0 / 255, 187.0 / 255, 204.0 / 255))
        #expect(card.labels[2].color == nil)
        for (checks, state) in [(PullRequestChecks(passed: 8, pending: 3, skipped: 6), PullRequestPreview.Checks.State.pending),
                                (.init(passed: 12, skipped: 6), .passed)] {
            card = PullRequestPreview.card(item: item, checks: checks, now: now)
            #expect(card.checks?.state == state && card.checks?.total == checks.passed + checks.pending)
            #expect(card.failing.isEmpty && card.extraFailing == 0)
        }
        #expect(PullRequestPreview.card(item: item, checks: .init(skipped: 2), now: now).checks == nil)
        item.subtitle = ""
        item.details = .init(commentCount: 0, labels: [.init(name: "no color"), .init(name: "invalid", color: "GG0000"), .init(name: "signed", color: "+12345")])
        card = PullRequestPreview.card(item: item, checks: nil, now: now)
        #expect(card.author == nil && card.commentCount == nil && card.extraLabels == 0)
        #expect(card.labels.allSatisfy { $0.color == nil })
    }

    @Test func labelTextContrast() throws {
        func label(_ hex: String) throws -> PullRequestPreview.Label {
            let item = LiveFolderPluginItem(id: "pr", url: "https://github.com/a/b/pull/3", title: "PR",
                                           details: .init(labels: [.init(name: "label", color: hex)]))
            return try #require(PullRequestPreview.card(item: item, checks: nil, now: now).labels.first)
        }
        func luminance(_ color: RGB) -> Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        }
        let dark = try label("#2700AF")
        let text = try #require(dark.textColor)
        #expect((luminance(text) + 0.05) / (luminance(RGB(25 / 255, 24 / 255, 23 / 255)) + 0.05) >= 4.5)
        #expect(dark.color == RGB(39 / 255, 0, 175 / 255))
        let original = try #require(dark.color)
        #expect(abs(SpaceTheme.hsl(text).h - SpaceTheme.hsl(original).h) < 0.000001)
        for hex in ["#39d965", "FFFFFF", "F8F8F8"] {
            let bright = try label(hex)
            #expect(bright.textColor == bright.color)
        }
        let invalid = try label("invalid")
        #expect(invalid.color == nil && invalid.textColor == nil)
    }

    @Test func githubAgeBoundaries() {
        for (seconds, age) in [(59.0, "just now"), (60, "1 minute ago"), (120, "2 minutes ago"),
                               (3600, "1 hour ago"), (82800, "23 hours ago"), (86400, "yesterday"),
                               (518400, "6 days ago"), (604800, "1 week ago"), (1209600, "2 weeks ago"),
                               (2592000, "1 month ago"), (5184000, "2 months ago"),
                               (31536000, "1 year ago"), (63072000, "2 years ago"), (-1, "just now")] {
            let item = LiveFolderPluginItem(id: "pr", url: "https://github.com/a/b/pull/3", title: "PR", updatedAt: now.addingTimeInterval(-seconds))
            #expect(PullRequestPreview.card(item: item, checks: nil, now: now).age == age)
        }
    }
}
