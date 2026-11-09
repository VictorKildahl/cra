import Foundation

public struct LiveFolderPluginPresentation: Codable, Equatable {
    public struct Filter: Codable, Equatable {
        public var id: String
        public var title: String
        public var enabledByDefault: Bool
    }

    public struct Groups: Codable, Equatable {
        public var title: String
        public var description: String
    }

    public struct Setup: Codable, Equatable {
        public var key: String
        public var title: String
        public var message: String
        public var placeholder: String
        public var defaultValue: String
        public var invalidTitle: String
        public var invalidMessage: String
    }

    public var folderTitle: String
    public var menuTitle: String
    public var icon: String
    public var filters: [Filter]
    public var groups: Groups?
    public var setup: Setup?
    public var statusMessages: [String: String]

    public func validate() throws {
        guard !folderTitle.isEmpty, !menuTitle.isEmpty, !icon.isEmpty,
              Set(filters.map(\.id)).count == filters.count,
              filters.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }) else {
            throw LiveFolderPluginError.invalidManifest("Invalid folder presentation")
        }
    }
}

public struct LiveFolderPluginItem: Codable, Equatable, Identifiable {
    public var id: String
    public var url: String
    public var title: String
    public var subtitle: String?
    public var group: String?
    public var createdAt: Date?

    public init(id: String, url: String, title: String, subtitle: String? = nil, group: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.createdAt = createdAt
    }

    public func validate() throws {
        guard !id.isEmpty, !title.isEmpty, let components = URLComponents(string: url),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else {
            throw LiveFolderPluginError.invalidManifest("Invalid folder item")
        }
    }
}

public struct LiveFolderPluginSnapshot: Codable, Equatable {
    public struct Action: Codable, Equatable {
        public var title: String
        public var url: String

        public init(title: String, url: String) { self.title = title; self.url = url }
    }

    public var items: [LiveFolderPluginItem]
    public var actions: [Action]
    public var actionMessage: String?
    public var warning: String?
    public var preservedGroups: [String]

    public init(items: [LiveFolderPluginItem], actions: [Action] = [], preservedGroups: [String] = []) {
        self.items = items
        self.actions = actions
        self.preservedGroups = preservedGroups
    }

    public func validate() throws {
        guard items.count <= 10_000, actions.count <= 100,
              Set(items.map(\.id)).count == items.count,
              Set(items.map(\.url)).count == items.count else {
            throw LiveFolderPluginError.invalidManifest("Invalid or duplicate folder items")
        }
        for item in items { try item.validate() }
        for action in actions {
            let item = LiveFolderPluginItem(id: action.title, url: action.url, title: action.title)
            try item.validate()
        }
    }
}
