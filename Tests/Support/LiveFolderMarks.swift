import AppKit

private func pluginMark(_ name: String) -> NSImage {
    let image = NSImage(contentsOf: URL(fileURLWithPath: "resources/live-folder-plugins/" + name + "/icon.svg"))!
    image.isTemplate = true
    return image
}

enum GitHubMark { static let image = pluginMark("github") }
enum GitLabMark { static let image = pluginMark("gitlab") }
