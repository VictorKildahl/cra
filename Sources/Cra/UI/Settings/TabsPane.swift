import SwiftUI

/// Settings ▸ Tabs. Dia draws this pane as a two-column form of checkboxes, whose titles didn't
/// say what each one did. Cra gives every setting a line saying what it changes, and the ones
/// that change how Cra looks a picture of it, the way Arc's Max pane draws a feature. The address
/// bar picks between onboarding's two layout pictures. Links have a pane of their own, as in Arc.
struct TabsPane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            // #305: onboarding's "Choose where the address bar goes". Arc keeps it in View ▸ Show Toolbar.
            SettingsHeader("Address bar")
            SettingsFeatureCard {
                HStack(spacing: 12) {
                    ForEach(AddressBarPlacement.allCases, id: \.self) { placement in
                        AddressBarTile(placement: placement, selection: $store.settings.addressBarPlacement)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            SettingsFootnote("\(KeyBindingRegistry.shared.action("toggleToolbar")?.primary?.display ?? "⇧⌘D") in any window, or the View menu’s Show Toolbar, switches it too.")
            SettingsFeatureCard {
                // GitHub #344, not in Arc: Arc's sidebar address opens the command bar on a click.
                SettingsToggleRow("Edit the address in the sidebar",
                                  detail: "Clicking the address at the top of the sidebar lets you edit it right there instead of opening the command bar. \(KeyBindingRegistry.shared.action("editURL")?.primary?.display ?? "⌘L") still opens the command bar.",
                                  isOn: $store.settings.editAddressInPlace,
                                  enabled: store.settings.addressBarPlacement == .sidebar)
            }
            .padding(.top, 12)

            // Settings that change how Cra looks carry a picture of the change.
            SettingsHeader("Sidebar").padding(.top, 20)
            SettingsFeatureCard {
                SettingsSwitchRow("New tabs at the top",
                                  detail: "A new tab goes above your other tabs instead of below them.",
                                  isOn: $store.settings.newTabsAtTop) { SettingsArt.newTabsAtTop }
                SettingsCardDivider()
                SettingsSwitchRow("New Tab button above tabs",
                                  detail: "The + New Tab row sits at the top of the tab list, where you can always reach it.",
                                  isOn: $store.settings.newTabButtonAtTop) { SettingsArt.newTabButtonAtTop }
                SettingsCardDivider()
                SettingsSwitchRow("Folder previews",
                                  detail: "Hover over a closed folder to see the tabs inside it.",
                                  isOn: $store.settings.folderPreviews) { SettingsArt.folderPreviews }
                SettingsCardDivider()
                // Arc: Settings ▸ General ▸ Previews (Gmail's unread mail on its favorite).
                SettingsSwitchRow("Gmail previews",
                                  detail: "Hover over Gmail in your Favorites to see your unread mail.",
                                  isOn: $store.settings.favoritePreviews) { SettingsArt.gmailPreviews }
                SettingsCardDivider()
                SettingsSwitchRow("Colorful favorite outline",
                                  detail: "The open favorite gets a rim in its logo’s colors instead of a plain one.",
                                  isOn: $store.settings.favoriteLogoOutline) { SettingsArt.favoriteLogoOutline }
                SettingsCardDivider()
                // Arc's single-space mode ("Hide Space Header" on the space's menu), for people who
                // don't use spaces.
                SettingsSwitchRow("Space header with one space",
                                  detail: "Show the space’s name at the top and its icon at the bottom of the sidebar, even while you have only one space.",
                                  isOn: $store.settings.showSpaceHeaderOnSingleSpace) { SettingsArt.spaceHeader }
            }

            SettingsHeader("Pages").padding(.top, 20)
            SettingsFeatureCard {
                SettingsSwitchRow("Edge to edge",
                                  detail: "Pages fill the window, with no margin or rounded corners around them.",
                                  isOn: $store.settings.edgeToEdgeContent) { SettingsArt.edgeToEdge }
                SettingsCardDivider()
                SettingsSwitchRow("Automatic Picture in Picture",
                                  detail: "Switch away from a tab playing a video and the video keeps playing in a small floating window. A site you set in its site controls keeps its own choice.",
                                  isOn: $store.settings.autoPictureInPicture) { SettingsArt.autoPictureInPicture }
            }

            SettingsHeader("Tabs and Favorites").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Haptic feedback when reordering",
                                  detail: "The trackpad taps as a dragged tab moves past another one.",
                                  isOn: $store.settings.hapticFeedbackOnReorder)
                SettingsCardDivider()
                // #154: Arc's favorites, one set per profile.
                SettingsToggleRow("Share Favorites across Spaces",
                                  detail: "Spaces on the same profile show the same Favorites, as in Arc. Turning it on combines their Favorites; turning it off gives each Space its own copy.",
                                  isOn: Binding(get: { store.settings.sharedFavorites }, set: { store.setFavoritesShared($0) }))
            }

            SettingsHeader("Tab cleanup").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Archive unused tabs",
                                  detail: "Today tabs you haven’t opened for a while move to the archive. Pinned tabs and Favorites stay.",
                                  isOn: $store.settings.autoArchiveEnabled) {
                    SettingsInlinePicker(label: "After", selection: $store.settings.autoArchive, enabled: store.settings.autoArchiveEnabled) {
                        ForEach(AutoArchiveThreshold.allCases) { Text($0.label).tag($0) }
                    }
                }
                SettingsCardDivider()
                // Tab sleeping (GitHub #153): Arc's 4 hours and nothing more unless you ask.
                SettingsToggleRow("Free memory from unused tabs",
                                  detail: "A tab you haven’t used for a while is forced out of memory and reloads when you open it.",
                                  isOn: $store.settings.tabSleepTimerEnabled) {
                    SettingsInlinePicker(label: "After", selection: $store.settings.tabSleepAfter, enabled: store.settings.tabSleepTimerEnabled) {
                        ForEach(TabSleepThreshold.allCases) { Text($0.label).tag($0) }
                    }
                }
                SettingsCardDivider()
                SettingsToggleRow("Free memory when the Mac runs short",
                                  detail: "While macOS is short of memory, the tabs hidden longest are forced out of it, a few at a time.",
                                  isOn: $store.settings.tabSleepOnMemoryPressure)
            }
            SettingsFootnote(tabSleepNote)
        }
    }

    /// Says which tabs stay in memory, before the user finds out.
    private var tabSleepNote: String {
        let s = store.settings
        let note = "Tabs playing sound, recording or holding text you typed stay in memory."
        guard s.tabSleepTimerEnabled, TabSleepPolicy.timer(s.tabSleepAfter).keepsRecentTabs else { return note }
        return note + (s.tabSleepOnMemoryPressure ? " So do the 10 tabs you used last, unless the Mac is short of memory." : " So do the 10 tabs you used last.")
    }
}

/// One of the two address bar layouts: onboarding's picture (Dia's TabLayout artwork) with a
/// ring when picked, its name and where that puts the address bar underneath.
private struct AddressBarTile: View {
    let placement: AddressBarPlacement
    @Binding var selection: AddressBarPlacement
    @Environment(\.colorScheme) private var scheme

    private static let width: CGFloat = 150

    var body: some View {
        let selected = selection == placement
        let k = Self.width / 230
        VStack(spacing: 4) {
            LayoutArt(toolbar: placement == .toolbar, selected: selected, dark: scheme == .dark)
                .frame(width: 230, height: 180)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: 230 * k, height: 180 * k, alignment: .topLeading)
            Text(placement.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            Text(placement.detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection = placement } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(placement.title): the address bar \(placement.detail.lowercased())")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = placement }
    }
}
