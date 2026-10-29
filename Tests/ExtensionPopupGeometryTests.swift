import AppKit

@main
enum ExtensionPopupGeometryTests {
    static func main() {
        if CommandLine.arguments.contains("--cleanup-expression") {
            print(ExtensionPopupRequest.closeExpression(extensionID: "testextension"))
            return
        }
        let desktop = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = NSPoint(x: 1100, y: 800)
        let initial = ExtensionPopupGeometry.frame(size: NSSize(width: 300, height: 200), anchor: anchor, visibleFrame: desktop)
        let loaded = ExtensionPopupGeometry.frame(size: NSSize(width: 420, height: 500), anchor: anchor, visibleFrame: desktop)
        expect(initial.maxX == anchor.x && loaded.maxX == anchor.x, "loading growth keeps the right edge at the icon")
        expect(initial.maxY == anchor.y && loaded.maxY == anchor.y, "loading growth keeps the top edge below the icon")

        let leftDisplay = NSRect(x: -1920, y: -180, width: 1920, height: 1080)
        let movedAnchor = NSPoint(x: -100, y: 750)
        let moved = ExtensionPopupGeometry.frame(size: NSSize(width: 420, height: 500), anchor: movedAnchor, visibleFrame: leftDisplay)
        expect(moved.maxX == movedAnchor.x && moved.maxY == movedAnchor.y, "negative-coordinate display keeps its own anchor")

        let edge = ExtensionPopupGeometry.frame(size: NSSize(width: 420, height: 500), anchor: NSPoint(x: 100, y: 120), visibleFrame: desktop)
        expect(edge.minX == 4 && edge.minY == 4, "popup near bottom-left stays reachable")
        expect(desktop.contains(edge), "normal-sized edge popup stays inside its display")
        let oversized = ExtensionPopupGeometry.frame(size: NSSize(width: 2000, height: 1200), anchor: anchor, visibleFrame: desktop)
        expect(oversized.minX == 4 && oversized.maxY == desktop.maxY, "oversized popup keeps its top-left reachable")

        let dragged = ExtensionPopupGeometry.frame(size: initial.size, anchor: anchor, offset: NSPoint(x: -50, y: -40), visibleFrame: desktop)
        let reopened = ExtensionPopupGeometry.frame(size: initial.size, anchor: anchor, visibleFrame: desktop)
        expect(dragged.origin != initial.origin && reopened == initial, "a transient drag does not change a fresh opening")
        print("Extension popup geometry: 7 checks passed")

        let request = ExtensionPopupRequest(extensionID: "testextension", popupPath: "popup/index.html", existingTargets: ["existing"])
        let candidate: [String: Any] = ["targetId": "new", "type": "page", "url": "chrome-extension://testextension/popup/index.html#/login"]
        expect(request.matches(candidate), "fragment navigation stays the same popup candidate")
        var existing = candidate
        existing["targetId"] = "existing"
        expect(!request.matches(existing), "an already-open target cannot belong to the new request")
        var other = candidate
        other["url"] = "chrome-extension://otherextension/popup/index.html"
        expect(!request.matches(other), "another extension cannot belong to the request")
        other["url"] = "https://testextension/popup/index.html"
        expect(!request.matches(other), "a web page cannot belong to the request")
        print("Extension popup target matching: 4 checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
