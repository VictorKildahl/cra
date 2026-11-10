import AppKit
import CraCEF
import Darwin
import Observation

@MainActor @Observable
final class MCPServer {
    static let shared = MCPServer()
    private(set) var enabled = false
    private(set) var status = "Off"
    private(set) var lastTool = ""
    /// The user's answers (mcp.json in the data folder, so a test copy's stay its own).
    private var settings = MCPServer.loadSettings() {
        didSet { MCPServer.save(settings) }
    }
    /// Agents the user answered, remembered by identity (MCPAgents). Settings lists and forgets them.
    var agents: [MCPAgent] { settings.agents }
    /// page_evaluate: off unless the user turns it on, since a script can read anything a page
    /// holds, passwords Chromium filled in included (an agent's click counts as the user's gesture).
    var allowsScripts: Bool {
        get { settings.allowsScripts }
        set { settings.allowsScripts = newValue }
    }
    /// For this run only (launch arguments of isolated test copies): agents allowed without a
    /// prompt (-mcpApprovesAgents YES), and page_evaluate on (-mcpAllowsScripts YES).
    @ObservationIgnored private let approvesAgents = MCPServer.launchArgument("mcpApprovesAgents")

    /// A YES/NO launch argument (-key YES), never a saved preference.
    private static func launchArgument(_ key: String) -> Bool {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] != nil && UserDefaults.standard.bool(forKey: key)
    }

    private static var settingsFile: URL { AppPaths.file("mcp.json") }
    private static func loadSettings() -> MCPSettings {
        var loaded = MCPSettings.decode(try? Data(contentsOf: settingsFile))
        if launchArgument("mcpAllowsScripts") { loaded.allowsScripts = true }
        return loaded
    }
    private static func save(_ settings: MCPSettings) {
        let url = settingsFile
        try? settings.encoded().write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    @ObservationIgnored private var asking: [String: AppDialog] = [:]
    @ObservationIgnored private var identities: [Int32: String] = [:]
    @ObservationIgnored private weak var app: AppDelegate?
    @ObservationIgnored private var endpoint: MCPListener?
    @ObservationIgnored private var listener: DispatchSourceRead?
    @ObservationIgnored private var clients: Set<Int32> = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var busyTabs: [UUID: UUID] = [:]
    @ObservationIgnored private var pages: [UUID: MCPPage] = [:]
    @ObservationIgnored private var ownedTabs: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var agentTabs: [UUID: (owner: UUID, browser: CraBrowser)] = [:]
    @ObservationIgnored private var transfers: [UUID: MCPTransfers] = [:]
    @ObservationIgnored private var pointerPositions: [UUID: CGPoint] = [:]
    private var path: String { AppPaths.file("mcp.sock").path }

    var configuration: String {
        let config: [String: Any] = ["mcpServers": ["cra": [
            "command": Bundle.main.executablePath ?? "", "args": ["--mcp", path]
        ]]]
        let data = try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func start(app: AppDelegate) {
        self.app = app
        setEnabled(UserDefaults.standard.bool(forKey: "mcpEnabled"))
    }

    func setEnabled(_ value: Bool) {
        stop()
        // Command-line overrides are process-local (also used by isolated scenarios).
        if UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["mcpEnabled"] == nil {
            UserDefaults.standard.set(value, forKey: "mcpEnabled")
        }
        guard value else { return }
        do {
            let endpoint = try MCPListener(path: path)
            let fd = try endpoint.bind()
            MCPTransfers.removeAbandonedUploads()
            self.endpoint = endpoint
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.acceptClient(fd) }
            source.setCancelHandler { close(fd) }
            listener = source
            enabled = true
            status = "On — local access to your tabs and signed-in sessions"
            source.resume()
        } catch {
            status = "Could not start: \(error.localizedDescription)"
        }
    }

    func stop() {
        generation = UUID()
        enabled = false
        status = "Off"
        endpoint?.stop()
        endpoint = nil
        listener?.cancel()
        listener = nil
        for fd in clients { shutdown(fd, SHUT_RDWR) }
        clients.removeAll()
        for transfer in transfers.values { transfer.close() }; transfers.removeAll()
        for tab in agentTabs.values { tab.browser.close() }
        agentTabs.removeAll()
        for page in pages.values { page.detach() }
        pages.removeAll(); pointerPositions.removeAll(); ownedTabs.removeAll()
    }

    private func acceptClient(_ fd: Int32) {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        guard clients.count < 8 else { close(client); return }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        clients.insert(client)
        let session = generation
        let peer = MCPPeer.of(socket: client)
        let protocolSession = MCPSession()
        protocolSession.disabledTools = { [weak self] in self?.allowsScripts == true ? [] : ["page_evaluate"] }
        protocolSession.offReason = { _ in "page_evaluate is off. The user can turn on Settings ▸ Advanced ▸ Let agents run JavaScript; until then use page_read, page_snapshot and page_screenshot." }
        let owner = UUID()
        let state = MCPClientState()
        let writer = DispatchQueue(label: "cra.mcp.writer")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reader = MCPConnection.Reader()
            let pending = DispatchGroup()
            let capacity = DispatchSemaphore(value: 32)
            while let line = reader.next(client) {
                guard capacity.wait(timeout: .now()) == .success else { break }
                pending.enter()
                let reply = MCPReply()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.enabled, self.generation == session, reply.isPending else { reply.finish(nil); return }
                    let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                    if request?["jsonrpc"] as? String == "2.0", request?["id"] == nil,
                       request?["method"] as? String == "notifications/cancelled",
                       let params = request?["params"] as? [String: Any], let id = params["requestId"], let key = MCPClientState.key(id) {
                        state.requests[key]?.cancel()
                        reply.finish(nil)
                        return
                    }
                    let key = request?["id"].flatMap(MCPClientState.key)
                    if let key, state.requests[key] != nil {
                        reply.finish(try? JSONSerialization.data(withJSONObject: MCPProtocol.error(id: request!["id"]!, code: -32600, message: "Request ID is already in flight.")))
                        return
                    }
                    if let key { state.requests[key] = reply }
                    protocolSession.receive(line, perform: { name, arguments, completion in
                        // Nothing runs before the user allowed this agent.
                        guard self.authorize(client: client, name: protocolSession.clientName ?? "", peer: peer, completion: completion) else { return }
                        self.lastTool = name
                        self.perform(name, arguments: arguments, owner: owner, canContinue: { [weak self] in
                            self?.enabled == true && self?.generation == session && reply.isPending && !reply.isCancelled
                                && (!MCPProtocol.inputTools.contains(name) || MCPConnection.peerIsOpen(client))
                        }, completion: completion)
                    }) { data in
                        if let key, state.requests[key] === reply { state.requests.removeValue(forKey: key) }
                        reply.finish(data)
                    }
                }
                DispatchQueue.global(qos: .utility).async {
                    if reply.ready.wait(timeout: .now() + MCPProtocol.responseTimeout(line)) != .success {
                        reply.cancel(); reply.finish(nil)
                        shutdown(client, SHUT_RDWR)
                    }
                    if let data = reply.data {
                        writer.sync {
                            if !MCPConnection.write(data + Data([10]), to: client) { shutdown(client, SHUT_RDWR) }
                        }
                    }
                    capacity.signal(); pending.leave()
                }
            }
            // EOF stops input through peerIsOpen, but accepted read-only requests drain.
            pending.wait()
            shutdown(client, SHUT_RDWR)
            Task { @MainActor [weak self] in
                self?.clients.remove(client)
                self?.identities.removeValue(forKey: client)
                self?.ownedTabs.removeValue(forKey: owner)
                // The last client gone: pages stop emulating focus and reporting events.
                if let self, self.clients.isEmpty {
                    for page in self.pages.values { page.detach() }
                    self.pages.removeAll()
                }
                if let self {
                    for (id, tab) in self.agentTabs where tab.owner == owner {
                        self.transfers.removeValue(forKey: id)?.close()
                        tab.browser.close(); self.agentTabs.removeValue(forKey: id)
                        self.pages.removeValue(forKey: id); self.pointerPositions.removeValue(forKey: id)
                    }
                }
                close(client)
            }
        }
    }

    /// Whether this connection's agent may use Cra. The first time an agent connects Cra asks
    /// (Allow / Don't Allow) and remembers the answer; until then calls get a message to wait.
    private func authorize(client: Int32, name: String, peer: MCPPeer, completion: @escaping ([String: Any]) -> Void) -> Bool {
        let id = MCPAgents.identity(clientName: name, signer: peer.signer)
        identities[client] = id
        if approvesAgents { return true }
        let display = MCPAgents.displayName(name)
        switch MCPAgents.decision(for: id, in: agents) {
        case true?: return true
        case false?:
            completion(MCPProtocol.content("The user didn't allow \(display) to use Cra. They can change that in Settings ▸ Advanced.", failed: true))
            return false
        case nil:
            ask(id: id, name: display, via: peer.via)
            completion(MCPProtocol.content("Cra is asking the user to allow \(display). Wait for their answer, then try again.", failed: true))
            return false
        }
    }

    private func ask(id: String, name: String, via: String) {
        guard asking[id] == nil else { return }
        let from = via.isEmpty ? "" : " It's asking from \(via)."
        let dialog = AppDialog(title: "Let \u{201C}\(name)\u{201D} use Cra?",
                               message: "While it runs, it can open tabs, read your pages and act in them, signed in as you.\(from) You can take this back in Settings ▸ Advanced.",
                               actions: [DialogAction("Allow"), DialogAction("Don\u{2019}t Allow", role: .cancel)])
        asking[id] = dialog
        let answer: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.asking.removeValue(forKey: id)
            guard response != .abort else { return }  // closed unanswered: ask again next time
            self.record(MCPAgent(id: id, name: name, via: via, allowed: response == .alertFirstButtonReturn, decided: Date()))
        }
        // A security question waits for the user, so this is the one time MCP brings Cra forward.
        guard let window = app?.mainWindows.first(where: { !$0.isIncognito })?.window else {
            NSApp.activate(ignoringOtherApps: true)
            answer(dialog.runModal(over: nil)); return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.requestUserAttention(.criticalRequest)
        dialog.present(over: window, completion: answer)
    }

    /// Answers the open approval prompt as the user would (cra://debug?mcpAnswer=allow|deny, test copies).
    func answerPrompt(allow: Bool) {
        asking.values.first?.select(allow ? 0 : 1)
    }

    private func record(_ agent: MCPAgent) {
        settings.agents = MCPAgents.recording(agent, in: settings.agents)
        if !agent.allowed { disconnect(agent.id) }
    }

    /// Forgets an answer: the agent is asked again next time, and its open connections close now.
    func forget(_ agent: MCPAgent) {
        settings.agents.removeAll { $0.id == agent.id }
        disconnect(agent.id)
    }

    private func disconnect(_ id: String) {
        for (fd, identity) in identities where identity == id { shutdown(fd, SHUT_RDWR) }
    }

    private func perform(_ name: String, arguments: [String: Any], owner: UUID, canContinue: @escaping () -> Bool,
                         woke: Bool = false, completion: @escaping ([String: Any]) -> Void) {
        guard let app else { completion(MCPProtocol.content("Browser is unavailable", failed: true)); return }
        if name == "tabs_list" {
            // Sidebar order: spaces left to right, then favorites, pinned and today, folders inline.
            // `active` is the tab on screen in the window the user last used.
            let activeWindow = app.store.activeWindowID
            let activeTab = app.store.selectedTabID(window: activeWindow)
            var seen: Set<UUID> = []
            var tabs: [[String: Any]] = []
            for sid in app.store.spaceOrder {
                guard let space = app.store.space(sid) else { continue }
                let selected = Set(app.mainWindows.filter { !$0.isIncognito }.compactMap { app.store.selectedTabID(in: sid, window: $0.windowID) })
                for (section, container) in [("favorites", space.favoritesContainerID), ("pinned", space.pinnedContainerID), ("today", space.todayContainerID)] {
                    for item in app.store.tabs(under: container) where app.store.mcpTab(item.id) != nil && seen.insert(item.id).inserted {
                        var row: [String: Any] = ["id": item.id.uuidString, "title": item.displayTitle, "url": item.tab?.url ?? "",
                                                  "space": space.title, "section": section,
                                                  "owned": ownedTabs[owner]?.contains(item.id) == true,
                                                  "loaded": app.runtime(for: item.id).map { !$0.discarded } ?? false]
                        var folders: [String] = []
                        var parent = item.parentID
                        while let id = parent, let folder = app.store.item(id), folder.isFolder {
                            folders.insert(folder.displayTitle, at: 0); parent = folder.parentID
                        }
                        if !folders.isEmpty { row["folder"] = folders.joined(separator: " / ") }
                        if selected.contains(item.id) { row["selected"] = true }
                        if item.id == activeTab { row["active"] = true }
                        if let url = item.tab?.url, !url.isEmpty, !MCPProtocol.navigable(url) { row["webPage"] = false }
                        if let runtime = app.runtime(for: item.id), let dialog = MCPPage.dialog(of: runtime.browser) { row["dialog"] = dialog }
                        tabs.append(row)
                    }
                }
            }
            tabs += agentTabs.filter { $0.value.owner == owner }.map { id, tab in
                ["id": id.uuidString, "title": tab.browser.currentTitle, "url": tab.browser.currentURL,
                 "owned": true, "loaded": tab.browser.isCreated && !tab.browser.isClosed, "closed": tab.browser.isClosed, "windowless": true]
            }
            completion((try? MCPCDP.content(tabs)) ?? MCPProtocol.content("Could not list tabs", failed: true))
            return
        }
        if name == "tab_open" {
            guard canContinue(), let url = arguments["url"] as? String, MCPProtocol.navigable(url),
                  let window = app.mainWindows.first(where: { $0.windowID == app.store.lastNormalWindowID && !$0.isIncognito }) else {
                completion(MCPProtocol.content("Opening a tab requires an HTTP(S) URL and a normal browser window.", failed: true)); return
            }
            if arguments["windowless"] as? Bool == true {
                guard agentTabs.count < 8 else { completion(MCPProtocol.content("Eight agent tabs are retained. Use tabs_list and tab_close to release open or timed-out tabs.", failed: true)); return }
                let id = UUID()
                let profile = app.store.profilePath(space: app.store.focusedSpaceID(window: window.windowID))
                let browser = CraBrowser(agentURL: url, profilePath: profile)
                agentTabs[id] = (owner, browser)
                completion(try! MCPCDP.content(["tabId": id.uuidString, "status": "opened", "windowless": true]))
                return
            }
            // By default the tab opens in the sidebar like a ⌘-clicked link: unread, loading, not
            // selected, so the agent works next to the user without taking their screen.
            let select = arguments["select"] as? Bool == true
            var space: UUID?
            if let name = arguments["space"] as? String {
                space = app.store.spaceOrder.first { app.store.space($0)?.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
                guard space != nil else {
                    let names = app.store.spaceOrder.compactMap { app.store.space($0)?.title }
                    completion(MCPProtocol.content("No space is called \(name). Spaces: " + names.joined(separator: ", ") + ".", failed: true)); return
                }
            }
            let tab = app.store.createTab(url: url, in: space, select: select, window: window.windowID)
            ownedTabs[owner, default: []].insert(tab.id)
            if !select { window.browsers.ensureRuntime(for: tab.id) }
            if arguments["activate"] as? Bool == true {
                window.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            completion(try! MCPCDP.content(["tabId": tab.id.uuidString, "status": "opened", "selected": select]))
            return
        }
        guard let text = arguments["tabId"] as? String, let id = UUID(uuidString: text), app.store.mcpTab(id) != nil || agentTabs[id]?.owner == owner else {
            completion(MCPProtocol.content("Normal tab unavailable.", failed: true)); return
        }
        guard busyTabs[id] == nil else {
            completion(MCPProtocol.content("Tab is busy with another MCP action. Inspect its result before continuing.", failed: true)); return
        }
        if let agent = agentTabs[id], agent.owner == owner, name == "tab_show" || name == "tab_close" {
            if name == "tab_show" { completion(MCPProtocol.content("This is a windowless agent tab. Use page_screenshot to inspect it or open its URL in a normal tab.", failed: true)); return }
            transfers.removeValue(forKey: id)?.close()
            agent.browser.close(); agentTabs.removeValue(forKey: id); pages.removeValue(forKey: id); pointerPositions.removeValue(forKey: id)
            completion(try! MCPCDP.content(["status": "closed"])); return
        }
        if name == "tab_show" || name == "tab_close" {
            guard canContinue(), let window = app.mainWindows.first(where: { !$0.isIncognito && $0.browsers.runtime(for: id) != nil })
                    ?? app.mainWindows.first(where: { $0.windowID == app.store.lastNormalWindowID && !$0.isIncognito }) else {
                completion(MCPProtocol.content("Normal browser window unavailable.", failed: true)); return
            }
            if name == "tab_close" {
                // Any today tab, like ⌘W (Reopen Closed Tab brings it back). Pinned tabs and
                // favorites are the user's own layout and stay.
                guard !app.store.isPinned(id), app.store.splitContaining(id) == nil else {
                    completion(MCPProtocol.content("Pinned tabs, favorites and tabs in a split stay open; close only today tabs.", failed: true)); return
                }
                transfers.removeValue(forKey: id)?.close()
                if let page = pages[id] { page.detach() }
                window.closeTab(id)
                ownedTabs[owner]?.remove(id); pages.removeValue(forKey: id); pointerPositions.removeValue(forKey: id)
            } else {
                app.store.selectTab(id, window: window.windowID)
                if arguments["activate"] as? Bool == true {
                    window.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            completion(try! MCPCDP.content(["status": name == "tab_close" ? "closed" : "shown"]))
            return
        }
        if name == "download_status" || name == "download_cancel" {
            do {
                guard canContinue(), agentTabs[id]?.owner == owner, let transfer = transfers[id] else { throw MCPCDP.Failure(message: "This connection's agent tab has no downloads.") }
                completion(try transfer.run(name, arguments: arguments))
            } catch { completion(MCPProtocol.content(error.localizedDescription, failed: true)) }
            return
        }
        let browser: CraBrowser
        if let agent = agentTabs[id], agent.owner == owner { browser = agent.browser }
        else if let runtime = app.runtime(for: id), !runtime.discarded { browser = runtime.browser }
        else {
            // A sleeping or never-opened tab wakes in the background, as a ⌘-clicked link loads,
            // and the request goes on once its page has loaded (up to 10 s).
            let window = app.mainWindows.first(where: { !$0.isIncognito && $0.browsers.runtime(for: id) != nil })
                ?? app.mainWindows.first(where: { $0.windowID == app.store.lastNormalWindowID && !$0.isIncognito })
            if app.runtime(for: id) != nil { window?.browsers.touchedByAgent(id) } else { window?.browsers.ensureRuntime(for: id) }
            Task { @MainActor [weak self, weak app] in
                let loaded = { () -> Bool in
                    guard let runtime = app?.runtime(for: id) else { return false }
                    return !runtime.discarded && runtime.browser.isCreated && !runtime.browser.isLoading
                }
                for _ in 0..<100 where !loaded() && canContinue() { try? await Task.sleep(for: .milliseconds(100)) }
                guard let self, !woke, loaded(), canContinue() else {
                    completion(MCPProtocol.content("The tab was asleep and is still loading. Try again in a moment.", failed: true)); return
                }
                self.perform(name, arguments: arguments, owner: owner, canContinue: canContinue, woke: true, completion: completion)
            }
            return
        }
        guard browser.isCreated, !browser.isClosed, !browser.isIncognito else {
            completion(MCPProtocol.content("Page is not ready or has closed.", failed: true)); return
        }
        // Only web pages: Chrome's settings and password pages, extension pages (a password
        // manager's vault), DevTools and local files stay out of an agent's reach.
        guard MCPProtocol.navigable(browser.currentURL) else {
            completion(MCPProtocol.content("This tab isn't a web page (\(browser.currentURL.prefix(40))). Agents only work in http and https pages.", failed: true)); return
        }
        for tabID in Array(transfers.keys) where agentTabs[tabID] == nil && (app.store.mcpTab(tabID) == nil || app.runtime(for: tabID)?.browser !== pages[tabID]?.browser) {
            transfers.removeValue(forKey: tabID)?.close()
        }
        pages = pages.filter {
            let live = agentTabs[$0.key]?.browser === $0.value.browser || app.store.mcpTab($0.key) != nil && app.runtime(for: $0.key)?.browser === $0.value.browser
            if !live { $0.value.detach() }
            return live
        }
        if pages[id] == nil { pages[id] = MCPPage(browser) }
        let page = pages[id]!
        if agentTabs[id] == nil { app.mainWindows.first { $0.browsers.runtime(for: id) != nil }?.browsers.touchedByAgent(id) }
        let lease = UUID()
        busyTabs[id] = lease
        let cdp = MCPCDP(browser) { [weak self, weak app] in
            let agentValid = self?.agentTabs[id]?.owner == owner && self?.agentTabs[id]?.browser === browser
            let normalValid = app?.store.mcpTab(id) != nil && app?.runtime(for: id)?.browser === browser
            return canContinue() && (agentValid || normalValid) && !browser.isClosed && !browser.isIncognito
        }
        Task { @MainActor in
            defer { if busyTabs[id] == lease { busyTabs.removeValue(forKey: id) } }
            await page.attach(cdp)
            do {
                let result: [String: Any]
                if name == "page_download" {
                    guard browser.isAgent else { throw MCPCDP.Failure(message: "Download tools need a windowless tab this connection opened (tab_open windowless=true).") }
                    if transfers[id] == nil {
                        guard transfers.count < 16 else { throw MCPCDP.Failure(message: "File-transfer tab limit reached. Close an existing transfer tab first.") }
                        transfers[id] = MCPTransfers(browser)
                    }
                }
                if ["page_download", "download_status", "download_cancel"].contains(name) {
                    try cdp.check()
                    result = try transfers[id]!.run(name, arguments: arguments)
                } else if MCPProtocol.inputTools.contains(name) {
                    let reference: (node: Int, document: String)?
                    if let ref = arguments["ref"] as? String { reference = try await page.resolve(ref, cdp: cdp) } else { reference = nil }
                    let input = MCPInput(browser: browser, position: pointerPositions[id] ?? CGPoint(x: 8, y: 8), reference: reference, screenshotScale: page.screenshotScale, stageUploads: { [weak server = self] paths in
                        guard let self = server else { throw MCPCDP.Failure(message: "Upload staging is unavailable.") }
                        if self.transfers[id] == nil {
                            guard self.transfers.count < 16 else { throw MCPCDP.Failure(message: "File-transfer tab limit reached.") }
                            self.transfers[id] = MCPTransfers(browser)
                        }
                        let transfer = self.transfers[id]!
                        do { return try await transfer.stage(paths) }
                        catch { if transfer.isEmpty, self.transfers[id] === transfer { self.transfers.removeValue(forKey: id) }; throw error }
                    }, discardUploads: { [weak server = self] paths in
                        server?.transfers[id]?.discard(paths)
                        if server?.transfers[id]?.isEmpty == true { server?.transfers.removeValue(forKey: id) }
                    }, canContinue: cdp.canContinue)
                    result = await input.run(name: name, arguments: arguments)
                    pointerPositions[id] = input.position
                } else if name == "page_evaluate" {
                    let expression = arguments["expression"] as! String
                    // Non-input stdio EOF still drains the response, as the bridge contract promises.
                    let value = try await cdp.call("Runtime.evaluate", ["expression": expression, "returnByValue": true, "awaitPromise": true, "timeout": 10000], timeout: 15, cleanup: true)
                    result = try MCPCDP.content(value)
                } else {
                    result = try await page.run(name, arguments: arguments, cdp: cdp)
                }
                completion(result)
            } catch { completion(MCPProtocol.content(error.localizedDescription, failed: true)) }
        }
    }

}

/// Single completion, including asynchronous Chromium replies.
private final class MCPReply: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private(set) var data: Data?
    private var finished = false
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished
    }
    func finish(_ value: Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        data = value
        ready.signal()
    }
}

@MainActor
private final class MCPClientState {
    var requests: [String: MCPReply] = [:]
    static func key(_ id: Any) -> String? {
        if let value = id as? String { return "s:" + value }
        if let value = id as? NSNumber { return "n:" + value.stringValue }
        return nil
    }
}
