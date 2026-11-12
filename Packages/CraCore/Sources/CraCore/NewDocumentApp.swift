import Foundation

/// Arc's per-profile "New documents" (Settings ▸ Profiles, `defaultNoteDocumentApp`, described as "Default
/// Document App"): the online document the command bar's "New …" command creates ("Action to create a new
/// document; e.g. 'New Google Doc'"). Arc 1.172.2's options and addresses, in its pop-up's order. GitHub #375.
public enum NewDocumentApp: String, Codable, CaseIterable, Identifiable, Sendable {
    case confluencePage, googleDoc, notionPage, wordDoc

    public var id: String { rawValue }

    /// The pop-up's name, and the command's after "New ".
    public var name: String {
        switch self {
        case .confluencePage: "Confluence Page"
        case .googleDoc: "Google Doc"
        case .notionPage: "Notion Page"
        case .wordDoc: "Word Doc"
        }
    }

    /// The command bar's command: "New Google Doc".
    public var commandName: String { "New \(name)" }

    /// The address the command opens in a new tab.
    public var url: String {
        switch self {
        case .confluencePage: "https://make.page"
        case .googleDoc: "https://doc.new"
        case .notionPage: "https://app.notion.com/new"
        case .wordDoc: "https://word.new"
        }
    }

    /// Other words that find the command in the bar (its name's words already do).
    public var triggers: [String] {
        let common = ["document", "new note"]
        switch self {
        case .confluencePage: return common + ["atlassian", "wiki"]
        case .googleDoc: return common + ["google docs", "gdoc"]
        case .notionPage: return common
        case .wordDoc: return common + ["microsoft word", "office"]
        }
    }

    /// The command's id: its use count in the bar, and what the bar runs.
    public static let commandID = "newDocument"

    /// The key AppSettings.newDocumentApps files a profile under (nil is Default), as for downloads.
    public static func key(profileID: UUID?) -> String { DownloadLocation.key(profileID: profileID) }

    /// The map as saved: entries an older or newer Cra wrote with an app this one doesn't know are
    /// dropped, the rest kept.
    static func decodeMap(_ raw: [String: String]?) -> [String: NewDocumentApp] {
        (raw ?? [:]).compactMapValues(NewDocumentApp.init(rawValue:))
    }
}

public extension AppSettings {
    /// The profile's "New documents" app; nil is Arc's "——": no "New …" command.
    func newDocumentApp(profileID: UUID?) -> NewDocumentApp? {
        newDocumentApps[NewDocumentApp.key(profileID: profileID)]
    }

    mutating func setNewDocumentApp(_ app: NewDocumentApp?, profileID: UUID?) {
        newDocumentApps[NewDocumentApp.key(profileID: profileID)] = app
    }

    /// The command the bar offers in a window: the window's profile's choice, none in an incognito
    /// window (it has no profile of its own, and isn't signed in to make the document).
    func newDocumentCommand(profileID: UUID?, incognito: Bool) -> NewDocumentApp? {
        incognito ? nil : newDocumentApp(profileID: profileID)
    }
}
