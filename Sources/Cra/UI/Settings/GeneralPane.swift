import SwiftUI

/// System integration (Dia asks for these in onboarding and shows the default-browser prompt at
/// the top of its Account pane): default browser, Dock, login, each with what it does under its
/// name; then Sync and App Icon.
struct GeneralPane: View {
    private let system = SystemIntegration.shared

    var body: some View {
        SettingsCardPane {
            SettingsHeader("System")
            SettingsFeatureCard {
                SettingsPlainRow("Default browser",
                                   detail: system.isDefaultBrowser
                                       ? "Links you click in other apps open in Cra."
                                       : "Links you click in other apps open in \(system.defaultBrowserName ?? "another browser"). Cra works best as your default browser.",
                                   trailing: {
                    if system.isDefaultBrowser {
                        Label("Default", systemImage: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        Button(system.isPromptingDefault ? "Confirm in the Dialog…" : "Make Default") {
                            Task { await system.makeDefaultBrowser() }
                        }
                        .disabled(system.isPromptingDefault)
                    }
                })
                SettingsCardDivider()
                SettingsPlainRow("Dock",
                                   detail: system.isInDock ? "Cra is in the Dock." : "Keep Cra in the Dock to open it with one click.",
                                   trailing: {
                    if system.isInDock {
                        Label("In the Dock", systemImage: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        Button("Add to Dock") { if !system.addToDock() { error = "Cra could not be added to the Dock." } }
                    }
                })
                SettingsCardDivider()
                SettingsToggleRow("Open Cra at login",
                                  detail: "Cra opens by itself when you log in to your Mac.",
                                  isOn: Binding(get: { system.launchesAtLogin }, set: { error = system.setLaunchAtLogin($0) }))
            }
            if let error { SettingsFootnote(error).foregroundStyle(.red) }
            SyncSection().padding(.top, 20)
            AppIconSection().padding(.top, 20)
        }
        .onAppear { system.refresh() }
    }

    @State private var error: String?
}
