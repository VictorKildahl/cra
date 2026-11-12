import CraCEF
import SwiftUI

/// Settings ▸ Advanced: Dia's Advanced pane (Automatically update, Address Bar routing, When
/// quitting) plus Arc's Advanced switches (sound effects, theme data, window dragging, Boosts)
/// and Cra's own (page engine, import and export, local agents). None of them changes how Cra
/// looks, so each is a plain row (name, what it does, control); About closes the pane.
struct AdvancedPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = SoftwareUpdater.shared
        let newLittleWindow = KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N"
        SettingsCardPane {
            // Arc's Advanced (Arc 1.172.2, GitHub #372): three cards of switches on coloured tiles, then buttons.
            // Its Shared Quotes switch isn't in Cra (the links it makes are arc.net's).
            SettingsCard {
                SettingsTileRow("Play Cra sound effects", symbol: "speaker.wave.2.fill", tile: .blue, isOn: $store.settings.soundEffects)
                SettingsCardDivider()
                SettingsTileRow("Haptic feedback when reordering tabs", symbol: "hand.tap.fill", tile: .blue, isOn: $store.settings.hapticFeedbackOnReorder)
            }
            SettingsCard {
                SettingsTileRow("When opening Cra, restore windows from previous session", symbol: "macwindow", tile: .green, isOn: $store.settings.restoreWindows)
                SettingsCardDivider()
                SettingsTileRow("Allow window dragging from the top of webpages", symbol: "rectangle.topthird.inset.filled", tile: .green, isOn: $store.settings.pageTopWindowDrag)
                SettingsCardDivider()
                SettingsTileRow("Show full URL when Toolbar is enabled", symbol: "ellipsis.rectangle", tile: .red, isOn: $store.settings.toolbarShowsFullURL)
            }
            .padding(.top, 9)
            SettingsCard {
                SettingsTileRow("Enable Picture in Picture when you leave a video tab", symbol: "play.square", tile: .purple, isOn: $store.settings.autoPictureInPicture)
                SettingsCardDivider()
                SettingsTileRow("Allow websites to get your theme data", symbol: "paintpalette.fill", tile: .purple, isOn: $store.settings.shareThemeWithWebsites)
                SettingsCardDivider()
                SettingsTileRow("Enable Boosts on websites you visit", symbol: "paintbrush.fill", tile: .purple, isOn: $store.settings.boostsEnabled)
            }
            .padding(.top, 9)
            HStack(spacing: 16) {
                Button("More Settings…") { actions.openURL("chrome://settings") }
                ResetTranslatedSitesButton(reset: actions.resetTranslatedSitePrompts)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            SettingsHeader("Cra").padding(.top, 20)
            SettingsFeatureCard {
                // The switch is Arc's General ▸ "Automatically update my Arc".
                SettingsPlainRow("Updates",
                                 detail: "Cra downloads new versions in the background and installs them the next time it opens (General).",
                                 trailing: { EmptyView() }) {
                    HStack(spacing: 8) {
                        Button("Check for Updates…") { updater.checkForUpdates(nil) }
                            .disabled(!updater.isAvailable)
                        Text(updater.lastCheckSummary).foregroundStyle(.secondary)
                    }
                }
                SettingsCardDivider()
                SettingsToggleRow("Chrome engine for pages",
                                  detail: "Pages run on Chromium, with Chrome extensions and Chrome DevTools. Takes effect when Cra restarts.",
                                  isOn: $store.settings.chromeEngine)
            }

            // The search engine and its suggestions are in Profiles, where Arc has them.
            SettingsHeader("Command bar").padding(.top, 20)
            SettingsFeatureCard {
                // GitHub #307, not in Arc: ⌘T finds tabs in the window's space only.
                SettingsToggleRow("Only this space’s tabs",
                                  detail: "The command bar finds open tabs in the space you’re in, not in all your spaces.",
                                  isOn: $store.settings.commandBarCurrentSpaceOnly)
            }

            SettingsHeader("Opening and quitting").padding(.top, 20)
            SettingsFeatureCard {
                // Not in Arc (X DM 7 Nov 2026): Arc opens on the tab in use last.
                SettingsToggleRow("Start on a new tab",
                                  detail: "When Cra opens, it starts on a new tab instead of the tab you used last.",
                                  isOn: $store.settings.startOnNewTab)
                SettingsCardDivider()
                // GitHub #231, not in Arc: ⌘Q puts Cra in the menu bar instead of quitting.
                SettingsToggleRow("Keep Cra in the menu bar",
                                  detail: "⌘Q closes Cra’s windows and pages but leaves it running in the menu bar, so \(newLittleWindow) opens a Little Window at once. Quit it from the menu bar.",
                                  isOn: $store.settings.keepInMenuBar)
            }

            SettingsHeader("Your data").padding(.top, 20)
            SettingsFeatureCard {
                SettingsPlainRow("Import from another browser",
                                   detail: importDetail,
                                   trailing: { Button("Import…") { actions.importData() } })
                SettingsCardDivider()
                SettingsPlainRow("Export spaces and pinned tabs",
                                   detail: "Save every space’s favorites, pinned tabs and folders as a bookmarks file that Chrome, Safari, Firefox and other browsers can import.",
                                   trailing: { Button("Export…") { SidebarExport.run(store, in: NSApp.keyWindow) } })
            }

            SettingsHeader("Agents").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Allow local agents to control Cra",
                                  detail: "AI agents on this Mac can read pages and act using your signed-in sessions, through MCP.",
                                  isOn: Binding(get: { MCPServer.shared.enabled }, set: { MCPServer.shared.setEnabled($0) })) {
                    Text(MCPServer.shared.status)
                    if MCPServer.shared.enabled {
                        Text("Last tool: \(MCPServer.shared.lastTool.isEmpty ? "None" : MCPServer.shared.lastTool)")
                            .foregroundStyle(.secondary)
                    }
                }
                if MCPServer.shared.enabled {
                    SettingsCardDivider()
                    MCPAgentTiles()
                    SettingsCardDivider()
                    SettingsCardRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let agents run JavaScript in pages").font(.system(size: 13))
                            Text("A script can read anything a page holds, including passwords Cra fills in.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } trailing: {
                        Toggle("Let agents run JavaScript in pages", isOn: Binding(
                            get: { MCPServer.shared.allowsScripts }, set: { MCPServer.shared.allowsScripts = $0 }))
                            .toggleStyle(.arcSwitch).labelsHidden()
                    }
                    SettingsCardDivider()
                    SettingsCardRow {
                        Text("Let agents read your history").font(.system(size: 13))
                    } trailing: {
                        Toggle("Let agents read your history", isOn: Binding(
                            get: { MCPServer.shared.allowsHistory }, set: { MCPServer.shared.allowsHistory = $0 }))
                            .toggleStyle(.arcSwitch).labelsHidden()
                    }
                    ForEach(MCPServer.shared.agents) { agent in
                        SettingsCardDivider()
                        SettingsCardRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.via.isEmpty ? agent.name : "\(agent.name) in \(agent.via)").font(.system(size: 13))
                                Text(agent.allowed ? "Allowed" : "Not allowed").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        } trailing: {
                            Button("Forget") { MCPServer.shared.forget(agent) }
                        }
                    }
                }
            }

            SettingsHeader("About").padding(.top, 20)
            SettingsFeatureCard {
                HStack(spacing: 14) {
                    BrandMark(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cra \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Chromium \(CraCEFRuntime.chromiumVersion()) · CEF \(CraCEFRuntime.cefVersion())")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(AppPaths.supportDir.path).font(.system(size: 11)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }

    private var importDetail: String {
        let names = ImportSource.allCases.filter { $0.kind != .safari && $0.isAvailable }.map(\.name)
        return names.isEmpty
            ? "Bring bookmarks, open tabs, passwords and sign-ins over from Safari."
            : "Bring spaces, tabs, folders, favorites, passwords, sign-ins and extensions over from \(names.joined(separator: ", ")), Safari and more."
    }
}

/// Chromium's default search engine, the one chrome://settings/searchEngines sets (Arc: Settings ▸
/// Profiles ▸ Default Search Engine, beside "Search Settings"): its built-in engines and whichever is
/// the default. The page adds, edits and removes the rest.
struct SearchEnginePicker: View {
    let store: SidebarStore
    @State private var engines: [ChromiumSearchEngine] = []
    @State private var selected = ""

    var body: some View {
        Picker("Search engine", selection: Binding(get: { selected }, set: pick)) {
            ForEach(engines, id: \.keyword) { Text($0.name).tag($0.keyword) }
        }
        .labelsHidden()
        .fixedSize()
        .onAppear(perform: reload)
    }

    private func reload() {
        let current = SearchEngines.shared.defaultEngine(profilePath: nil, legacy: store.settings.searchEngine)
        var list = SearchEngines.shared.keywords(profilePath: nil).filter(\.isBuiltIn)
        if !list.contains(where: { $0.keyword == current.keyword }) { list.insert(current, at: 0) }
        engines = list
        selected = current.keyword
    }

    private func pick(_ keyword: String) {
        guard let engine = engines.first(where: { $0.keyword == keyword }) else { return }
        SearchEngines.shared.setDefault(engine, store: store)
        selected = keyword
    }
}

/// Arc's "Reset Translated-site Prompts", which says nothing when it is done: the label turns to "Done"
/// for two seconds instead.
private struct ResetTranslatedSitesButton: View {
    let reset: () -> Void
    @State private var done = false

    var body: some View {
        Button(done ? "Done" : "Reset Translated-site Prompts") {
            reset()
            done = true
            Task { try? await Task.sleep(for: .seconds(2)); done = false }
        }
        .disabled(done)
    }
}
