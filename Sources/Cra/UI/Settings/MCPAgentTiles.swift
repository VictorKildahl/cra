import AppKit
import SwiftUI

/// Settings ▸ Advanced ▸ Agents: one click adds Cra to an agent's MCP settings, like the
/// "connect your agent" screens of apps that work inside agents. The six agents most people use
/// are tiles; the rest are in Other, and Copy MCP Configuration covers anything else.
struct MCPAgentTiles: View {
    private let installer = MCPAgentInstaller.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Cra to an agent").font(.system(size: 13))
                Text("Cra writes itself into the agent’s MCP settings. Each agent asks before it uses Cra the first time.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MCPAgentSetup.agents.filter(\.popular)) { agent in
                    MCPAgentTile(agent: agent, installer: installer)
                }
            }
            HStack(spacing: 8) {
                Menu("Other Agent") {
                    ForEach(MCPAgentSetup.agents.filter { !$0.popular }) { agent in
                        let state = installer.state(agent)
                        Button {
                            installer.add(agent)
                        } label: {
                            if state == .current { Label(agent.name, systemImage: "checkmark") } else { Text(agent.name) }
                        }
                        .disabled(!installer.isInstalled(agent))
                    }
                }
                .fixedSize()
                Button("Copy MCP Configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(MCPServer.shared.configuration, forType: .string)
                }
            }
            .controlSize(.small)
            if !installer.message.isEmpty {
                Text(installer.message)
                    .font(.system(size: 11))
                    .foregroundStyle(installer.messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .onAppear { installer.refresh() }
    }
}

/// One agent: its app icon (a terminal for a CLI), its name and whether Cra is in it.
private struct MCPAgentTile: View {
    let agent: MCPAgentApp
    let installer: MCPAgentInstaller
    @State private var hovering = false

    var body: some View {
        let state = installer.state(agent)
        let installed = installer.isInstalled(agent)
        Button { installer.add(agent) } label: {
            HStack(spacing: 8) {
                icon.frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    caption(state, installed: installed).font(.system(size: 10)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering && installed ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(state == .current ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: state == .current ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!installed)
        .opacity(installed ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(help(state, installed: installed))
        .contextMenu {
            if state == .current || state == .outdated {
                Button("Remove Cra from \(agent.name)") { installer.remove(agent) }
            }
            Button("Show Settings File in Finder") { installer.reveal(agent) }
        }
        .accessibilityLabel(agent.name)
        .accessibilityValue(help(state, installed: installed))
    }

    @ViewBuilder private var icon: some View {
        if let image = installer.icon(agent) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.85))
                .overlay(Image(systemName: "terminal").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor)))
                .padding(2)
        }
    }

    @ViewBuilder private func caption(_ state: MCPEntryState, installed: Bool) -> some View {
        switch state {
        case .current: Label("Added", systemImage: "checkmark").labelStyle(.titleAndIcon).foregroundStyle(.green)
        case .outdated: Text("Update").foregroundStyle(Color.accentColor)
        case .unreadable: Text("Can’t edit its settings").foregroundStyle(.red)
        case .absent: Text(installed ? (agent.detail.isEmpty ? "Add" : agent.detail) : "Not on this Mac").foregroundStyle(.secondary)
        }
    }

    private func help(_ state: MCPEntryState, installed: Bool) -> String {
        if !installed { return "Cra didn’t find \(agent.name) on this Mac." }
        switch state {
        case .current: return "Cra is in \(agent.name)’s MCP settings."
        case .outdated: return "\(agent.name) has Cra at another location. Click to point it at this Cra."
        case .unreadable: return "\(agent.name)’s settings file isn’t one Cra can change safely. Copy the configuration and add it by hand."
        case .absent: return "Add Cra to \(agent.name)’s MCP settings."
        }
    }
}
