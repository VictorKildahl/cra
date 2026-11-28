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
    public var updatedAt: Date?
    public var revision: String?
    public var details: Details?

    public struct Details: Codable, Equatable {
        public struct Label: Codable, Equatable {
            public var name: String
            public var color: String?
            public init(name: String, color: String? = nil) { self.name = name; self.color = color }
            private enum CodingKeys: String, CodingKey { case name, color }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "Empty label")
                }
                color = try? c.decode(String.self, forKey: .color)
            }
        }
        public struct Tasks: Codable, Equatable {
            public var done: Int
            public var total: Int
            public init(done: Int, total: Int) { self.done = done; self.total = total }
            private enum CodingKeys: String, CodingKey { case done, total }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                done = try c.decode(Int.self, forKey: .done)
                total = try c.decode(Int.self, forKey: .total)
                guard done >= 0, total >= 0, done <= total else {
                    throw DecodingError.dataCorruptedError(forKey: .done, in: c, debugDescription: "Invalid task counts")
                }
            }
        }
        public var draft: Bool?
        public var commentCount: Int?
        public var labels: [Label]?
        public var tasks: Tasks?
        public init(draft: Bool? = nil, commentCount: Int? = nil, labels: [Label]? = nil, tasks: Tasks? = nil) {
            self.draft = draft; self.commentCount = commentCount; self.labels = labels; self.tasks = tasks
        }
        private enum CodingKeys: String, CodingKey { case draft, commentCount, labels, tasks }
        private struct SoftLabel: Decodable {
            var value: Label?
            init(from decoder: Decoder) { value = try? Label(from: decoder) }
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            draft = try? c.decode(Bool.self, forKey: .draft)
            commentCount = (try? c.decode(Int.self, forKey: .commentCount)).flatMap { $0 >= 0 ? $0 : nil }
            labels = (try? c.decode([SoftLabel].self, forKey: .labels))?.compactMap(\.value)
            tasks = try? c.decode(Tasks.self, forKey: .tasks)
        }
    }

    private enum CodingKeys: String, CodingKey { case id, url, title, subtitle, group, createdAt, updatedAt, revision, details }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decode(Date.self, forKey: .updatedAt)
        revision = try? c.decode(String.self, forKey: .revision)
        details = try? c.decode(Details.self, forKey: .details)
    }

    public init(id: String, url: String, title: String, subtitle: String? = nil, group: String? = nil, createdAt: Date? = nil,
                updatedAt: Date? = nil, revision: String? = nil, details: Details? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.details = details
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
