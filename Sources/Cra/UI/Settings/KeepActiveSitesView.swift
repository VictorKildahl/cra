import SwiftUI

/// Settings ▸ Tabs ▸ Memory ▸ "Always keep these sites active" (GitHub #458): Arc's list at
/// arc://settings/performance, drawn as Air Traffic Control's sheet is. Chrome's dialog adds a typed
/// address or a site from "Currently open sites"; here Add Site's menu offers both. Each row is the
/// address, whether its subdomains count, and a remove button.
struct KeepActiveSitesView: View {
    @Environment(SidebarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedSite: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always keep these sites active").font(.system(size: 13, weight: .bold))
                    Text("Their tabs stay in memory and keep running while hidden.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                addMenu
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
            sites
            Divider()
            Text("“example.com” with its subdomains also covers app.example.com, never notexample.com. The same list is at chrome://settings/performance.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .padding(.horizontal, 24)
        .frame(width: 508, height: 440)
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .onDisappear { store.settings.tidyKeepActiveSites() }
    }

    /// Chrome's two ways in: an address typed into a new row, or a site a tab has open now.
    private var addMenu: some View {
        Menu {
            Button("Type an Address") { addSite("") }
            let open = openSites
            if !open.isEmpty {
                Section("Currently Open Sites") {
                    ForEach(open, id: \.self) { host in
                        Button(host) { addSite(host) }
                    }
                }
            }
        } label: {
            Text("Add Site")
        }
        .menuStyle(.button)
        .fixedSize()
        .controlSize(.large)
    }

    private var sites: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 12) {
                    ForEach(store.settings.keepActiveSites) { site in
                        siteRow(site.id).id(site.id)
                    }
                }
                .padding(.vertical, 20)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if store.settings.keepActiveSites.isEmpty {
                    Text("Tabs on the sites you add here are never put to sleep or frozen, however long they stay hidden.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }
            .onChange(of: store.settings.keepActiveSites.last?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func siteRow(_ id: UUID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Address", text: binding(id, \.host), prompt: Text("example.com"))
                .textFieldStyle(.roundedBorder)
                .focused($focusedSite, equals: id)
                .frame(width: 200)
            Picker("Scope", selection: binding(id, \.includesSubdomains)) {
                Text("and its subdomains").tag(true)
                Text("this address only").tag(false)
            }
            .labelsHidden()
            .frame(width: 160)
            Button { removeSite(id) } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 13))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.background, .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
    }

    /// Hosts of the open tabs that no entry covers yet, most tabs first. Incognito tabs aren't offered.
    private var openSites: [String] {
        var counts: [String: Int] = [:]
        for item in store.allTabs() where !store.isIncognito(item: item.id) {
            // www. dropped: example.com with its subdomains covers www.example.com and the rest.
            guard let url = item.tab?.url, url.hasPrefix("http"), let host = AppSettings.siteKey(for: url),
                  !store.settings.keepsActive(url: url) else { continue }
            counts[host, default: 0] += 1
        }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(20).map(\.key)
    }

    private func binding<T>(_ id: UUID, _ key: WritableKeyPath<KeepActiveSite, T>) -> Binding<T> {
        Binding(
            get: { store.settings.keepActiveSites.first { $0.id == id }.map { $0[keyPath: key] } ?? KeepActiveSite(host: "")[keyPath: key] },
            set: { value in
                guard let i = store.settings.keepActiveSites.firstIndex(where: { $0.id == id }) else { return }
                store.settings.keepActiveSites[i][keyPath: key] = value
            })
    }

    private func addSite(_ host: String) {
        let site = KeepActiveSite(host: host)
        store.settings.keepActiveSites.append(site)
        if host.isEmpty { focusedSite = site.id }
    }

    private func removeSite(_ id: UUID) {
        if focusedSite == id { focusedSite = nil }
        store.settings.keepActiveSites.removeAll { $0.id == id }
    }
}
