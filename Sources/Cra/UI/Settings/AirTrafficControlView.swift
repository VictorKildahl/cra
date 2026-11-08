import SwiftUI

/// Arc's Air Traffic Control sheet (Settings ▸ Links, Arc 1.170), measured from window
/// captures and the accessibility tree: title and "New Route" over a hairline, one
/// two-line route per entry ("🔗 URL [Contains ⌃⌄] [text] ⊖" / "↳ Open in [Space ⌃⌄]",
/// 52 pt tall on a 76 pt pitch), then "Default" below a second hairline.
struct AirTrafficControlView: View {
    @Environment(SidebarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedRoute: UUID?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Air Traffic Control").font(.system(size: 13, weight: .bold))
                Spacer(minLength: 8)
                Button { addRoute() } label: { Text("New Route").frame(width: 94) }
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 6))
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .light)).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
                .keyboardShortcut(.cancelAction)
                .padding(.leading, 24)
            }
            .frame(height: 76)
            .padding(.top, 8)
            Divider()
            routes
            Divider()
            HStack(spacing: 0) {
                Text("Default").font(.system(size: 13))
                    .frame(width: 104, alignment: .leading)
                destinationPicker($store.settings.defaultLinkDestination)
                Spacer(minLength: 0)
            }
            .padding(.leading, 36)
            .frame(height: 90)
        }
        .padding(.horizontal, 24)
        .frame(width: 508, height: 440)
        // Arc opens the sheet with nothing focused; AppKit would select the first route's text.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private var routes: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    ForEach(store.settings.linkRoutes) { route in
                        routeRow(route.id).id(route.id)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
                .padding(.leading, 31)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if store.settings.linkRoutes.isEmpty {
                    Text("Add a route to open matching links from other apps in a chosen space.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }
            .onChange(of: store.settings.linkRoutes.last?.id) { _, id in
                guard let id, focusedRoute == id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func routeRow(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("URL", systemImage: "link")
                    .labelStyle(RouteLabelStyle())
                    .frame(width: 49, alignment: .leading)
                    .accessibilityLabel("Link URL")
                Picker("Match", selection: binding(id, \.match)) {
                    ForEach(LinkMatchStyle.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                TextField("URL", text: binding(id, \.text), prompt: Text("crabrowser.app"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRoute, equals: id)
                    .frame(width: 210)
                Button { removeRoute(id) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.background, .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            }
            HStack(spacing: 8) {
                Label("Open in", systemImage: "arrow.turn.down.right")
                    .labelStyle(RouteLabelStyle())
                    .frame(width: 70, alignment: .leading)
                destinationPicker(binding(id, \.destination))
            }
            .padding(.leading, 74)
        }
    }

    /// Arc's destination menu: an "Open in Space" header over Most Recent Space and
    /// every space, then Little Arc after a separator.
    private func destinationPicker(_ selection: Binding<LinkDestination>) -> some View {
        let spaces = store.orderedSpaces
        // A route to a deleted space opens in the most recent one; show it that way.
        let shown = Binding<LinkDestination>(
            get: {
                if case .space(let sid) = selection.wrappedValue, !spaces.contains(where: { $0.id == sid }) { return .mostRecentSpace }
                return selection.wrappedValue
            },
            set: { selection.wrappedValue = $0 })
        return Picker("Open in", selection: shown) {
            Section("Open in Space") {
                Text("Most Recent Space").tag(LinkDestination.mostRecentSpace)
                ForEach(spaces) { space in
                    Text(space.labeled).tag(LinkDestination.space(space.id))
                }
            }
            Divider()
            Text("Little Window").tag(LinkDestination.littleWindow)
        }
        .labelsHidden()
        .frame(width: 165)
    }

    private func binding<T>(_ id: UUID, _ key: WritableKeyPath<LinkRoute, T>) -> Binding<T> {
        Binding(
            get: { store.settings.linkRoutes.first { $0.id == id }.map { $0[keyPath: key] } ?? LinkRoute()[keyPath: key] },
            set: { value in
                guard let i = store.settings.linkRoutes.firstIndex(where: { $0.id == id }) else { return }
                store.settings.linkRoutes[i][keyPath: key] = value
            })
    }

    private func addRoute() {
        let route = LinkRoute()
        store.settings.linkRoutes.append(route)
        focusedRoute = route.id
    }

    private func removeRoute(_ id: UUID) {
        if focusedRoute == id { focusedRoute = nil }
        store.settings.linkRoutes.removeAll { $0.id == id }
    }
}

/// Secondary 13 pt label with its symbol in front ("🔗 URL", "↳ Open in").
private struct RouteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12))
            configuration.title.font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
    }
}
