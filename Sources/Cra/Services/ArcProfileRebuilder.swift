import AppKit

/// Settings ▸ Profiles ▸ Rebuild from Arc (GitHub #131). An Arc import from before 0.1.28 left
/// every space on Default. This puts the spaces back on the profiles their Arc spaces are on and
/// brings what those Arc profiles held: sign-ins and passwords, the extensions they had (an
/// imported extension then loads only there) and their pinned extensions. Cra restarts to load
/// them, as after an import.
@MainActor
enum ArcProfileRebuilder {
    /// Shown in Settings only while Arc's sidebar is on this Mac.
    static var isAvailable: Bool { ArcImporter.isAvailable }

    /// Asks, moves the spaces and restarts; says so when there is nothing to do or Arc can't be read.
    static func run(store: SidebarStore, relaunch: @escaping () -> Void) {
        guard let plan = try? ArcImporter.plan() else {
            alert("Cra couldn't read Arc's spaces.", "Arc's sidebar file is missing or in a format this version doesn't know.")
            return
        }
        let moves = store.arcProfileMoves(plan)
        guard !moves.isEmpty else {
            alert("No spaces to move", "Every space named like one of your Arc spaces is already on the right profile, or Arc has it on its Default profile.")
            return
        }
        let a = NSAlert()
        a.messageText = "Move \(moves.count == 1 ? "this space" : "these spaces") to \(moves.count == 1 ? "its" : "their") Arc profile\(moves.count == 1 ? "" : "s")?"
        a.informativeText = moves.map { "\($0.spaceTitle) → \($0.profileName)" }.joined(separator: "\n") + "\n\n"
            + "Cra brings over the sign-ins, passwords and extensions these Arc profiles have, so the spaces work as they did in Arc. "
            + "Sign-ins and passwords you added in Cra since the import stay with Default. macOS asks for your password to unlock Arc's data, then Cra restarts."
        a.addButton(withTitle: "Move and Restart")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let folders = Set(moves.map(\.folder))
        let profiles = ChromiumImporter.profiles(userData: ArcImporter.userData).filter { folders.contains($0.id) }
        Task { @MainActor in
            var credentials = ImportedCredentials()
            if !profiles.isEmpty {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try ChromiumImporter.credentials(browser: "Arc", profiles: profiles, keychainService: "Arc Safe Storage",
                                                              keychainAccount: "Arc", cookies: true, passwords: true) }
                }.value
                switch result {
                case .success(let c): credentials = c
                case .failure(let error):
                    CraLog.note("rebuild from Arc: sign-ins not read: \(error.localizedDescription)")
                    let b = NSAlert()
                    b.messageText = "Move the spaces without their sign-ins?"
                    b.informativeText = "\(error.localizedDescription) The spaces would start signed out of every site. Cancel changes nothing."
                    b.addButton(withTitle: "Move Without Sign-ins")
                    b.addButton(withTitle: "Cancel")
                    guard b.runModal() == .alertFirstButtonReturn else { return }
                }
            }
            let map = store.applyArcProfileMoves(moves)
            CraLog.note("rebuild from Arc: moved \(moves.count) space(s), \(credentials.cookies.count) cookies, \(credentials.logins.count) passwords")
            if !credentials.isEmpty, !(await Task.detached(priority: .userInitiated) { CredentialImport.stage(credentials, profiles: map) }.value) {
                alert("Cra couldn't save Arc's sign-ins.", "The spaces moved, but they start signed out.")
            }
            scopeExtensions(map, store: store)
            seedPins(map)
            relaunch()
        }
    }

    /// Extensions an older import copied in, loading everywhere: from now on only in the profiles
    /// that had them in Arc, and in profiles made in Cra, which keep what they had.
    private static func scopeExtensions(_ map: ImportProfileMap, store: SidebarStore) {
        let all = Set(["Default"] + store.profiles.map(\.directoryName))
        for ext in ExtensionImporter.extensions(inUserData: ArcImporter.userData) where ExtensionStore.isInstalled(id: ext.id) {
            let profiles = map.extensionProfiles(sources: ext.sourceProfiles, allFolders: all, keepUnmapped: true)
            if let profiles { CraLog.note("rebuild from Arc: extension \(ext.id) for \(profiles.sorted().joined(separator: ", "))") }
            ExtensionStore.scopeImported(folder: ext.id, profiles: profiles)
        }
    }

    /// Each moved profile starts with the toolbar pins it has in Arc.
    private static func seedPins(_ map: ImportProfileMap) {
        for (folder, target) in map.folders where target != "Default" {
            guard let ids = ExtensionImporter.pinnedIDs(inProfile: ArcImporter.userData.appendingPathComponent(folder, isDirectory: true)) else { continue }
            ExtensionStore.shared.seedPinned(ids, inProfile: target)
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
