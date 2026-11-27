import CraCore
import SwiftUI

/// Settings ▸ Extensions ▸ Share across Profiles… (discussion #595's follow-up, Anoninz): the extension set up in one
/// profile goes into the profiles checked here, which use that profile's settings and sign-in for it. Its own profile
/// is always checked; Select All checks every other one. Profiles made later aren't added on their own.
struct ShareAcrossProfilesSheet: View {
    let entry: ExtensionStore.Entry
    let home: String
    let profiles: [(folder: String, name: String)]
    /// The picked profiles (home among them), or nil for Cancel.
    let done: ([String]?) -> Void

    @State private var picked: Set<String> = []

    private var ordered: [(folder: String, name: String)] {
        ExtensionsLayout.shareChecklist(home: home, allProfiles: profiles.map(\.folder))
            .compactMap { folder in profiles.first { $0.folder == folder } }
    }

    private var others: [String] { profiles.map(\.folder).filter { $0 != home } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share “\(entry.name)” across Profiles").font(.headline)
            Text("The profiles you check use \(name(home))’s settings and sign-in for it, and Cra installs it from the Chrome Web Store "
                 + "where it’s missing. Websites’ cookies and logins stay each profile’s own.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ordered, id: \.folder) { p in
                    Toggle(isOn: Binding(get: { p.folder == home || picked.contains(p.folder) },
                                         set: { on in if on { picked.insert(p.folder) } else { picked.remove(p.folder) } })) {
                        Text(p.folder == home ? "\(p.name) (set up here)" : p.name)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(p.folder == home)
                }
            }
            HStack {
                Button(picked.isSuperset(of: others) ? "Select None" : "Select All") {
                    picked = picked.isSuperset(of: others) ? [] : Set(others)
                }
                .disabled(others.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Share") { done(ordered.map(\.folder).filter { $0 == home || picked.contains($0) }) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            // Profiles that have it already start checked: sharing them is the usual reason to be here.
            picked = Set(others.filter { entry.profiles?.contains($0) == true })
        }
    }

    private func name(_ folder: String) -> String { profiles.first { $0.folder == folder }?.name ?? folder }
}
