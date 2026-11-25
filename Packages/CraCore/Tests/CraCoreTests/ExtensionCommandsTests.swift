import CraCore
import Testing

/// Extension keyboard shortcuts outside Global scope (GitHub #701): Chromium keeps them per profile in
/// extensions.commands, and Cra runs the ones that open the extension's popup.
struct ExtensionCommandsTests {
    static let option = KeyChord.Modifiers.option.rawValue
    static let shift = KeyChord.Modifiers.shift.rawValue
    static let command = KeyChord.Modifiers.command.rawValue
    static let control = KeyChord.Modifiers.control.rawValue
    static let pref = #"{"mac:Alt+Shift+Y":{"command_name":"_execute_action","extension":"miocmppoaodadgmokcmlndeobefobgfb","global":false},"mac:Command+Shift+L":{"command_name":"lock","extension":"aeblfdkhhhdcdjpifhhbdiojplfjncoa","global":false},"mac:MacCtrl+Period":{"command_name":"_execute_browser_action","extension":"x","global":true},"linux:Ctrl+K":{"command_name":"_execute_action","extension":"y","global":false}}"#

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/701"))
    func readsTheMacBindingsChromiumKeeps() {
        let b = ExtensionCommands.bindings(prefJSON: Self.pref)
        #expect(b.count == 3)
        let popup = b.first { $0.extensionID == "miocmppoaodadgmokcmlndeobefobgfb" }
        #expect(popup?.key == "Y" && popup?.modifiers == [.option, .shift] && popup?.global == false)
        #expect(b.first { $0.command == "lock" }?.modifiers == [.command, .shift])
        #expect(b.first { $0.extensionID == "x" }?.key == "Period" && b.first { $0.extensionID == "x" }?.modifiers == [.control])
        #expect(ExtensionCommands.bindings(prefJSON: "nonsense").isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/701"))
    func aKeyPressFindsItsShortcut() {
        let b = ExtensionCommands.bindings(prefJSON: Self.pref)
        // ⌥⇧Y: the popup's shortcut, whatever case the letter comes in.
        #expect(ExtensionCommands.binding(in: b, characters: "Y", keyCode: 16, modifiers: Self.option | Self.shift)?.command == "_execute_action")
        #expect(ExtensionCommands.binding(in: b, characters: "y", keyCode: 16, modifiers: Self.option | Self.shift)?.command == "_execute_action")
        // Other modifiers, or the letter alone: not it.
        #expect(ExtensionCommands.binding(in: b, characters: "Y", keyCode: 16, modifiers: Self.option) == nil)
        #expect(ExtensionCommands.binding(in: b, characters: "Y", keyCode: 16, modifiers: 0) == nil)
        // A Global one is the system's: macOS runs it as a hot key, so Cra leaves it alone.
        #expect(ExtensionCommands.binding(in: b, characters: ".", keyCode: 47, modifiers: Self.control) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/701"))
    func theActionCommandsOpenThePopup() {
        #expect(ExtensionCommands.opensPopup("_execute_action"))
        #expect(ExtensionCommands.opensPopup("_execute_browser_action"))
        #expect(ExtensionCommands.opensPopup("_execute_page_action"))
        #expect(!ExtensionCommands.opensPopup("lock"))
    }

    /// Obsidian Web Clipper's ⌘⇧O is Cra's Show Little Window "Open In" Menu too, dimmed in a browser window: the key
    /// goes to the extension there, as in Arc. Where Cra's row runs, or is hidden but its key still acts, Cra keeps it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/744"))
    func anExtensionGetsAKeyWhoseCraRowIsDimmed() {
        #expect(ExtensionCommands.extensionTakes(craMenuRanIt: false, craRowHidden: false))
        #expect(!ExtensionCommands.extensionTakes(craMenuRanIt: true, craRowHidden: false))
        #expect(!ExtensionCommands.extensionTakes(craMenuRanIt: false, craRowHidden: true))
    }

    /// A ⌘ key typed in a page reaches Cra before the page only through the engine's key hook: there an extension's
    /// shortcut comes first, as in Chrome and Arc. ⌘⇧Y, which Cra has no command for, and the clipper's ⌘⇧O, whose Cra
    /// row is dimmed in a browser window, are the extension's; a Cra row that runs, or a hidden one whose key still
    /// acts, keeps its key.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/744"))
    func anExtensionsKeyComesBeforeThePage() {
        #expect(ExtensionCommands.extensionTakesBeforePage(craRowCanRun: nil, craRowHidden: false))
        #expect(ExtensionCommands.extensionTakesBeforePage(craRowCanRun: false, craRowHidden: false))
        #expect(!ExtensionCommands.extensionTakesBeforePage(craRowCanRun: true, craRowHidden: false))
        #expect(!ExtensionCommands.extensionTakesBeforePage(craRowCanRun: false, craRowHidden: true))
    }
}
