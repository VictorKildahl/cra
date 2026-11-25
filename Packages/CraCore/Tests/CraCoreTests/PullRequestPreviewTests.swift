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

    @Test func cardLinesAndOmissions() {
        var item = LiveFolderPluginItem(id: "pr", url: "https://github.com/a/b/pull/3", title: "A title")
        var card = PullRequestPreview.card(item: item, checks: nil, now: now)
        #expect(card.header == "a/b #3" && card.title == "A title")
        #expect(card.checks == nil && card.failing.isEmpty && card.labels == nil && card.activity == nil && card.updated == nil)
        item.details = .init(draft: true, commentCount: 1, labels: ["one", "two", "three", "four", "five"].map { .init(name: $0) }, tasks: .init(done: 2, total: 4))
        item.updatedAt = now
        card = PullRequestPreview.card(item: item, checks: .init(passed: 2, failed: 1, pending: 1, skipped: 9, failing: ["Build"]), now: now)
        #expect(card.header == "a/b #3 · Draft")
        #expect(card.checks == "1 failing check · 2/4 passed" && card.failing == ["Build"])
        #expect(card.labels == "one, two, three +2")
        #expect(card.activity == "1 comment · 2 of 4 tasks" && card.updated == "Updated just now")
        card = PullRequestPreview.card(item: item, checks: .init(failed: 4, failing: ["a", "b", "c", "d"]), now: now)
        #expect(card.checks == "4 failing checks · 0/4 passed" && card.failing == ["a", "b", "c"])
        for (checks, line) in [(PullRequestChecks(passed: 2, pending: 1), "1 pending check · 2/3 passed"),
                               (.init(pending: 2), "2 pending checks · 0/2 passed"), (.init(passed: 3, skipped: 2), "All checks passed · 3/3 passed")] {
            #expect(PullRequestPreview.card(item: item, checks: checks, now: now).checks == line)
        }
        #expect(PullRequestPreview.card(item: item, checks: .init(skipped: 2), now: now).checks == nil)
        for (seconds, text) in [(300.0, "5 min"), (10800, "3 h"), (172800, "2 d")] {
            item.updatedAt = now.addingTimeInterval(-seconds)
            #expect(PullRequestPreview.card(item: item, checks: nil, now: now).updated == "Updated \(text) ago")
        }
        item.details = .init(draft: false, commentCount: 2, labels: [.init(name: "one")])
        card = PullRequestPreview.card(item: item, checks: nil, now: now)
        #expect(card.header == "a/b #3" && card.labels == "one" && card.activity == "2 comments")
        item.details = .init(commentCount: 0, labels: [], tasks: .init(done: 0, total: 1))
        #expect(PullRequestPreview.card(item: item, checks: nil, now: now).activity == "0 of 1 tasks")
        item.details = .init(commentCount: 0, labels: [])
        card = PullRequestPreview.card(item: item, checks: nil, now: now)
        #expect(card.activity == nil && card.labels == nil)
    }
}
