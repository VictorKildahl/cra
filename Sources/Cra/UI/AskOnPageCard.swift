import AppKit
import CraCEF
import Observation
import SwiftUI

/// Arc Max's Ask on Page (AskInPageView): with the setting on, ⌘F's bar is this card. Typing finds
/// on the page as the plain bar does; Ask (or Return once the text isn't on the page) asks the Mac's
/// Apple Intelligence model about the page, and the card grows into the conversation over the row.
/// Arc's numbers (docs/arc-reverse-engineering.md, "Ask on Page"): 400 pt wide, the conversation
/// at most 450 tall, the close button 18 pt, 9 from the top and trailing edges, quotes on a 2 pt
/// rule with "Find on Page →" under them.
@MainActor
@Observable
final class AskOnPageState {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var reply = ""
        var fractionRead: Double?
        var finished = false
    }

    enum QuoteSearch: Equatable { case loading, found, notFound }

    /// The setting is on and the model can run: the card replaces the plain find bar.
    var enabled = false
    /// The page is one the model can be asked about (Arc's isValidAskPage).
    var canAsk = false
    var messages: [Message] = []
    var quotes: [String: QuoteSearch] = [:]
    /// The space's colour for the question and the Ask button.
    var accent = Color(.sRGB, red: 0.22, green: 0.24, blue: 1)
    /// The card's height as laid out, which its panel follows.
    var height: CGFloat = AskOnPageMetrics.rowHeight

    var inConversation: Bool { !messages.isEmpty }
}

enum AskOnPageMetrics {
    static let width: CGFloat = 400
    static let conversationMaxHeight: CGFloat = 450
    static let rowHeight: CGFloat = 52
    static let radius: CGFloat = 10
}

/// One window's card: its state, the find bar it stands in for, and the model's answers.
@MainActor
final class AskOnPageController {
    let state = AskOnPageState()
    private let overlay: OverlayState
    /// The find bar's own actions: find (query, forward), close.
    var onFind: (String, Bool) -> Void = { _, _ in }
    var onClose: () -> Void = {}
    /// The page asked about: the focused tab's browser.
    var browser: () -> CraBrowser? = { nil }
    /// The card's size changed: its panel follows.
    var onResize: () -> Void = {}

    private(set) lazy var view: NSView = makeView()
    private var asking: Task<Void, Never>?
    /// The page the conversation is about (tab and address); another page ends it.
    private var subject: (tab: UUID, url: String)?
    /// The page in front, as pageChanged last heard.
    private var current: (tab: UUID, url: String)?
    private var pendingQuote: String?
    private var quoteTimeout: DispatchWorkItem?

    init(overlay: OverlayState) {
        self.overlay = overlay
    }

    var size: NSSize { NSSize(width: AskOnPageMetrics.width, height: state.height) }

    func setAccent(_ c: (r: Double, g: Double, b: Double)) {
        state.accent = Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    private func makeView() -> NSView {
        let container = NSView()
        let card = MaterialCardView(radius: AskOnPageMetrics.radius)
        card.autoresizingMask = [.width, .height]
        container.addSubview(card)
        let host = NSHostingView(rootView: AskOnPageView(state: state, overlay: overlay, controller: self))
        host.autoresizingMask = [.width, .height]
        // The panel sizes the card; SwiftUI only says how tall it wants to be.
        host.sizingOptions = []
        container.addSubview(host)
        container.wantsLayer = true
        return container
    }

    func heightChanged(_ h: CGFloat) {
        let h = ceil(h)
        guard abs(h - state.height) >= 0.5 else { return }
        state.height = h
        onResize()
    }

    /// Return in the field.
    func submit(shift: Bool) {
        // A count for other text (the page hasn't answered for this yet) says nothing about it.
        let matches = overlay.findCountText == overlay.findQuery ? overlay.findMatchCount : nil
        switch AskOnPagePolicy.returnKey(query: overlay.findQuery, matches: matches,
                                         inConversation: state.inConversation, canAsk: state.canAsk) {
        case .nextMatch?: onFind(overlay.findQuery, !shift)
        case .ask?: ask(overlay.findQuery)
        case nil: break
        }
    }

    /// The page in front changed (tab, address): a conversation about another page ends.
    func pageChanged(tab: UUID?, url: URL?) {
        state.canAsk = AskOnPagePolicy.canAsk(page: url)
        current = tab.map { ($0, url?.absoluteString ?? "") }
        guard let subject, subject.tab != tab || subject.url != (url?.absoluteString ?? "") else { return }
        CraLog.note("Ask on Page: another page, the conversation ends")
        reset()
    }

    func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, state.canAsk, let browser = browser() else { return }
        if subject == nil { subject = current }
        let turns = state.messages.filter(\.finished).map { AskOnPagePrompt.Turn(question: $0.question, answer: $0.reply) }
        asking?.cancel()
        state.messages.append(.init(question: question))
        let id = state.messages[state.messages.count - 1].id
        // The field asks the next question; the page's find marks go.
        overlay.findQuery = ""
        onFind("", true)
        CraLog.note("Ask on Page: asked (\(state.messages.count) in the conversation)")
        asking = Task { @MainActor [weak self] in
            let service = AskOnPageService.shared
            guard let page = await service.read(browser) else {
                self?.update(id) { $0.reply = AskOnPagePrompt.unreadable; $0.finished = true }
                return
            }
            let final = await service.answer(question: question, turns: turns, page: page) { reply, fraction in
                self?.update(id) { $0.reply = reply; $0.fractionRead = fraction }
            }
            guard !Task.isCancelled, let final else { return }
            self?.update(id) { $0.reply = final; $0.finished = true }
        }
    }

    private func update(_ id: UUID, _ change: (inout AskOnPageState.Message) -> Void) {
        guard let i = state.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&state.messages[i])
    }

    /// What Find on Page still has to try for the pending quote.
    private var quoteCandidates: [String] = []

    /// Find on Page: the page's own find runs on the quote (then its first sentence, then its first
    /// words); the card says when none of them is there.
    func findQuote(_ quote: String) {
        let candidates = AskOnPageReply.findCandidates(quote)
        guard !candidates.isEmpty else { return }
        state.quotes[quote] = .loading
        pendingQuote = quote
        quoteCandidates = candidates
        tryNextCandidate()
    }

    private func tryNextCandidate() {
        guard let quote = pendingQuote, !quoteCandidates.isEmpty else { return }
        let text = quoteCandidates.removeFirst()
        quoteTimeout?.cancel()
        onFind(text, true)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingQuote == quote else { return }
            self.notFound(quote)
        }
        quoteTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timeout)
    }

    private func notFound(_ quote: String) {
        if !quoteCandidates.isEmpty { tryNextCandidate(); return }
        state.quotes[quote] = .notFound
        pendingQuote = nil
        quoteTimeout?.cancel()
        CraLog.note("Ask on Page: quote not found")
    }

    /// The page's find answered: a quote being looked for is found, or the next try runs.
    func matchesUpdated(count: Int) {
        guard let quote = pendingQuote, count >= 0 else { return }
        if count > 0 {
            state.quotes[quote] = .found
            pendingQuote = nil
            quoteCandidates = []
            quoteTimeout?.cancel()
            CraLog.note("Ask on Page: quote found (\(count))")
        } else {
            notFound(quote)
        }
    }

    /// Typing in the field finds, unless the card is in a conversation (then it only asks).
    var findsWhileTyping: Bool { !state.enabled || !state.inConversation }

    /// The card closed: Arc starts again from the find bar.
    func reset() {
        asking?.cancel()
        asking = nil
        subject = nil
        pendingQuote = nil
        quoteCandidates = []
        quoteTimeout?.cancel()
        state.messages = []
        state.quotes = [:]
    }

    /// cra://debug?askFindQuote=<n>: Find on Page under the last answer's nth quote (from 1).
    func debugFindQuote(_ n: Int) {
        let quotes = AskOnPageReply.parts(state.messages.last?.reply ?? "").filter(\.isQuote)
        guard n >= 1, n <= quotes.count else { return }
        findQuote(quotes[n - 1].text)
    }

    /// cra://debug readout: messages, the last reply's parts and the read line.
    func readout(_ label: String) -> String {
        guard let last = state.messages.last else { return "ask \(label): enabled=\(state.enabled) canAsk=\(state.canAsk) messages=0" }
        let parts = AskOnPageReply.parts(last.reply)
        let quotes = parts.filter(\.isQuote).count
        let line = AskOnPagePrompt.fractionLine(last.fractionRead) ?? "-"
        let found = state.quotes.values.map { "\($0)" }.sorted().joined(separator: ",")
        let first = parts.first(where: \.isQuote).map { String($0.text.prefix(40)) } ?? "-"
        return "ask \(label): enabled=\(state.enabled) canAsk=\(state.canAsk) messages=\(state.messages.count) finished=\(last.finished) quotes=\(quotes) read=\(line) search=[\(found)] quote=\"\(first)\" height=\(Int(state.height))"
    }
}

// MARK: - The card

struct AskOnPageView: View {
    @Bindable var state: AskOnPageState
    @Bindable var overlay: OverlayState
    let controller: AskOnPageController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.inConversation {
                AskOnPageConversation(state: state, controller: controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            inputRow
        }
        .frame(width: AskOnPageMetrics.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controller.heightChanged($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            if state.inConversation { closeButton.padding([.top, .trailing], 9) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.1), value: state.inConversation)
        .onAppear { fieldFocused = true }
        .onChange(of: overlay.findFocusToken) { fieldFocused = true }
        .onChange(of: overlay.findVisible) { _, visible in if visible { fieldFocused = true } }
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(AskOnPagePolicy.placeholder(canAsk: state.canAsk, inConversation: state.inConversation), text: $overlay.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .onSubmit { controller.submit(shift: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) }
                .onExitCommand { controller.onClose() }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            if !state.inConversation, !overlay.findQuery.isEmpty, let matches = overlay.findMatchCount {
                Text(matches == 0 ? "No matches" : "\(overlay.findActiveMatch)/\(matches)")
                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.5))
                    .fixedSize()
                if matches > 0 {
                    iconButton("arrow.up", label: "Previous") { controller.onFind(overlay.findQuery, false) }
                    iconButton("arrow.down", label: "Next") { controller.onFind(overlay.findQuery, true) }
                }
            }
            if AskOnPagePolicy.showsAskButton(query: overlay.findQuery, canAsk: state.canAsk) {
                Button { controller.ask(overlay.findQuery) } label: {
                    Text("Ask").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .padding(.vertical, 4).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(state.accent))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("askOnPageAsk")
            }
            if !state.inConversation {
                iconButton("xmark", label: "Close") { controller.onClose() }
            }
        }
        .padding(12)
        .frame(minHeight: AskOnPageMetrics.rowHeight)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary.opacity(0.45))
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var closeButton: some View {
        Button { controller.onClose() } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.primary.opacity(0.45))
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// The questions and answers, scrolling past 450 pt, newest in view.
private struct AskOnPageConversation: View {
    @Bindable var state: AskOnPageState
    let controller: AskOnPageController
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(state.messages) { message in
                        AskOnPageMessageView(message: message, state: state, controller: controller).id(message.id)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(contentHeight, 1), AskOnPageMetrics.conversationMaxHeight))
            .mask(fades)
            .onChange(of: state.messages.count) {
                if let last = state.messages.last { withAnimation(.default) { proxy.scrollTo(last.id, anchor: .top) } }
            }
        }
    }

    /// Arc's fades where the conversation scrolls under its edges.
    private var fades: some View {
        let scrolls = contentHeight > AskOnPageMetrics.conversationMaxHeight
        return LinearGradient(stops: scrolls ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                                .init(color: .black, location: 0.9), .init(color: .clear, location: 1)]
                                             : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }
}

private struct AskOnPageMessageView: View {
    let message: AskOnPageState.Message
    @Bindable var state: AskOnPageState
    let controller: AskOnPageController
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.question).font(.body.bold()).foregroundStyle(state.accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 24)
                .textSelection(.enabled)
            if let line = AskOnPagePrompt.fractionLine(message.fractionRead) {
                Text(line).font(.subheadline.bold()).foregroundStyle(.primary.opacity(0.5))
            }
            let parts = AskOnPageReply.parts(message.reply)
            if parts.isEmpty, !message.finished {
                Text("Loading Content").font(.body).redacted(reason: .placeholder)
                    .opacity(pulse ? 0.4 : 1)
                    .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
            }
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isQuote {
                    AskOnPageQuote(quote: part.text, search: state.quotes[part.text], finished: message.finished) { controller.findQuote(part.text) }
                } else {
                    Text(Self.markdown(part.text)).font(.body).foregroundStyle(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A quote from the page on Arc's 2 pt rule, with Find on Page under it.
private struct AskOnPageQuote: View {
    let quote: String
    let search: AskOnPageState.QuoteSearch?
    let finished: Bool
    let find: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(AskOnPageMessageView.markdown(quote)).font(.body).foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if finished {
                    if search == .notFound {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Quote not found. Make sure it’s accurate!")
                        }
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.primary.opacity(0.5))
                        .padding(.top, 4)
                    } else {
                        Button(action: find) {
                            HStack(spacing: 4) {
                                Text("Find on Page")
                                Image(systemName: "arrow.forward")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary.opacity(hovered ? 0.8 : 0.5))
                            .opacity(search == .loading ? 0.5 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .onHover { h in withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)) { hovered = h } }
                        .accessibilityIdentifier("askOnPageFindQuote")
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
