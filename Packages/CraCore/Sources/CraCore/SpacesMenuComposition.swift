import Foundation

/// The menu bar's list of Spaces. A row targets a Space by identity even though the customizable
/// shortcuts remain positional: Cra defines actions only for positions 1 through 9.
public struct SpacesMenuComposition: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let spaceID: UUID
        public let position: Int
        public let shortcutID: String?
    }

    public let navigation: [Row]

    public init(spaceIDs: [UUID]) {
        navigation = spaceIDs.enumerated().map { offset, spaceID in
            let position = offset + 1
            return Row(spaceID: spaceID, position: position,
                       shortcutID: position <= 9 ? "space" + String(position) : nil)
        }
    }
}
