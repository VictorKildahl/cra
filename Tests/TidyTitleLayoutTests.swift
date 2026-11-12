import AppKit

@main
enum TidyTitleLayoutTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let short = "Arc"
        let informative = "Arc Monetization Strategy"
        let label = NSTextField(labelWithString: "Original title")
        label.font = .systemFont(ofSize: 14)
        let measured = (informative as NSString).size(withAttributes: [.font: label.font!]).width
        label.frame.size.width = measured + 4
        let layout = TidyTitleLayout(label: label, inset: 2)
        expect(layout.width == measured, "the drawable title width excludes both text-field insets")
        expect(layout.select([informative, short], shown: "Original title") == informative,
               "an informative candidate fitting the actual native title box must be used")

        label.frame.size.width = 30
        let resized = TidyTitleLayout(label: label, inset: 2)
        expect(resized.select([informative, short], shown: "Original title") == short,
               "a resized title box uses the new width rather than an earlier snapshot")
        expect(TidyTitleLayout.fallback.select([informative, short], shown: "Original title") == short,
               "an unmaterialized row uses the smallest measured candidate")

        label.frame.size.width = measured + 4
        label.font = .systemFont(ofSize: 28)
        expect(TidyTitleLayout(label: label, inset: 2).select([informative, short], shown: "Original title") == short,
               "measurement uses the title label's actual font")
        label.frame.size.width = 1
        expect(TidyTitleLayout(label: label, inset: 2).width == 0, "padding never creates negative drawable width")
        sidebarPresentationSelection()
        print("Tidy title layout: 10 checks passed")
    }

    @MainActor
    private static func sidebarPresentationSelection() {
        let origin = UUID(), other = UUID()
        let short = "Arc", informative = "Arc Monetization Strategy"
        let sidebarLabel = NSTextField(labelWithString: "Sidebar title")
        sidebarLabel.font = .systemFont(ofSize: 14)
        sidebarLabel.frame.size.width = (informative as NSString).size(withAttributes: [.font: sidebarLabel.font!]).width + 4
        let cardLabel = NSTextField(labelWithString: "Spaces card title")
        cardLabel.font = sidebarLabel.font
        cardLabel.frame.size.width = 40
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView!.addSubview(sidebarLabel)
        window.contentView!.addSubview(cardLabel)
        cardLabel.isHidden = true // A hidden Library Spaces manager remains attached.
        let otherNativeWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 150, height: 300),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        let otherLabel = NSTextField(labelWithString: "Other window title")
        otherLabel.font = sidebarLabel.font
        otherLabel.frame.size.width = 40
        otherNativeWindow.contentView!.addSubview(otherLabel)

        typealias Source = (windowID: UUID, showsNewTab: Bool, label: NSTextField)
        let sidebar: Source = (origin, true, sidebarLabel)
        let manager: Source = (origin, false, cardLabel)
        let otherWindow: Source = (other, true, otherLabel)
        func name(_ sources: [Source]) -> String? {
            let source = sources.first {
                TidyTitles.usesSidebarLayout(windowID: $0.windowID, originWindowID: origin,
                                             hasWindow: $0.label.window != nil, showsNewTab: $0.showsNewTab)
            }
            let layout = source.map { TidyTitleLayout(label: $0.label, inset: 2) } ?? .fallback
            return layout.select([informative, short], shown: "Original title")
        }
        expect(name([manager, otherWindow, sidebar]) == informative,
               "a same-window hidden Spaces card cannot choose the persisted title's width")
        expect(name([sidebar, manager, otherWindow]) == informative,
               "the sidebar choice is independent of registry order")
        expect(name([otherWindow, sidebar]) == informative,
               "another window's list cannot supply the originating sidebar's width")
        expect(name([manager, otherWindow]) == short,
               "without the intended sidebar, manager and other-window rows cannot replace the smallest fallback")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
}
