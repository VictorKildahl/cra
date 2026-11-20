import AppKit

/// The kind of Space a window is on, read from the WindowServer (private `CGSCopySpacesForWindows` and
/// `CGSSpaceGetType`): `isOnActiveSpace` only says whether it is the one in front. Unknown if the API is gone.
@MainActor
enum WindowSpaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }   // RTLD_DEFAULT
    }
    private static let connection = symbol("CGSMainConnectionID", as: MainConnection.self)
    private static let spacesForWindows = symbol("CGSCopySpacesForWindows", as: SpacesForWindows.self)
    private static let spaceType = symbol("CGSSpaceGetType", as: SpaceType.self)

    static func space(of window: NSWindow) -> LittleWindowActivation.Space {
        guard let connection, let spacesForWindows, let spaceType, window.windowNumber > 0,
              let list = spacesForWindows(connection(), 7, [window.windowNumber] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return .unknown }
        let cid = connection()
        return LittleWindowActivation.space(types: list.map { spaceType(cid, $0.uint64Value) })
    }
}
