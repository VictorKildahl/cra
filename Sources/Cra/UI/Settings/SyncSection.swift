import AppKit
import SwiftUI

/// Settings ▸ General ▸ Sync: iCloud keeps the sidebar, the settings and the shortcuts the
/// same on the user's Macs (SettingsSyncService); a folder a provider syncs is the other way.
/// Off, the card is one switch and "Use a folder instead…"; on, the state and Stop Syncing.
/// The same bundle backs Export… and Import… for people with one Mac.
struct SyncSection: View {
    @Environment(SettingsSyncService.self) private var sync
    @State private var importing: (URL, SyncBundleSummary)?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .alert("Use the sidebar from your other Mac?", isPresented: Binding(get: { sync.pendingChoice != nil }, set: { _ in })) {
                Button("Use That Sidebar") { sync.useRemote() }
                Button("Replace It with This Mac’s") { sync.useLocal() }
                Button("Cancel", role: .cancel) { sync.disable() }
            } message: {
                if let found = sync.pendingChoice { Text(Self.describe(found) + " Using it replaces this Mac’s sidebar, settings and shortcuts.") }
            }
            .alert("Import these settings?", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
                Button("Import") {
                    if let (url, _) = importing { notice = sync.importBundle(from: url) ? "Settings imported." : "The folder holds no Cra settings." }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let (_, s) = importing { Text(Self.describe(s) + " Importing replaces this Mac’s sidebar, settings and shortcuts.") }
            }
    }

    @ViewBuilder private var content: some View {
        SettingsHeader("Sync")
        SettingsCard {
            SettingsCardRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with iCloud").font(.system(size: 13))
                    Text(sync.iCloudAvailable ? "Uses the iCloud account signed in on this Mac." : iCloudUnavailableReason)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } trailing: {
                // macOS doesn't tell apps which Apple Account is signed in; System Settings shows it.
                Button("iCloud Settings…") { NSWorkspace.shared.open(Self.appleAccountSettings) }
                Toggle("Sync with iCloud", isOn: Binding(get: { sync.location == .iCloud }, set: { on in on ? enableICloud() : sync.disable() }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!sync.iCloudAvailable)
            }
            if case .folder(let path)? = sync.location {
                SettingsCardDivider()
                SettingsCardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync folder").font(.system(size: 13))
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                } trailing: {
                    Button("Stop Syncing") { sync.disable() }
                }
            } else if sync.location == nil {
                SettingsCardDivider()
                SettingsCardRow {
                    Text("Or sync through a folder in Dropbox, OneDrive or a similar service").font(.system(size: 13))
                } trailing: {
                    Button("Use a Folder…") { chooseFolder() }
                }
            }
            if sync.location != nil {
                SettingsCardDivider()
                SettingsCardRow {
                    Text(status).font(.system(size: 13)).foregroundStyle(sync.error == nil ? .secondary : Color.red)
                } trailing: {
                    if !sync.otherDevices.isEmpty {
                        Text("Also on " + sync.otherDevices.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCardDivider()
            SettingsCardRow {
                Text("Settings file").font(.system(size: 13))
            } trailing: {
                Button("Export…") { exportBundle() }
                Button("Import…") { importBundle() }
            }
        }
        SettingsFootnote(notice ?? "Spaces, pinned tabs, favorites, folders, settings and shortcuts sync. Logins, cookies, history and extensions stay on each Mac.")
    }

    static let appleAccountSettings = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!

    private var iCloudUnavailableReason: String {
        FileManager.default.ubiquityIdentityToken == nil
            ? "Sign in to iCloud in System Settings to sync this way."
            : "This build of Cra cannot use iCloud. The signed release can."
    }

    private var status: String {
        if let error = sync.error { return error }
        if sync.awaitingDownload { return "Waiting for iCloud to download your other Mac’s sidebar…" }
        if sync.pendingChoice != nil { return "Waiting for your choice" }
        guard let date = sync.lastSync else { return "Not synced yet" }
        return "Synced " + Self.relative.localizedString(for: date, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func describe(_ s: SyncBundleSummary) -> String {
        let when = s.writtenAt.formatted(date: .abbreviated, time: .shortened)
        return "\(s.device) saved \(s.spaces) \(s.spaces == 1 ? "space" : "spaces") and \(s.tabs) \(s.tabs == 1 ? "tab" : "tabs") on \(when)."
    }

    private func enableICloud() {
        notice = nil
        if case .failed(let reason) = sync.enableICloud() { notice = reason }
    }

    private func folderPanel(prompt: String, message: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel
    }

    private func chooseFolder() {
        let panel = folderPanel(prompt: "Sync Here", message: "Choose a folder your Macs share, in Dropbox, OneDrive or a similar service. Cra keeps its files in a “Cra” folder inside it.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notice = nil
        if case .failed(let reason) = sync.enable(folder: url) { notice = reason }
    }

    private func exportBundle() {
        let panel = folderPanel(prompt: "Export", message: "Choose where to save a “Cra” folder with your sidebar, settings and shortcuts.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notice = sync.export(to: url).map { "Not exported: \($0)" } ?? "Exported to \((url.path as NSString).abbreviatingWithTildeInPath)/Cra."
    }

    private func importBundle() {
        let panel = folderPanel(prompt: "Import", message: "Choose the folder that holds the exported “Cra” folder, or that folder itself.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let summary = sync.summary(ofBundleIn: url) { importing = (url, summary) } else { notice = "The folder holds no Cra settings." }
    }
}
