import Foundation

/// Where an address entered in ⌘T opens, worked out before it opens: the tab in front (⌘L, an empty split pane), the
/// space an Air Traffic Control route sends it to (#421), or a new tab in the space in use. The address counts for
/// typed completion (#667) in the profile of the space it opens in. Counting it in the typing space's profile, as
/// Cra did, made a profile complete an address Air Traffic Control had sent to another profile, which Arc doesn't
/// (#864).
public enum TypedDestination: Equatable, Sendable {
    case selectedTab
    case routed(space: UUID)
    case newTab

    /// `loadsInSelectedTab`: ⌘L or an empty pane, and the tab may take another host. `route`: the space a route
    /// sends the address to, if it is another space that exists and the window isn't standalone.
    public static func of(loadsInSelectedTab: Bool, route: UUID?, focused: UUID) -> TypedDestination {
        if loadsInSelectedTab { return .selectedTab }
        if let route, route != focused { return .routed(space: route) }
        return .newTab
    }

    /// The space whose profile the typed address counts in.
    public func space(focused: UUID) -> UUID {
        if case .routed(let space) = self { return space }
        return focused
    }
}
