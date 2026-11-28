import CraCore
import Foundation
import Testing

struct DesktopFilterListsTests {
    @Test func catalogGroupsOrderAndCountOnlyKnownSubscriptions() throws {
        let groups = DesktopFilterList.groups(selected: Set(DesktopFilterList.strictAddresses + ["https://custom.example/list"]))
        #expect(groups.map(\.category) == [.ads, .tracking, .security, .mixed, .cookies, .social, .annoyances, .compatibility, .regional])
        #expect(groups.map(\.selectedCount) == [1, 1, 0, 0, 0, 0, 0, 0, 0])
        #expect(groups[0].entries.first?.name == "EasyList")
        #expect(groups[1].entries.first?.name == "EasyPrivacy")
        let entries = groups.flatMap(\.entries)
        #expect(entries.count == DesktopFilterList.catalog.count)
        // One row per subscription: two rows with one address would switch together.
        #expect(Set(entries.map(\.address)).count == entries.count)
        #expect(entries.allSatisfy { !$0.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let regional = try #require(groups.last).entries
        for (lhs, rhs) in zip(regional, regional.dropFirst()) {
            let order = lhs.name.localizedStandardCompare(rhs.name)
            #expect(order == .orderedAscending || (order == .orderedSame && lhs.detail.localizedStandardCompare(rhs.detail) != .orderedDescending))
        }
    }

    @Test func catalogUsesUniqueHTTPSAddresses() {
        let addresses = DesktopFilterList.catalog.map(\.address)
        #expect(addresses.count == Set(addresses).count)
        #expect(addresses.allSatisfy { CustomBlocklist.listURL(from: $0)?.scheme == "https" })
    }

    @Test func strictIsEasyListAndEasyPrivacyOnTopOfStandard() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.blocksAdsAndTrackers && settings.adBlockingLevel == .standard)
        #expect(settings.adAwayEnabled && settings.anudeepEnabled && settings.customBlocklists.isEmpty)
        for address in DesktopFilterList.strictAddresses {
            #expect(DesktopFilterList.catalog.contains { $0.address == address })
        }
        settings.adBlockingLevel = .strict
        // Strict also turns on the lists with YouTube's, X's and Instagram's page rules (#845).
        #expect(settings.customBlocklists == DesktopFilterList.strictAddresses + DesktopFilterList.strictPageAddresses)
        settings = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.adBlockingLevel == .strict)
        settings.adBlockingLevel = .standard
        #expect(settings.customBlocklists.isEmpty)
        #expect(settings.adAwayEnabled && settings.anudeepEnabled)
    }

    @Test func oneOfStrictsListsAloneIsStillStandard() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        settings.setFilterList(DesktopFilterList.strictAddresses[0], enabled: true)
        #expect(settings.adBlockingLevel == .standard)
        settings.adBlockingLevel = .strict
        #expect(Set(settings.customBlocklists) == Set(DesktopFilterList.strictAddresses + DesktopFilterList.strictPageAddresses))
    }

    @Test func theMainSwitchTurnsEveryListOffAndComesBackStandard() throws {
        let added = "https://lists.example/rules.txt"
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        settings.adBlockingLevel = .strict
        settings.setFilterList(added, enabled: true)
        settings.blocksAdsAndTrackers = false
        #expect(!settings.adAwayEnabled && !settings.anudeepEnabled)
        #expect(settings.customBlocklists == [added])
        #expect(!settings.blocksAdsAndTrackers)
        settings.blocksAdsAndTrackers = true
        #expect(settings.adAwayEnabled && settings.anudeepEnabled)
        #expect(settings.adBlockingLevel == .standard && settings.customBlocklists == [added])
    }

    @Test func strictListsAloneKeepTheMainSwitchOn() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        settings.adBlockingLevel = .strict
        settings.adAwayEnabled = false
        settings.anudeepEnabled = false
        #expect(settings.blocksAdsAndTrackers)
    }

    @Test func togglesRememberCustomURLsAndNeverRemovePresets() throws {
        let preset = try #require(DesktopFilterList.catalog.first?.address)
        let custom = "https://lists.example/rules.txt"
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        for address in [preset, custom] {
            settings.setFilterList(address, enabled: true)
            settings.setFilterList(address, enabled: false)
        }
        settings = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.customBlocklists.isEmpty)
        #expect(settings.customFilterAddresses == [custom])
        for address in [preset, custom, custom] { settings.setFilterList(address, enabled: true) }
        #expect(settings.customBlocklists == [preset, custom])
        #expect(settings.disabledCustomBlocklists.isEmpty)
        settings.forgetFilterList(custom)
        #expect(settings.customFilterAddresses.isEmpty)
        settings.setFilterList(custom, enabled: true)
        #expect(settings.customFilterAddresses == [custom])
    }

    @Test func warningRecoveryFollowsItsSubscription() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        let address = DesktopFilterList.warningListAddress
        #expect(!settings.removesAdblockWarnings)
        settings.setFilterList(address, enabled: true)
        #expect(settings.removesAdblockWarnings)
        settings.disabledCustomBlocklists.append(address)
        #expect(!settings.removesAdblockWarnings)
        settings.setFilterList(address, enabled: false)
        #expect(!settings.removesAdblockWarnings)
    }

    @Test func subscriptionSwitchesAreIndependent() throws {
        func address(_ name: String) throws -> String {
            try #require(DesktopFilterList.catalog.first { $0.name == name }?.address)
        }
        let popup = try address("AdGuard Popups"), widget = try address("AdGuard Widgets")
        let pro = try address("HaGeZi Multi PRO"), mini = try address("HaGeZi Multi PRO Mini")
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.customBlocklists.isEmpty)
        for item in [popup, widget, pro, mini] { settings.setFilterList(item, enabled: true) }
        #expect(settings.customBlocklists == [popup, widget, pro, mini])
        settings.setFilterList(popup, enabled: false)
        settings.setFilterList(pro, enabled: true)
        #expect(settings.customBlocklists == [widget, pro, mini])
        for saved in [[pro, widget, mini], [mini, popup, pro]] {
            let data = try JSONEncoder().encode(["customBlocklists": saved])
            let restored = try JSONDecoder().decode(AppSettings.self, from: data)
            #expect(restored.customBlocklists == saved)
        }
        #expect(settings.customFilterAddresses.isEmpty)
    }

    @Test func legacyOffAndIndependentChoicesSurviveReload() throws {
        let old = Data(#"{"blockAdsAndTrackers":false,"customBlocklists":["https://example.org/list"],"personalBlockFilters":"ads.example"}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(!settings.hasActiveBlockFilters)
        #expect(settings.customFilterAddresses == ["https://example.org/list"])
        #expect(settings.activePersonalFilters == nil)
        settings.setFilterList("https://example.org/list", enabled: true)
        settings = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.hasActiveBlockFilters && !settings.blockAdsAndTrackers)
        settings.setFilterList("https://example.org/list", enabled: false)
        settings.personalFiltersEnabled = true
        #expect(settings.hasActiveBlockFilters && settings.activePersonalFilters == "ads.example")
        settings.adAwayEnabled = true
        #expect(!settings.anudeepEnabled)
    }

    @Test func sitePauseIsExactPersistentAndReversible() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        let host = try #require(AppSettings.filterHost("https://News.Example:8443/article"))
        #expect(host == "news.example")
        #expect(AppSettings.filterHost("file:///tmp/test") == nil)
        settings.toggleFilters(on: host)
        let saved = try JSONEncoder().encode(settings)
        settings = try JSONDecoder().decode(AppSettings.self, from: saved)
        #expect(settings.pausedFilterHosts == [host])
        let rules = DesktopNetworkRules.siteExceptions(for: [host], after: 100)
        #expect(rules.map(\.id) == [101, 102])
        #expect(rules.allSatisfy { $0.priority > 4 && $0.action.type == "allowAllRequests" && $0.condition.resourceTypes == ["main_frame"] })
        settings.toggleFilters(on: host)
        #expect(settings.pausedFilterHosts == nil)
        #expect(settings.blockAdsAndTrackers)
    }

    @Test func hostProjectionDoesNotWidenScopedFilters() {
        let list = DesktopHidingRules.read("""
        ||tracker.example^$third-party
        ||cdn.example^$script
        ||excepted.example^
        @@||media.excepted.example/allowed.png
        !#if ext_ublock
        ||conditional.example^
        ##.conditional
        !#endif
        """, address: "fixture", fetched: .distantPast)
        #expect(list.domains == ["tracker.example"])
        #expect(list.hidingRules.isEmpty)
    }

    @Test func chromiumNetworkConditionsAndCacheMigration() throws {
        let text = """
        0.0.0.0 ads.example
        ||cdn.example/ad/*$script,third-party,domain=reader.example|~pay.reader.example
        @@||cdn.example/ad/consent.js$script,domain=reader.example
        @@||trusted.example^$document
        ||cdn.example^$redirect=noop.js
        """
        let list = DesktopHidingRules.read(text, address: "fixture", fetched: Date(timeIntervalSince1970: 10))
        #expect(CachedBlocklist(text: list.text) == list)
        #expect(list.plainDomains == ["ads.example"])
        let compiled = DesktopNetworkRules.compile(domains: list.plainDomains, lines: list.networkRules)
        #expect(compiled.count == 4)
        let rule = try #require(compiled.first { $0.condition.urlFilter == "||cdn.example/ad/*" })
        #expect(rule.condition.resourceTypes == ["script"])
        #expect(rule.condition.domainType == "thirdParty")
        #expect(rule.condition.initiatorDomains == ["reader.example"])
        #expect(rule.condition.excludedInitiatorDomains == ["pay.reader.example"])
        let exception = try #require(compiled.first { $0.action.type == "allow" })
        #expect(exception.priority > rule.priority)
        #expect(exception.condition.urlFilter == "||cdn.example/ad/consent.js")
        #expect(compiled.contains { $0.action.type == "allowAllRequests" })
        let old = try #require(CachedBlocklist(text: "# url: abc\n# fetched: 2026-01-01T00:00:00Z\nold.example\n"))
        #expect(!old.hasNetworkSource && old.domains == ["old.example"])
        #expect(DesktopNetworkRules.compile(domains: [], lines: ["||bad.example^", "||bad.example^$badfilter"]).isEmpty)
    }

    @Test func unsupportedDomainAnchorDoesNotInvalidateTheRestOfASubscription() {
        let lines = ["||*cdn.example/ads/*.gif$image", "@@||*cdn.example/ads/*.gif$image", "||cdn.example/ads/*$image"]
        let list = DesktopHidingRules.read(lines.joined(separator: "\n"), address: "https://example.com/list", fetched: .now)
        #expect(list.networkRules == [lines[2]])
        // An existing cache can still contain the unsupported filters after an upgrade.
        let compiled = DesktopNetworkRules.compile(domains: [], lines: lines)
        #expect(compiled.map(\.condition.urlFilter) == ["||cdn.example/ads/*"])
    }

    @Test func subscriptionCanHideAnAdContainerByItsContents() {
        let selector = #"section aside[class^="sc-"]:has(> div[class^="sc-"]:not([id]) > div[class^="sc-"]:not([id]) > div[data-ad-unit-id])"#
        let rule = "20min.ch##" + selector
        let list = DesktopHidingRules.read([rule, "reader.20min.ch#@#" + selector,
            rule + "{color:red}", rule + ":style(color:red)", rule + "("].joined(separator: "\n"), address: "", fetched: .now)
        // The `:style()` rule is kept for the procedural runner since #845; from a list Cra doesn't trust it doesn't run.
        #expect(list.hidingRules.count == 3)
        let hiding = DesktopHidingRules(lines: list.hidingRules)
        #expect(hiding.css(host: "www.20min.ch") == selector + "{display:none!important}")
        #expect(hiding.css(host: "reader.20min.ch").isEmpty)
        #expect(hiding.css(host: "other.ch").isEmpty)
        // Copies written by older Cra say an older format (1 up to 0.1.58, 3 until scriptlets came, #845): they
        // read as having no network source, so the next launch fetches them again and newly kept rules arrive.
        #expect(list.text.contains("# network-format: 4"))
        let previous = list.text.replacingOccurrences(of: "# network-format: 4", with: "# network-format: 3")
        #expect(CachedBlocklist(text: previous)?.hasNetworkSource == false)
    }

    @Test func attributeExclusionsReplaceGenericSlotRuleAndRespectHostExceptions() {
        let slot = #"[id^="div-gpt-ad"]"#
        let refined = slot + #":not([style^="width: 1px; height: 1px; position: absolute; left: -10000px; top: -"]):not([style="pointer-events: none; height: 1px; width: 0px; opacity: 0; visibility: hidden; position: fixed; bottom: 0px;"])"#
        let lines = ["##" + slot, "#@#" + slot, "~except.example##" + refined,
                     "other.example#@#" + refined, "##" + refined + "{color:red}",
                     "##" + refined + ":style(height:0)", "##" + refined + ","]
        let list = DesktopHidingRules.read(lines.joined(separator: "\n"), address: "", fetched: .now)
        #expect(list.hidingRules == Array(lines.prefix(4)))
        let rules = DesktopHidingRules(lines: list.hidingRules)
        #expect(rules.css(host: "news.example") == refined + "{display:none!important}")
        #expect(rules.css(host: "sub.except.example").isEmpty)
        #expect(rules.css(host: "other.example").isEmpty)
    }

    @Test func compoundClassExceptionsAndEmptySlotsPreserveTheWholeSelector() {
        let refined = ".ad-slot:not(.adsbox):not(.adsbygoogle)"
        let empty = "[data-ad][data-ad-unit]:empty"
        let lines = ["##.ad-slot", "#@#.ad-slot", "##" + refined, "##" + empty,
                     "except.example#@#" + refined, "##.ad-slot:not(.a,.b)", "##:empty"]
        let list = DesktopHidingRules.read(lines.joined(separator: "\n"), address: "", fetched: .now)
        #expect(list.hidingRules == Array(lines.prefix(5)))
        let rules = DesktopHidingRules(lines: list.hidingRules)
        #expect(rules.css(host: "example.org").contains(refined + "{display:none!important}"))
        #expect(rules.css(host: "except.example") == empty + "{display:none!important}")
    }

    @Test func collapsingReservedSpaceRespectsCosmeticExceptions() {
        let rules = DesktopHidingRules(lines: ["##.dfp-slot", "reader.example#@#.dfp-slot", "##.sponsor"])
        #expect(rules.css(host: "news.example").contains(".dfp-slot{min-block-size:0!important"))
        #expect(rules.css(host: "reader.example") == ".sponsor{display:none!important}")
    }

    @Test func hidingAndExceptionsUseDomainBoundaries() {
        let list = DesktopHidingRules.read("""
        ||tracker.example^
        ##.sponsor
        host.example#@#.sponsor
        host.example,~private.host.example###notice
        ##div[id^="ad_"]
        ##+js(script)
        ##.unsafe{color:red}
        """, address: "https://lists.example/list", fetched: Date(timeIntervalSince1970: 10))
        #expect(list.domains == ["tracker.example"])
        // `##+js(script)` is a scriptlet line, kept since #845; Cra implements no "script", so it counts as unused.
        #expect(list.hidingRules.count == 5)
        #expect(list.skippedRules == 1)
        #expect(BlockListCount(list, networkRules: false) == BlockListCount(applied: 5, skipped: 2))
        #expect(CachedBlocklist(text: list.text) == list)
        let hides = DesktopHidingRules(lines: list.hidingRules)
        #expect(hides.css(host: "badhost.example").contains(".sponsor{"))
        #expect(!hides.css(host: "sub.host.example").contains(".sponsor{"))
        #expect(hides.css(host: "sub.host.example").contains("#notice{"))
        #expect(!hides.css(host: "private.host.example").contains("#notice{"))
        #expect(hides.css(host: "host.example").contains("div[id^=\"ad_\"]{"))
        #expect(!hides.css(host: "host.example").contains("color:red"))
    }
}
