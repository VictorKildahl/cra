import Foundation

/// When the iPhone's first page may load (#507): WebKit applies only the rule lists a page has when
/// it starts loading, so the first page waits for Cra's own lists and, when lists were added in
/// Default Site Settings ▸ Block Lists, for their kept copies too. Without that wait a big added list
/// still compiling lets its domains through on the first page. Lists added or fetched later apply
/// from each page's next load and never hold pages back.
public struct MobileBlockerReadiness: Equatable {
    public private(set) var ownListsReady = false
    public private(set) var waitsForAdded = false

    public init() {}

    public var isReady: Bool { ownListsReady && !waitsForAdded }

    /// At launch, with the setting's addresses: pages wait for added lists only when there are some.
    /// Called once; a later call (a list added while Cra runs) changes nothing.
    public mutating func launched(addresses: [String], first: Bool) {
        if first, !addresses.isEmpty { waitsForAdded = true }
    }

    public mutating func ownListsCompiled() { ownListsReady = true }

    /// The added lists' rule lists exist (or there was nothing to compile).
    public mutating func addedListsCompiled() { waitsForAdded = false }
}
