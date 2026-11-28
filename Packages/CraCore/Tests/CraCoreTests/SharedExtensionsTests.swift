import CraCore
import Foundation
import Testing

/// Shared extensions: a Web Store extension in every profile, managed from Cra's Settings (GitHub discussion #595).
struct SharedExtensionsTests {
    let ublock = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    let bitwarden = "nngceckbapebfimnlniiiahkandclblb"
    let all = ["Default", "Profile W", "Profile H"]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func sharingInstallsInEveryProfileThatLacksIt() {
        var shares = SharedExtensions()
        let changed1 = shares.share(ublock)
        #expect(changed1)
        #expect(shares.profiles(of: ublock, allProfiles: all) == all)
        #expect(shares.plan(profile: "Default", installed: [ublock]).isEmpty, "already there: nothing to do")
        #expect(shares.plan(profile: "Profile W", installed: [bitwarden]) == .init(install: [ublock]))
        #expect(SharedExtensions().plan(profile: "Profile W", installed: []).isEmpty, "nothing shared, nothing installed")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func profilesMadeLaterGetSharedExtensions() {
        var shares = SharedExtensions()
        shares.share(ublock)
        let later = all + ["Profile New"]
        #expect(shares.profiles(of: ublock, allProfiles: later).contains("Profile New"))
        #expect(shares.plan(profile: "Profile New", installed: []) == .init(install: [ublock]))
        #expect(shares.managedIDs(allProfiles: later)["Profile New"] == [ublock])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func takingAProfileOutUninstallsItThereOnce() {
        var shares = SharedExtensions()
        shares.share(ublock)
        let changed2 = shares.setIncluded(ublock, profile: "Profile H", false)
        #expect(changed2)
        #expect(shares.profiles(of: ublock, allProfiles: all) == ["Default", "Profile W"])
        #expect(shares.managedIDs(allProfiles: all)["Profile H"] == nil, "Chrome no longer keeps it there")
        #expect(shares.plan(profile: "Profile H", installed: [ublock]) == .init(uninstall: [ublock]))
        // Removed: the owed uninstall is done, and an install the person makes there later stays.
        let changed3 = shares.settle(profile: "Profile H", installed: [])
        #expect(changed3)
        #expect(shares.removals.isEmpty)
        #expect(shares.plan(profile: "Profile H", installed: [ublock]).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func puttingAProfileBackCancelsItsUninstall() {
        var shares = SharedExtensions()
        shares.share(ublock)
        shares.setIncluded(ublock, profile: "Profile H", false)
        let changed4 = shares.setIncluded(ublock, profile: "Profile H", true)
        #expect(changed4)
        #expect(shares.removals.isEmpty)
        #expect(shares.shared[ublock]?.excluded == [])
        #expect(shares.plan(profile: "Profile H", installed: [ublock]).isEmpty)
        #expect(shares.plan(profile: "Profile H", installed: []) == .init(install: [ublock]))
        let changed5 = shares.setIncluded(bitwarden, profile: "Profile H", true)
        #expect(!changed5, "not shared: nothing to put back")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func theLastProfileCannotBeTakenOut() {
        var shares = SharedExtensions()
        shares.share(ublock)
        shares.setIncluded(ublock, profile: "Profile W", false)
        #expect(shares.canExclude(ublock, profile: "Default", allProfiles: all))
        shares.setIncluded(ublock, profile: "Profile H", false)
        #expect(!shares.canExclude(ublock, profile: "Default", allProfiles: all), "that is Remove")
        #expect(!shares.canExclude(ublock, profile: "Profile W", allProfiles: all), "already out")
        #expect(!shares.canExclude(bitwarden, profile: "Default", allProfiles: all))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func removingASharedExtensionRemovesItFromEveryProfile() {
        var shares = SharedExtensions()
        shares.share(ublock)
        shares.share(bitwarden)
        shares.removeEverywhere(ublock, allProfiles: all)
        #expect(!shares.isShared(ublock))
        #expect(shares.managedIDs(allProfiles: all) == ["Default": [bitwarden], "Profile W": [bitwarden], "Profile H": [bitwarden]])
        for profile in all {
            #expect(shares.plan(profile: profile, installed: [ublock, bitwarden]) == .init(uninstall: [ublock]))
        }
        // A profile that never had it owes nothing once it loads.
        shares.settle(profile: "Profile H", installed: [bitwarden])
        #expect(shares.removals["Profile H"] == nil)
        #expect(shares.removals["Default"] == [ublock])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func stoppingSharingLeavesEveryInstallAlone() {
        var shares = SharedExtensions()
        shares.share(ublock)
        let changed6 = shares.stopSharing(ublock)
        #expect(changed6)
        let changed7 = shares.stopSharing(ublock)
        #expect(!changed7)
        #expect(shares.managedIDs(allProfiles: all).isEmpty, "chrome://extensions manages each install again")
        #expect(shares.plan(profile: "Profile W", installed: []).isEmpty, "not installed where it was missing")
        #expect(shares.plan(profile: "Default", installed: [ublock]).isEmpty, "not removed where it is")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func sharingAgainPutsItBackEverywhere() {
        var shares = SharedExtensions()
        shares.share(ublock)
        shares.setIncluded(ublock, profile: "Profile W", false)
        shares.share(ublock)
        #expect(shares.profiles(of: ublock, allProfiles: all) == all)
        #expect(shares.removals.isEmpty, "the owed uninstall is cancelled")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func theStoreIsNotAskedAgainWhereItRefused() {
        var shares = SharedExtensions()
        shares.share(ublock)
        var refused = WebStoreRefusals()
        refused.refuse(folder: ublock, inProfile: "Profile W")
        #expect(shares.plan(profile: "Profile W", installed: [], refused: refused).isEmpty)
        #expect(shares.plan(profile: "Profile H", installed: [], refused: refused) == .init(install: [ublock]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/842"))
    func removeOpensTheProfileThatHasIt() {
        // Chrome uninstalls a profile's own install from that profile's chrome://extensions only, so Remove… opens
        // the page there, never in the space Settings was opened from.
        #expect(ExtensionRemoval.pageProfiles(installedIn: ["Profile W"], allProfiles: all) == ["Profile W"],
                "only in Work: Work's page, also when Settings was opened from a Personal space")
        #expect(ExtensionRemoval.pageProfiles(installedIn: ["Profile H", "Default"], allProfiles: all) == ["Default", "Profile H"],
                "installed separately in two: both, in Settings' profile order, so Remove… asks which")
        #expect(ExtensionRemoval.pageProfiles(installedIn: ["Profile Gone", "Profile W"], allProfiles: all) == ["Profile W"],
                "a deleted profile's folder has no page to open")
        #expect(ExtensionRemoval.pageProfiles(installedIn: nil, allProfiles: all) == all, "loads everywhere")
        #expect(ExtensionRemoval.pageProfiles(installedIn: [], allProfiles: all).isEmpty)
    }

    @Test(.bug(id: "crash-extension-remove-other-profile"))
    func removeUninstallsFromTheMenusProfile() {
        // A pinned extension's Remove acts on the profile its menu is for. It acted on the window's current page,
        // and when that page's profile didn't have the extension Chrome's uninstall CHECKed and Cra crashed.
        #expect(ExtensionRemoval.engineProfile(menuProfile: "Profile H", installedIn: ["Profile H"]) == "Profile H",
                "Hobbies' toolbar, also while the window in front shows a page on Default")
        #expect(ExtensionRemoval.engineProfile(menuProfile: "Default", installedIn: ["Profile H"]) == nil,
                "a profile without it: nothing to ask Chrome")
        #expect(ExtensionRemoval.engineProfile(menuProfile: "Default", installedIn: []) == nil)
        #expect(ExtensionRemoval.engineProfile(menuProfile: "Profile W", installedIn: nil) == "Profile W",
                "a folder of Cra's that loads everywhere")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func settingsSaysWhichProfilesHaveIt() {
        let names = ["Default": "Personal", "Profile W": "Work", "Profile H": "Hobbies"]
        var shares = SharedExtensions()
        #expect(shares.profilesLine(id: bitwarden, installedIn: ["Profile W"], allProfiles: all, names: names) == "In Work")
        #expect(shares.profilesLine(id: bitwarden, installedIn: ["Default", "Profile H"], allProfiles: all, names: names)
                == "In Personal and Hobbies", "in Settings' profile order")
        #expect(shares.profilesLine(id: bitwarden, installedIn: Set(all), allProfiles: all, names: names) == "In every profile")
        #expect(shares.profilesLine(id: "folder", installedIn: nil, allProfiles: all, names: names) == "In every profile",
                "a folder of Cra's that loads everywhere")
        #expect(shares.profilesLine(id: bitwarden, installedIn: ["Default"], allProfiles: ["Default"], names: names) == "In Personal",
                "one profile is named, not 'every'")
        shares.share(ublock)
        #expect(shares.profilesLine(id: ublock, installedIn: Set(all), allProfiles: all, names: names) == "Shared with every profile")
        #expect(shares.profilesLine(id: ublock, installedIn: ["Default"], allProfiles: all, names: names)
                == "Shared with every profile · Work and Hobbies get it when one of their spaces opens")
        shares.setIncluded(ublock, profile: "Profile W", false)
        #expect(shares.profilesLine(id: ublock, installedIn: ["Default"], allProfiles: all, names: names)
                == "Shared with Personal and Hobbies · Hobbies gets it when one of its spaces opens")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func removeSaysWhereItGoes() {
        #expect(ExtensionRemoval.message(isShared: true, isCraCopy: false, profileCount: 3).contains("every profile"))
        #expect(ExtensionRemoval.message(isShared: false, isCraCopy: false, profileCount: 2) == "It will be removed from this profile, with its data.",
                "Chromium uninstalls a profile's own install from that profile only")
        #expect(ExtensionRemoval.message(isShared: false, isCraCopy: true, profileCount: nil) == "It will be removed from every profile that has it.",
                "Cra deletes its own copy for every profile that loads it")
        #expect(ExtensionRemoval.message(isShared: false, isCraCopy: true, profileCount: 1) == "It will be removed from this profile, with its data.")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/595"))
    func savesWithoutAnEmptyRemovalList() throws {
        var shares = SharedExtensions()
        shares.share(ublock)
        let json = String(decoding: try JSONEncoder().encode(shares), as: UTF8.self)
        #expect(!json.contains("removals"))
        #expect(try JSONDecoder().decode(SharedExtensions.self, from: Data(json.utf8)) == shares)
        #expect(try JSONDecoder().decode(SharedExtensions.self, from: Data("{}".utf8)) == SharedExtensions())
    }
}
