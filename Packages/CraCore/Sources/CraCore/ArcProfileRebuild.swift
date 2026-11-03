import Foundation

/// Settings ▸ Profiles ▸ Rebuild from Arc (GitHub #131): an import from before Cra kept Arc's
/// profiles left every space on Default. This finds the spaces to move back onto the profile
/// their Arc space is on, matched by name, since ids differ between the browsers.
public enum ArcProfileRebuild {
    public struct CraSpace: Equatable, Sendable {
        public var id: UUID
        public var title: String
        /// On Default and not incognito: the only spaces a rebuild moves. One already on a
        /// profile was put there by hand.
        public var movable: Bool

        public init(id: UUID, title: String, movable: Bool) {
            self.id = id
            self.title = title
            self.movable = movable
        }
    }

    public struct ArcSpace: Equatable, Sendable {
        public var title: String
        /// Arc's profile folder ("Profile 2"); nil for Default.
        public var folder: String?
        /// The profile's name in Arc.
        public var name: String

        public init(title: String, folder: String?, name: String) {
            self.title = title
            self.folder = folder
            self.name = name
        }
    }

    public struct Move: Equatable, Sendable {
        public var spaceID: UUID
        public var spaceTitle: String
        public var folder: String
        public var profileName: String
    }

    /// The Cra spaces to put on an Arc profile: a movable space whose name (any case) is one Arc
    /// space's, when that space is on a profile other than Default. A name Arc uses on more than
    /// one profile, or Cra on more than one space, says nothing about which is which: skipped.
    public static func moves(cra: [CraSpace], arc: [ArcSpace]) -> [Move] {
        let arcByTitle = Dictionary(grouping: arc) { $0.title.lowercased() }
        let craCount = Dictionary(grouping: cra) { $0.title.lowercased() }.mapValues(\.count)
        return cra.compactMap { space in
            let key = space.title.lowercased()
            guard space.movable, craCount[key] == 1, let matches = arcByTitle[key],
                  Set(matches.map(\.folder)).count == 1, let match = matches.first, let folder = match.folder else { return nil }
            return Move(spaceID: space.id, spaceTitle: space.title, folder: folder, profileName: match.name)
        }
    }
}
