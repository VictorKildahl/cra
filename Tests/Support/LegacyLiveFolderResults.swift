import Foundation

extension SidebarStore {
    /// Arc's "Pull Requests" folder at the top of the space's pinned tabs, open.
    @discardableResult
    func createLiveFolder(_ source: LiveFolderSource, inSpace sid: UUID, serverURL: String? = nil) -> SidebarItem? {
        let server = source == .gitlab ? serverURL.flatMap(GitLabLiveClient.serverURL) : nil
        if source == .gitlab, server == nil { return nil }
        if let existing = liveFolder(source, inSpace: sid, serverURL: server) { return existing }
        guard let space = spaces[sid], !isStandalone(space: sid) else { return nil }
        let title = source == .gitlab ? GitLabLiveClient.folderTitle : "Pull Requests"
        let folder = createFolder(named: title, in: space.pinnedContainerID, index: 0)
        var live = LiveFolderData()
        live.source = source
        live.serverURL = server
        if source == .gitlab { live.filter.attributes = [.authored, .reviewRequests, .assigned] }
        items[folder.id]?.liveFolder = live
        updateLiveFolder(folder.id) { _ in }
        return items[folder.id]
    }


    func applyLiveResults(_ requests: [LivePullRequest], to folderID: UUID, ssoOrganizations: [String], context: LiveRequestContext? = nil) {
        if let context, liveRequestContext(folderID) != context { return }
        guard let live = item(folderID)?.liveFolder else { return }
        if live.plugin == nil {
            updateLiveFolder(folderID) {
                $0.plugin = LiveFolderPluginConfiguration(id: live.source.rawValue,
                    settings: live.serverURL.map { ["server": $0] } ?? [:], filters: [], sessionOrigins: [])
            }
        }
        let groups = (item(folderID)?.liveFolder?.plugin?.snapshot?.items ?? []).compactMap(\.group)
        let preserved = groups.filter { group in ssoOrganizations.contains { group.lowercased().hasPrefix($0.lowercased() + "/") } }
        let items = requests.map { LiveFolderPluginItem(id: $0.url, url: $0.url, title: $0.title, subtitle: $0.author,
                                                       group: $0.repository, createdAt: $0.createdAt) }
        applyPluginResults(.init(items: items, preservedGroups: preserved), to: folderID)
        updateLiveFolder(folderID) { $0.ssoOrganizations = ssoOrganizations }
    }
}
