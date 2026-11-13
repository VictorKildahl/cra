import SwiftUI

/// Arc's Links tab (Arc 1.172.2, GitHub #372): a picture band, a line on Little Windows and the switches that open
/// one, a rule, a line on Peek and its switches, a rule, and "Choose where links open" with Air Traffic Control….
/// Cra adds "Peek in every tab" to the Peek card and a last card for what "Open Link in New Tab" does.
struct LinksPane: View {
    @Environment(SidebarStore.self) private var store
    @State private var showsAirTrafficControl = false

    var body: some View {
        @Bindable var store = store
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                LinksHero()
                VStack(alignment: .leading, spacing: 0) {
                    SettingsBlurb("Little Window is a smaller, simpler window. It’s perfect for quick lookups and reading funny tweets your friends send you.")
                        .padding(.top, 20)
                    SettingsCard {
                        // Arc: "Open Little Arc when I press ⌥⌘N in any app" (#195).
                        SettingsSwitchLine("Open Little Window when I press \(shortcut) in any app", isOn: $store.settings.littleWindowShortcutEverywhere)
                        SettingsCardDivider()
                        // Arc: "Open Little Arc when clicking on links with ⌥⌘ held" (#373). Off in Cra: a ⌘⌥-click opens
                        // Split View otherwise (#298).
                        SettingsSwitchLine("Open Little Window when clicking on links with ⌥⌘ held", isOn: $store.settings.littleWindowOnOptionCommandClick) {
                            Text("Off, a ⌥⌘-click opens the link in Split View.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        SettingsCardDivider()
                        SettingsSwitchLine("Links from other apps open in Little Window", isOn: $store.settings.openExternalLinksInLittleWindow)
                        SettingsCardDivider()
                        // Arc: "Archive Little Arcs after:" 1 hour, 6 hours (default), 12 hours.
                        SettingsCardRow { Text("Archive Little Windows after:").font(.system(size: 13)) } trailing: {
                            Picker("Archive Little Windows after", selection: $store.settings.littleWindowArchiveAfter) {
                                ForEach(LittleWindowArchive.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    .padding(.top, 20)

                    SettingsRule().padding(.top, 24)

                    SettingsBlurb("Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet.")
                        .padding(.top, 24)
                    SettingsCard {
                        SettingsSwitchLine("Open a Peek window when clicking on links with Shift held", isOn: $store.settings.peekOnShiftClick)
                        SettingsCardDivider()
                        SettingsSwitchLine("Open a Peek window when clicking on links to other sites", isOn: $store.settings.peekLinksToOtherSites) {
                            Text("Note: This only affects Favorites and Pinned tabs").font(.system(size: 13).italic()).foregroundStyle(.secondary)
                        }
                        SettingsCardDivider()
                        // Cra's addition (#12).
                        SettingsSwitchLine("Peek at links to other sites in every tab", isOn: $store.settings.peekInEveryTab,
                                           enabled: store.settings.peekLinksToOtherSites)
                        SettingsCardDivider()
                        // Not in Arc (GitHub #380): off by default, Expand makes a new tab as in Arc.
                        SettingsSwitchLine("⌘-click Expand opens in the tab", isOn: $store.settings.peekExpandInSourceTab) {
                            Text("Hold ⌘ while you click a Peek’s Expand to open the page in the tab you were peeking from. Back takes that tab to where it was.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 20)

                    SettingsRule().padding(.top, 24)

                    SettingsCard {
                        SettingsCardRow {
                            Text("Choose where links open inside Cra.").font(.system(size: 13))
                                .help(routesDetail)
                        } trailing: {
                            Button("Air Traffic Control…") { showsAirTrafficControl = true }
                        }
                    }
                    .padding(.top, 20)

                    // Not in Arc's tab: what "Open Link in New Tab" does (#276).
                    SettingsHeader("New tabs").padding(.top, 20)
                    SettingsFeatureCard {
                        SettingsToggleRow("Switch to links opened in new tabs",
                                          detail: "“Open Link in New Tab” brings the new tab to the front. Off, the page you’re reading stays in front, as in Arc. ⌘-click opens a link behind the page and ⇧⌘-click switches to it either way.",
                                          isOn: $store.settings.openLinksInForeground)
                    }
                }
                .padding(.horizontal, SettingsMetrics.paneInset)
                .padding(.bottom, SettingsMetrics.paneBottom)
            }
        }
        .scrollIndicators(.automatic)
        .sheet(isPresented: $showsAirTrafficControl) {
            AirTrafficControlView().environment(store)
        }
    }

    private var shortcut: String { KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N" }

    private var routesDetail: String {
        let lead = "Send links from other apps to the space you choose, by what their address contains."
        switch store.settings.linkRoutes.count {
        case 0: return lead
        case 1: return lead + " 1 route set."
        case let n: return lead + " \(n) routes set."
        }
    }
}

/// Arc's Links picture (684 × 135, a rose band with a Little Arc in it, ending in a wavy edge), drawn here with a
/// Little Window of Cra's: its address and the "Open in" button.
private struct LinksHero: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            (scheme == .dark ? Color(.sRGB, red: 0.87, green: 0.49, blue: 0.52) : Color(.sRGB, red: 1, green: 0.63, blue: 0.64))
            // The Little Window: a title bar with its address pill and "Open in" button, cut off by the band's edge.
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.55)).frame(width: 6, height: 6) } }
                    Text("Work").font(.system(size: 6.5)).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.5)))
                    Spacer(minLength: 0)
                    HStack(spacing: 3) { Image(systemName: "lock.fill").font(.system(size: 5)); Text("crabrowser.app").font(.system(size: 7.5)) }
                    Spacer(minLength: 0)
                    Text("Open in Work ⌘O").font(.system(size: 6.5)).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.75)))
                }
                .padding(.horizontal, 8)
                .foregroundStyle(Color.black.opacity(0.55))
                .frame(height: 22)
                Rectangle().fill(Color.white.opacity(0.28)).frame(maxHeight: .infinity)
            }
            .frame(width: 562, height: 88)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.bottom, -8)
        }
        .frame(height: 135)
        .clipShape(SettingsScallopedBand())
        .accessibilityHidden(true)
    }
}
