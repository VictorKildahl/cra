import CraCore
import UIKit

/// A hardware keyboard's shortcuts (`MobileKeyCommands`): ⌘T opens the search for a new tab, ⌘L
/// opens it on the page's address, Escape puts it away. Only the ones that do something now are
/// offered, so the others' keys still reach the page.
extension BrowserViewController {
    override var keyCommands: [UIKeyCommand]? {
        MobileKeyCommands.Command.allCases.compactMap { command in
            guard keyCommandEffect(command) != nil else { return nil }
            let input: String
            switch command.key {
            case .character(let character): input = character
            case .escape: input = UIKeyCommand.inputEscape
            }
            let key = UIKeyCommand(title: command.title, action: #selector(performKeyCommand(_:)), input: input,
                                   modifierFlags: command.withCommand ? .command : [], propertyList: command.rawValue)
            // Ahead of the search field's own use of Escape, and of UIApplication's (pointer lock).
            key.wantsPriorityOverSystemBehavior = command.key == .escape
            return key
        }
    }

    private func keyCommandEffect(_ command: MobileKeyCommands.Command) -> MobileKeyCommands.Effect? {
        MobileKeyCommands.effect(of: command, searching: isSearching, hasPage: shownPage != nil && switcher == nil,
                                 covered: presentedViewController != nil || menuHost != nil)
    }

    @objc private func performKeyCommand(_ sender: UIKeyCommand) {
        guard let raw = sender.propertyList as? String, let command = MobileKeyCommands.Command(rawValue: raw),
              let effect = keyCommandEffect(command) else { return }
        switch effect {
        case .search:
            startSearch()
        case .editAddress:
            guard let page = shownPage, let tab = store.tabs.first(where: { $0.id == page.tabID }) else { return startSearch() }
            editAddress(of: page, text: MobileAddressEdit.text(tabAddress: tab.url, pageAddress: page.webView.url?.absoluteString))
        case .closeSearch:
            dismissSearch()
        }
    }
}
