import AppKit
import SwiftUI

@main
enum DialogTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for style in [DialogButton.Style.primary, .accent, .destructive] {
            let tint = NSColor(style.hoverTint).usingColorSpace(.sRGB)!
            expect(tint.redComponent == 0 && tint.greenComponent == 0 && tint.blueComponent == 0,
                   "primary and destructive buttons darken on hover: \(style)")
        }
        let secondaryHover = NSColor(DialogButton.Style.secondary.hoverTint).usingColorSpace(.sRGB)!
        expect(secondaryHover.redComponent == 1 && secondaryHover.greenComponent == 1 && secondaryHover.blueComponent == 1,
               "secondary buttons brighten on hover")
        if let directory = ProcessInfo.processInfo.environment["CRA_DIALOG_SNAPSHOTS"] { try snapshots(in: directory) }
        checkEaselDeletion()
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        parent.resignKey()
        parent.resignMain()
        expect(NSApp.keyWindow == nil && NSApp.mainWindow == nil, "the background-window check has no key or main window")
        expect(AppDialog.parentWindow === parent, "an inactive app still anchors dialogs to its visible browser window")

        let acknowledgement = AppDialog(title: "You need at least one space.")
        acknowledgement.present(over: parent) { _ in }
        let acknowledgementWindow = sheet(over: parent)
        expect(acknowledgementWindow.isSheet && acknowledgementWindow.sheetParent === parent,
               "dialogs use the same native sheet presentation as the Space editor")
        guard let acknowledgementView = acknowledgementWindow.contentView else { fatalError("Dialog content missing") }
        expect(acknowledgementWindow.hasShadow && acknowledgementWindow.animationBehavior == .default,
               "AppKit owns the sheet's shadow and animations")
        expect(acknowledgementView.bounds.width == 450 && acknowledgementView.bounds.height < 400,
               "the panel fits the card rather than covering the browser window")
        let acknowledgementBitmap = bitmap(of: acknowledgementView)
        let face = acknowledgementBitmap.colorAt(x: 15, y: acknowledgementBitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
        let reference = AppDialog(title: "You need at least one space.").prepareWindow()
        let referenceBitmap = bitmap(of: reference.contentView!)
        let referenceFace = referenceBitmap.colorAt(x: 15, y: referenceBitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
        expect(abs(face.redComponent - referenceFace.redComponent) < 0.025 && abs(face.blueComponent - referenceFace.blueComponent) < 0.025,
               "the parent window's dim must not change the card's colors")
        reference.close()
        let buttonPoint = blueButtonCenter(in: acknowledgementBitmap, view: acknowledgementView)
        let hit = acknowledgementView.hitTest(buttonPoint)
        expect(hit != nil, "the sheet content receives pointer events")
        acknowledgementWindow.close()

        for code: UInt16 in [36, 53, 76] {
            let dialog = AppDialog.easelDeletion()
            var responses: [NSApplication.ModalResponse] = []
            dialog.present(over: parent) { responses.append($0) }
            let window = sheet(over: parent)
            expect(window.sheetParent === parent, "Easel deletion is attached to its source window")
            expect(window.animationBehavior == .default, "Easel deletion keeps native sheet animations")
            expect(window.canBecomeKey, "the dialog can receive keyboard input")
            window.sendEvent(key(code, window: window))
            expect(window.isDismissing, "answering ends the native sheet session")
            expect(responses == [code == 53 ? .alertSecondButtonReturn : .alertFirstButtonReturn], "Return and Escape keep the original response indices")
            expect(parent.attachedSheet == nil, "answering detaches the sheet")
            window.close()
            expect(responses.count == 1, "a completion runs exactly once")
        }

        let rename = AppDialog(title: "Rename your Profile", actions: [DialogAction("Save"), .cancel], input: "", requiresInput: true, icon: .none)
        var renamed: NSApplication.ModalResponse?
        rename.present(over: parent) { renamed = $0 }
        let renameWindow = sheet(over: parent)
        renameWindow.sendEvent(key(36, window: renameWindow))
        expect(renamed == nil && renameWindow.isVisible, "empty names cannot submit")
        rename.input = "Work"
        renameWindow.sendEvent(key(36, window: renameWindow))
        expect(renamed == .alertFirstButtonReturn && rename.input == "Work", "the edited text survives dismissal")

        let profile = AppDialog(title: "Change Profile", actions: [DialogAction("Change Profile"), .cancel], suppressionTitle: "Don’t ask again")
        var suppressed = false
        profile.present(over: parent) { _ in suppressed = profile.isSuppressed }
        profile.isSuppressed = true
        profile.select(0)
        expect(suppressed, "the suppression choice is available in the completion")

        let confirmation = AppDialog(title: "Quit Cra?", actions: [DialogAction("Quit"), .cancel])
        RunLoop.current.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                expect(sheet(over: parent).sheetParent === parent, "a synchronous confirmation also uses a native sheet")
                confirmation.select(1)
            }
        }
        expect(confirmation.runModal(over: parent) == .alertSecondButtonReturn, "a synchronous sheet returns Cancel after native dismissal")
        expect(parent.attachedSheet == nil, "the synchronous sheet leaves no attached modal behind")

        let externallyDismissed = AppDialog(title: "Rename your Profile", actions: [DialogAction("Save"), .cancel], input: "Work")
        var externalResponse: NSApplication.ModalResponse?
        externallyDismissed.present(over: parent) { externalResponse = $0 }
        parent.endSheet(sheet(over: parent))
        expect(externalResponse == .abort, "native dismissal without a button cancels the operation")

        var dismissCustom: (() -> Void)?
        expect(DialogPanel.present(over: parent) { close in
            dismissCustom = close
            return Text("Profile settings").frame(width: 450, height: 338)
        }, "custom profile and URL views use the same sheet presenter")
        let customPanel = sheet(over: parent)
        expect(customPanel.contentView?.bounds.size == NSSize(width: 450, height: 338), "custom content keeps its measured size")
        expect(!DialogPanel.present(over: parent) { _ in Text("Duplicate") }, "custom content cannot replace an open sheet")
        dismissCustom?()
        expect(parent.attachedSheet == nil && !customPanel.isVisible, "closing custom content dismisses the native sheet")
        dismissCustom = nil

        let permission = AppDialog(title: "example.com wants to use your camera", actions: [DialogAction("Allow"), DialogAction("Block", role: .cancel)])
        var permissionResponse: NSApplication.ModalResponse?
        permission.present(over: parent) { permissionResponse = $0 }
        let permissionWindow = sheet(over: parent)
        var duplicateResponse: NSApplication.ModalResponse?
        AppDialog(title: "Another request").present(over: parent) { duplicateResponse = $0 }
        expect(duplicateResponse == .abort, "a duplicate request completes without replacing the first")
        expect(sheet(over: parent) === permissionWindow, "the original request stays visible")
        let permissionSize = permissionWindow.frame.size
        parent.setFrame(NSRect(x: -9900, y: -9900, width: 1100, height: 800), display: true)
        expect(permissionWindow.sheetParent === parent && permissionWindow.frame.size == permissionSize,
               "AppKit keeps the card attached without stretching it on parent resize")
        parent.close()
        expect(permissionResponse == .abort && !permissionWindow.isVisible, "closing the parent denies a pending permission")

        let modal = AppDialog(title: "Cra is still open", actions: [DialogAction("Try Again"), DialogAction("Force Quit", role: .destructive), .cancel])
        let modalWindow = modal.prepareWindow()
        modalWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        expect(modalWindow.contentView?.bounds.width == 450 && modalWindow.hasShadow,
               "a standalone panel fits its card and uses the system shadow")
        RunLoop.current.perform(inModes: [.modalPanel]) { MainActor.assumeIsolated { modal.select(1) } }
        expect(modal.runModal(over: nil) == .alertSecondButtonReturn, "a standalone modal returns its selected action")
        expect(!modalWindow.isVisible, "the standalone modal closes after a response")

        let autoClosing = AppDialog(title: "An older Cra is still open")
        let autoClosingWindow = autoClosing.prepareWindow()
        autoClosingWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        RunLoop.current.perform(inModes: [.modalPanel]) { NSApp.stopModal(withCode: .OK) }
        expect(autoClosing.runModal(over: nil) == .OK, "the old-copy timer can stop the modal without a button press")
        expect(!autoClosingWindow.isVisible, "external modal dismissal also removes the window")

        let error = AppDialog(error: NSError(domain: "DialogTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not save", NSLocalizedRecoverySuggestionErrorKey: "Try another folder."]))
        expect(error.title == "Could not save" && error.message == "Try another folder.", "errors keep their description and recovery advice")
        let errorWindow = error.prepareWindow()
        errorWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        RunLoop.current.perform(inModes: [.modalPanel]) { MainActor.assumeIsolated { errorWindow.sendEvent(key(53, window: errorWindow)) } }
        expect(error.runModal(over: nil) == .alertFirstButtonReturn, "Escape acknowledges a one-button error")
        print("Dialogs: \(checks) checks passed")
    }

    @MainActor
    private static func checkEaselDeletion() {
        let dialog = AppDialog.easelDeletion()
        expect(dialog.title == "Are you sure you want to delete this Easel?", "Easel deletion uses Arc's title")
        expect(dialog.message == "Doing so will delete the Easel permanently.", "Easel deletion explains permanence")
        expect(dialog.icon == .mark && dialog.width == 450, "Easel deletion uses the branded dialog card")
        expect(dialog.actions.buttons.map(\.title) == ["Delete", "Cancel"], "Easel deletion offers Delete and Cancel")
        expect(dialog.actions.buttons[0].role == .destructive, "Delete uses the destructive button style")
        expect(dialog.actions.trailingOrder == [1, 0], "Cancel precedes Delete visually")
        expect(dialog.actions.key(at: 0) == "↩" && dialog.actions.key(at: 1) == "ESC", "Easel deletion shows its keyboard shortcuts")
        for code: UInt16 in [36, 53, 76] {
            let window = AppDialog.easelDeletion().prepareWindow()
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            expect(window.contentView?.bounds.width == 450, "Easel deletion fits its card")
            expect(window.handleKey?(key(code, window: window)) == true, "Easel deletion handles Return, Escape and keypad Enter")
            expect(window.isDismissing, "a keyboard choice closes the dialog")
        }
    }

    @MainActor
    private static func snapshots(in directory: String) throws {
        let examples: [(String, AppDialog)] = [
            ("delete-easel", .easelDeletion()),
            ("delete-space", AppDialog(title: "Delete your “Work main” Space?", message: "This will archive all the tabs and folders inside it.",
                                       actions: [DialogAction("Delete", role: .destructive), .cancel])),
            ("rename-profile", AppDialog(title: "Rename your Profile", message: "This won’t affect the names of any of the Spaces associated with this Profile.",
                                         actions: [DialogAction("Save"), .cancel], input: "Work", requiresInput: true,
                                         icon: .none, width: 496, buttonSpacing: 30)),
            ("quit", AppDialog(title: "Quit Cra?", actions: [DialogAction("Quit"), .cancel, DialogAction("Quit, and don’t ask again", role: .secondary)],
                               icon: .application, buttonSpacing: 49.5, buttonOutset: 10.5)),
            ("long-message", AppDialog(title: "Move these spaces to their Arc profiles?", message: Array(repeating: "Work → Work Profile", count: 80).joined(separator: "\n"),
                                       actions: [DialogAction("Move and Restart"), .cancel])),
            ("last-space", AppDialog(title: "You need at least one space."))
        ]
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, dialog) in examples {
            let window = dialog.prepareWindow()
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            guard let view = window.contentView else { fatalError("Dialog content missing") }
            let bitmap = bitmap(of: view)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Dialog PNG missing") }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
            window.close()
        }
    }

    @MainActor
    private static func bitmap(of view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Dialog bitmap missing") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @MainActor
    private static func blueButtonCenter(in bitmap: NSBitmapImageRep, view: NSView) -> NSPoint {
        var minX = bitmap.pixelsWide, maxX = 0, minY = bitmap.pixelsHigh, maxY = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.blueComponent > 0.8, color.redComponent < 0.4, color.greenComponent < 0.4 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX < maxX, minY < maxY else { fatalError("The acknowledgement button must remain bright blue above the dim") }
        let x = CGFloat(minX + maxX) / 2 * view.bounds.width / CGFloat(bitmap.pixelsWide)
        let y = CGFloat(minY + maxY) / 2 * view.bounds.height / CGFloat(bitmap.pixelsHigh)
        return NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
    }

    @MainActor
    private static func sheet(over parent: NSWindow) -> DialogPanel {
        guard let window = parent.attachedSheet as? DialogPanel else {
            fatalError("Native dialog sheet missing")
        }
        return window
    }

    @MainActor
    private static func key(_ code: UInt16, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                         context: nil, characters: code == 53 ? "\u{1b}" : "\r", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}
