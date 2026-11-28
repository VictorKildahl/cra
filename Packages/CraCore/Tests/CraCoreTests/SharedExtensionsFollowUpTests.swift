import CraCore
import Foundation
import Testing

/// Discussion #595's follow-up (Anoninz, after 0.1.58): sharing is opt-in per profile and shares the extension's own
/// data from the profile it was set up in, Settings lists shared extensions apart from each profile's own, Stop
/// Sharing waits until one profile is left, and a shared extension has one on/off switch.
struct SharedExtensionsFollowUpTests {
    let translate = "bpoadfkcbjbfhfodiogcnhhhpibjhbnh"
    let bitwarden = "nngceckbapebfimnlniiiahkandclblb"
    let all = ["Default", "Profile W", "Profile H"]
    let names = ["Default": "Personal", "Profile W": "Work", "Profile H": "Hobbies"]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func sharingIsOptInFromTheProfileItWasSetUpIn() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: ["Default"])
        #expect(shares.profiles(of: translate, allProfiles: all) == ["Default", "Profile W"], "home is always in")
        #expect(shares.home(of: translate) == "Profile W")
        #expect(shares.plan(profile: "Profile H", installed: []).isEmpty, "Hobbies wasn't picked")
        #expect(shares.plan(profile: "Default", installed: []) == .init(install: [translate]))
        #expect(!shares.profiles(of: translate, allProfiles: all + ["Profile New"]).contains("Profile New"),
                "a profile made later doesn't get it unless picked")
        #expect(shares.managedIDs(allProfiles: all) == ["Default": [translate], "Profile W": [translate]])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func everyIncludedProfileUsesTheHomesData() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: ["Default", "Profile W"])
        shares.share(bitwarden)
        let homes = shares.storageHomes(allProfiles: all)
        #expect(homes[translate]?.home == "Profile W")
        #expect(homes[translate]?.profiles == ["Default", "Profile W"])
        #expect(homes[bitwarden] == nil, "a share from before keeps each profile's own data")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func aProfileWithItsOwnInstallIsAskedAboutFirst() {
        #expect(SharedExtensions.replacedInstalls(home: "Profile W", profiles: all, installedIn: ["Profile W", "Profile H"])
                == ["Profile H"])
        #expect(SharedExtensions.replacedInstalls(home: "Profile W", profiles: ["Profile W", "Default"], installedIn: ["Profile W"]).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func theHomeStaysWhileOthersUseItsData() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: all)
        #expect(!shares.canExclude(translate, profile: "Profile W", allProfiles: all), "the data lives there")
        #expect(shares.canExclude(translate, profile: "Default", allProfiles: all))
        shares.setIncluded(translate, profile: "Default", false)
        #expect(shares.profiles(of: translate, allProfiles: all) == ["Profile W", "Profile H"])
        #expect(shares.plan(profile: "Default", installed: [translate]) == .init(uninstall: [translate]))
        shares.setIncluded(translate, profile: "Default", true)
        #expect(shares.profiles(of: translate, allProfiles: all) == all)
        #expect(shares.plan(profile: "Default", installed: [translate]).isEmpty, "put back: nothing owed")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func stopSharingWaitsUntilOneProfileIsLeft() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: all)
        #expect(!shares.canStopSharing(translate, allProfiles: all))
        shares.setIncluded(translate, profile: "Default", false)
        shares.setIncluded(translate, profile: "Profile H", false)
        #expect(shares.canStopSharing(translate, allProfiles: all), "only Work left: it keeps its own data")
        shares.stopSharing(translate)
        #expect(!shares.isShared(translate))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func oneSwitchForEveryProfile() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: all)
        // Turned off in Work's chrome://extensions: off everywhere.
        var result = shares.followSwitch(translate, offIn: ["Profile W"], changed: ["Profile W"], loaded: all, allProfiles: all)
        #expect(!result.on && result.apply == ["Default": false, "Profile H": false])
        #expect(!shares.isOn(translate))
        // All off now: nothing to do.
        result = shares.followSwitch(translate, offIn: Set(all), loaded: all, allProfiles: all)
        #expect(!result.on && result.apply.isEmpty)
        // A profile that has just loaded has it on, as Chrome starts it: it follows, nothing is turned on.
        result = shares.followSwitch(translate, offIn: ["Default", "Profile W"], loaded: all, allProfiles: all)
        #expect(!result.on && result.apply == ["Profile H": false])
        // Turned on again in Hobbies' chrome://extensions: on everywhere.
        result = shares.followSwitch(translate, offIn: ["Default", "Profile W"], changed: ["Profile H"], loaded: all, allProfiles: all)
        #expect(result.on && result.apply == ["Default": true, "Profile W": true])
        // A profile that hasn't loaded isn't touched; it follows when it loads.
        _ = shares.setOn(translate, false)
        result = shares.followSwitch(translate, offIn: [], loaded: ["Default"], allProfiles: all)
        #expect(!result.on && result.apply == ["Default": false])
        _ = shares.setOn(translate, true)
        // Settings' switch.
        let turnedOff = shares.setOn(translate, false)
        #expect(turnedOff)
        let again = shares.setOn(translate, false)
        #expect(!again, "no change")
        // Not shared: each profile's own switch.
        #expect(shares.followSwitch(bitwarden, offIn: ["Default"], loaded: all, allProfiles: all).apply.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func settingsListsSharedThenEachProfilesOwn() {
        var shares = SharedExtensions()
        shares.share(translate, from: "Profile W", with: all)
        let items = [
            ExtensionsLayout.Item(id: translate, name: "Immersive Translate", installedByChrome: true, profiles: Set(all)),
            // A password manager installed separately in Personal and Work: a row in each.
            ExtensionsLayout.Item(id: bitwarden, name: "Bitwarden", installedByChrome: true, profiles: ["Default", "Profile W"]),
            ExtensionsLayout.Item(id: "folder", name: "My unpacked", installedByChrome: false, profiles: nil),
        ]
        let sections = ExtensionsLayout.sections(items: items, shares: shares, allProfiles: all, names: names)
        #expect(sections.map(\.title) == ["Shared across Profiles", "Personal", "Work", "Added to Cra"], "Hobbies has none of its own")
        #expect(sections[0].rows == [.init(id: translate, profile: nil)])
        #expect(sections[1].rows == [.init(id: bitwarden, profile: "Default")])
        #expect(sections[2].rows == [.init(id: bitwarden, profile: "Profile W")])
        #expect(sections[3].kind == .craCopies)
        #expect(ExtensionsLayout.homeLine(translate, shares: shares, names: names) == "Settings and sign-in from Work")
        #expect(ExtensionsLayout.homeLine(bitwarden, shares: shares, names: names) == nil)
        #expect(ExtensionsLayout.shareChecklist(home: "Profile W", allProfiles: all) == ["Profile W", "Default", "Profile H"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595")) func aShareFromBeforeKeepsItsShape() throws {
        var shares = SharedExtensions()
        shares.share(bitwarden)
        shares.setIncluded(bitwarden, profile: "Profile H", false)
        let json = String(decoding: try JSONEncoder().encode(shares), as: UTF8.self)
        #expect(json.contains(#""excluded":["Profile H"]"#) && !json.contains("included") && !json.contains("home"))
    }
}
