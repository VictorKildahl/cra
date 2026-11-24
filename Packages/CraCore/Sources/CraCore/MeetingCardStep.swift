/// Live Calendar's Join card: what one Calendar favorite's tile does with it at a tick.
///
/// Every tile of a Calendar favorite reads its own profile's events and reports at each 30 s
/// tick, and there is one card. A space in another profile (its column kept beside the one on
/// screen) or a second window had no call on. It closed the card the first tile had just put up,
/// so every tick put the card up and took it down again within 0.3 s, and Cra's browser window
/// came over the app in use each time (#758). Now only a tile on screen puts the card up, and only
/// the tile that put it up changes or closes it, until that tile leaves the screen.
public enum MeetingCardStep: Equatable, Sendable {
    /// Nothing changes.
    case leave
    /// A new card beside this tile, which owns it from now on (any other card closes first).
    case show
    /// This tile's card shows the meeting again (its time line moves on).
    case update
    case close

    /// `shown`: the meeting on the card (CalendarPreview.key), nil with no card. `ownerIsCaller`:
    /// this tile put it up. `ownerOnScreen`: the tile that put it up is still on screen.
    /// `callerOnScreen`: this tile is in a visible window's current space. `meeting`: the meeting
    /// to join this tile's events give, nil for none.
    public static func next(shown: String?, ownerIsCaller: Bool, ownerOnScreen: Bool, callerOnScreen: Bool,
                            meeting: String?) -> MeetingCardStep {
        // Another tile's card, beside a tile still on screen: not this tile's to change.
        if shown != nil, !ownerIsCaller, ownerOnScreen { return .leave }
        guard callerOnScreen else { return shown == nil ? .leave : .close }
        guard let meeting else { return shown == nil ? .leave : .close }
        return shown == meeting && ownerIsCaller ? .update : .show
    }
}
