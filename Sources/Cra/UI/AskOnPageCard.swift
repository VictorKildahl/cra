import AppKit
import Observation
import SwiftUI

/// The existing native Find or Ask card. The window's service alone owns requests and dialogue.
@MainActor
@Observable
final class AskOnPageState {
    let service: AskOnPageService
    var enabled = false
    var canAsk = false
    /// The card follows its own effective appearance, independently of the space (#408).
    var tone = AskOnPageTone(themeHex: "#DDDDDD")
    var height: CGFloat = AskOnPageMetrics.rowHeight
    var inputHeight: CGFloat = AskOnPageMetrics.rowHeight
    var availableSize = CGSize(width: AskOnPageLayout.maximumWidth, height: CGFloat.greatestFiniteMagnitude)
    var width: CGFloat { min(AskOnPageLayout.maximumWidth, availableSize.width) }
    var conversationHeightLimit: CGFloat {
        AskOnPageLayout.conversationHeight(content: AskOnPageLayout.maximumConversationHeight,
                                          input: inputHeight, available: availableSize.height)
    }

    init(service: AskOnPageService) { self.service = service }
    var inConversation: Bool { !service.messages.isEmpty || service.current != nil }
}

enum AskOnPageMetrics {
    static let rowHeight: CGFloat = 48
    static let radius: CGFloat = 10
}

/// One window's existing card and Find callbacks, backed by exactly one guided service.
@MainActor
final class AskOnPageController {
    let state: AskOnPageState
    let service: AskOnPageService
    private let overlay: OverlayState
    var onFind: (String, Bool) -> Void = { _, _ in }
    var onClose: () -> Void = {}
    var canAskFromFind: (String, Bool) -> Bool = { _, _ in false }
    var onResize: () -> Void = {}
    private(set) lazy var view: NSView = makeView()

    init(overlay: OverlayState, service: AskOnPageService) {
        self.overlay = overlay
        self.service = service
        state = AskOnPageState(service: service)
    }

    var size: NSSize { NSSize(width: state.width, height: min(state.height, state.availableSize.height)) }
    func constrain(to available: CGSize) {
        let size = CGSize(width: max(0, available.width), height: max(0, available.height))
        if state.availableSize != size { state.availableSize = size }
    }
    func setTone(themeHex: String) { state.tone = AskOnPageTone(themeHex: themeHex) }

    private func makeView() -> NSView {
        let container = NSView()
        let card = MaterialCardView(radius: AskOnPageMetrics.radius)
        card.autoresizingMask = [.width, .height]
        container.addSubview(card)
        let host = NSHostingView(rootView: AskOnPageView(state: state, overlay: overlay, controller: self))
        host.autoresizingMask = [.width, .height]
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

    func submit(shift: Bool) {
        service.refresh()
        switch AskOnPagePolicy.returnKey(query: overlay.findQuery,
            finalZero: canAskFromFind(overlay.findQuery, !shift), inConversation: state.inConversation,
            canAsk: state.enabled && state.canAsk, forward: !shift) {
        case .nextMatch?: onFind(overlay.findQuery, !shift)
        case .ask?: ask(overlay.findQuery)
        case nil: break
        }
    }

    func pageChanged(canAsk: Bool) {
        service.refresh()
        state.canAsk = canAsk
    }

    func ask(_ raw: String) {
        guard state.enabled, state.canAsk else { return }
        let code = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        let language = Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
        guard service.ask(raw.trimmingCharacters(in: .whitespacesAndNewlines), language: language) else { return }
        overlay.findQuery = ""
        onFind("", true)
    }

    func findQuote(messageID: UUID, index: Int) {
        guard state.enabled, state.canAsk else { return }
        service.findQuote(messageID: messageID, index: index)
    }

    var findsWhileTyping: Bool { !state.enabled || !state.inConversation }
    func reset() { service.clear() }

    func restoreFailedQuestion() {
        if case .failed = service.phase, overlay.findQuery.isEmpty { overlay.findQuery = service.current?.question ?? "" }
    }

    /// The existing debug action addresses a native completed citation, without a markup parser.
    func debugFindQuote(_ n: Int) {
        guard let message = service.messages.last else { return }
        findQuote(messageID: message.id, index: n - 1)
    }

    /// cra://debug?askTone=<label>: the card's appearance (its own, as SwiftUI sees it), the question's
    /// colour on it with their contrast, and the Ask button's against its white text (#408).
    func toneReadout(_ label: String) -> String {
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let card = AskOnPageTone.card(dark: dark)
        let q = state.tone.question(dark: dark), b = state.tone.button
        func hex(_ c: AskOnPageTone.RGB) -> String {
            String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        }
        return String(format: "ask tone %@: card=%@ question=%@ contrast=%.1f button=%@ white=%.1f", label,
                      dark ? "dark" : "light", hex(q), AskOnPageTone.contrast(q, (card, card, card)),
                      hex(b), AskOnPageTone.contrast(b, (1, 1, 1)))
    }

    /// Counts/status only. Debug output must not retain real page/question/answer text.
    func readout(_ label: String) -> String {
        let messages = service.messages.count + (service.current == nil ? 0 : 1)
        guard let last = service.current ?? service.messages.last else {
            return "ask \(label): enabled=\(state.enabled) canAsk=\(state.canAsk) messages=0"
        }
        let quotes = last.answer?.quotes.count ?? 0
        let line = AskOnPagePrompt.fractionLine(last.fractionRead) ?? "-"
        let search = service.quoteNavigation.map { $0.status.rawValue } ?? ""
        return "ask \(label): enabled=\(state.enabled) canAsk=\(state.canAsk) messages=\(messages) finished=\(last.answer?.isComplete == true) quotes=\(quotes) read=\(line) search=[\(search)] height=\(Int(state.height))"
    }
}

/// Arc uses a native field editor. Focus tokens select all once; ordinary updates preserve selection.
@MainActor
final class AskOnPageTextField: NSTextField, NSTextFieldDelegate {
    private let overlay: OverlayState
    private weak var controller: AskOnPageController?
    private var appliedFocusToken: Int?
    private var scheduledFocusToken: Int?

    init(overlay: OverlayState, controller: AskOnPageController?) {
        self.overlay = overlay; self.controller = controller
        super.init(frame: .zero)
        isBordered = false; isBezeled = false; drawsBackground = false
        focusRingType = .none; usesSingleLineMode = true
        cell?.wraps = false; cell?.isScrollable = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        delegate = self
        setAccessibilityIdentifier("askOnPageInput")
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(query: String, placeholder: String, fontSize: CGFloat, focusToken: Int, visible: Bool) {
        if stringValue != query { stringValue = query }
        font = .systemFont(ofSize: fontSize, weight: .medium)
        placeholderString = placeholder
        setAccessibilityLabel(placeholder)
        if visible { requestFocus(token: focusToken) }
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); requestFocus(token: overlay.findFocusToken) }

    private func requestFocus(token: Int) {
        guard overlay.findVisible, appliedFocusToken != token, scheduledFocusToken != token else { return }
        scheduledFocusToken = token
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.scheduledFocusToken == token { self.scheduledFocusToken = nil }
            guard self.overlay.findVisible, self.overlay.findFocusToken == token,
                  self.controller?.state.enabled == true, !self.isHiddenOrHasHiddenAncestor,
                  let window = self.window else { return }
            var editor = self.currentEditor()
            if editor == nil || window.firstResponder !== editor {
                guard window.makeFirstResponder(self) else { return }
                editor = self.currentEditor()
            }
            guard let editor else { return }
            editor.selectAll(nil)
            self.appliedFocusToken = token
        }
    }

    func controlTextDidChange(_ obj: Notification) { overlay.findQuery = stringValue }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        performCommand(selector, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
    }

    /// The native delegate supplies selectors and actual event modifiers; unrelated editor commands stay native.
    func performCommand(_ selector: Selector, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard overlay.findVisible, let controller else { return false }
        let modifiers = modifiers.intersection([.shift, .control, .option, .command])
        switch selector {
        case #selector(NSResponder.moveDown(_:)) where modifiers.isEmpty:
            controller.onFind(overlay.findQuery, true)
        case #selector(NSResponder.moveUp(_:)) where modifiers.isEmpty:
            controller.onFind(overlay.findQuery, false)
        case #selector(NSResponder.insertNewline(_:)) where modifiers.isEmpty:
            controller.submit(shift: false)
        case #selector(NSResponder.insertNewline(_:)) where modifiers == .shift:
            controller.onFind(overlay.findQuery, false)
        case #selector(NSResponder.insertLineBreak(_:)) where modifiers == .shift,
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) where modifiers == .shift:
            controller.onFind(overlay.findQuery, false)
        case #selector(NSResponder.cancelOperation(_:)):
            controller.onClose()
        default: return false
        }
        return true
    }
}

/// Value inputs are captured during SwiftUI body evaluation, including explicit Cmd-F focus requests.
struct AskOnPageInput: NSViewRepresentable {
    let overlay: OverlayState
    weak var controller: AskOnPageController?
    let query: String
    let placeholder: String
    let fontSize: CGFloat
    let focusToken: Int
    let visible: Bool

    init(state: AskOnPageState, overlay: OverlayState, controller: AskOnPageController?) {
        self.overlay = overlay; self.controller = controller
        query = overlay.findQuery; focusToken = overlay.findFocusToken; visible = overlay.findVisible
        fontSize = state.inConversation ? 14 : 16
        placeholder = AskOnPagePolicy.placeholder(canAsk: state.canAsk, inConversation: state.inConversation)
    }
    func makeNSView(context: Context) -> AskOnPageTextField { AskOnPageTextField(overlay: overlay, controller: controller) }
    func updateNSView(_ field: AskOnPageTextField, context: Context) { update(field) }
    func update(_ field: AskOnPageTextField) {
        field.update(query: query, placeholder: placeholder, fontSize: fontSize, focusToken: focusToken, visible: visible)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AskOnPageTextField, context: Context) -> CGSize? {
        CGSize(width: max(0, proposal.width ?? 0), height: ceil(nsView.intrinsicContentSize.height))
    }
}

// MARK: - The card

struct AskOnPageView: View {
    @Bindable var state: AskOnPageState
    @Bindable var overlay: OverlayState
    weak var controller: AskOnPageController?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closeHovered = false

    var body: some View {
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.1)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if state.inConversation {
                    AskOnPageConversation(state: state, controller: controller)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(spring, value: state.service.current?.id ?? state.service.messages.last?.id)
            .animation(spring, value: state.service.current?.answer)
            inputRow
        }
        .frame(width: state.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controller?.heightChanged($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        // Arc's card is nearly opaque (the reporter's capture): the material only shows at its edge.
        .background(RoundedRectangle(cornerRadius: AskOnPageMetrics.radius, style: .continuous)
            .fill(Color(white: AskOnPageTone.card(dark: scheme == .dark)).opacity(scheme == .dark ? 0.96 : 0.97)))
        .overlay(alignment: .topTrailing) {
            if state.inConversation { closeButton.padding([.top, .trailing], 9) }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: state.inConversation)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onChange(of: state.service.phase) { controller?.restoreFailedQuestion() }
        .onExitCommand { controller?.onClose() }
    }

    /// The native baseline row includes Find controls; only conversation input gets an inset band.
    private var inputRow: some View {
        let font = NSFont.systemFont(ofSize: state.inConversation ? 14 : 16, weight: .medium)
        let ascent = font.ascender, descent = font.descender
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            AskOnPageInput(state: state, overlay: overlay, controller: controller)
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    (dimensions.height - ascent + descent) / 2 + ascent
                }
            findControls
            if !state.inConversation {
                iconButton("xmark", label: "Close") { controller?.onClose() }
            }
        }
        .padding(12).padding(.leading, 6)
        .background {
            if state.inConversation {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)).padding(6)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.inputHeight = $0 }
    }

    @ViewBuilder private var findControls: some View {
            if !state.inConversation, !overlay.findQuery.isEmpty, let matches = overlay.findMatchCount {
                let countLabel = matches == 0 ? "No matches" : "\(overlay.findActiveMatch)/\(matches)"
                Text(countLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle).layoutPriority(-1)
                    .help(countLabel).accessibilityLabel(countLabel)
                if matches > 0 {
                    iconButton("arrow.up", label: "Previous") { controller?.onFind(overlay.findQuery, false) }
                    iconButton("arrow.down", label: "Next") { controller?.onFind(overlay.findQuery, true) }
                }
            }
            // Arc shows Ask with the field still empty (the reporter's capture); it asks once there is text.
            if state.canAsk {
                let ready = AskOnPagePolicy.showsAskButton(query: overlay.findQuery, canAsk: state.canAsk)
                Button { if ready { controller?.ask(overlay.findQuery) } } label: {
                    Text("Ask").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(state.tone.button)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("askOnPageAsk")
                .accessibilityLabel("Submit")
            }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary.opacity(0.45))
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Arc's close button: a plain ✕ on the card; its material square shows under the pointer.
    private var closeButton: some View {
        Button { controller?.onClose() } label: {
            Image(systemName: "xmark").font(.system(size: 12, weight: .regular)).foregroundStyle(.primary.opacity(0.5))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial).opacity(closeHovered ? 1 : 0))
        }
        .buttonStyle(.plain)
        .onHover { closeHovered = $0 }
        .accessibilityLabel("Close")
    }
}

/// The questions and answers, scrolling past 450 pt, newest in view.
private struct AskOnPageConversation: View {
    @Bindable var state: AskOnPageState
    weak var controller: AskOnPageController?
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(state.service.messages) { message in
                        AskOnPageMessageView(message: message, state: state, controller: controller).id(message.id)
                    }
                    if let message = state.service.current {
                        AskOnPageMessageView(message: message, state: state, controller: controller).id(message.id)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 17).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(contentHeight, 1), state.conversationHeightLimit))
            .mask(fades)
            .onChange(of: state.service.current?.id ?? state.service.messages.last?.id) {
                if let last = state.service.current ?? state.service.messages.last {
                    if reduceMotion { proxy.scrollTo(last.id, anchor: .top) }
                    else { withAnimation(.default) { proxy.scrollTo(last.id, anchor: .top) } }
                }
            }
        }
    }

    /// Arc's fades where the conversation scrolls under its edges.
    private var fades: some View {
        let scrolls = contentHeight > state.conversationHeightLimit
        return LinearGradient(stops: scrolls ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                                .init(color: .black, location: 0.9), .init(color: .clear, location: 1)]
                                             : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }
}

private struct AskOnPageMessageView: View {
    let message: AskOnPageService.Message
    @Bindable var state: AskOnPageState
    weak var controller: AskOnPageController?
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message.question).font(.body.bold()).foregroundStyle(Color(state.tone.question(dark: scheme == .dark)))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 24)
                .textSelection(.enabled)
            if let line = AskOnPagePrompt.fractionLine(message.fractionRead) {
                Text(line).font(.subheadline.bold()).foregroundStyle(.primary.opacity(0.5))
            } else if message.isPartialPage {
                Text("This page was long, so I read part of it.").font(.subheadline.bold()).foregroundStyle(.primary.opacity(0.5))
            }
            if message.olderMessagesHidden {
                Text("[Older messages hidden]").font(.subheadline).foregroundStyle(.secondary)
            }
            if let answer = message.answer {
                ForEach(Array(answer.quotes.enumerated()), id: \.offset) { index, quote in
                    AskOnPageQuote(quote: quote, finished: answer.isComplete,
                        status: state.service.quoteNavigation.flatMap { $0.messageID == message.id && $0.index == index ? $0.status : nil }) {
                        controller?.findQuote(messageID: message.id, index: index)
                    }
                }
                answerText(answer).font(.body).foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else if state.service.isLoading {
                Text("Loading Content").font(.body).redacted(reason: .placeholder)
                    .opacity(reduceMotion ? 1 : (pulse ? 0.4 : 1))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = !reduceMotion }
                    .onChange(of: reduceMotion) { pulse = !reduceMotion }
            }
            if state.service.current?.id == message.id, let failure = state.service.failureText {
                Text(failure).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answerText(_ answer: AskOnPage.Answer) -> Text {
        guard let key = answer.keyAnswer, !key.isEmpty,
              let range = answer.text.range(of: key, options: .literal) else { return Text(answer.text) }
        let prefix = Text(String(answer.text[..<range.lowerBound]))
        let emphasis = Text(String(answer.text[range])).bold()
        let suffix = Text(String(answer.text[range.upperBound...]))
        return Text("\(prefix)\(emphasis)\(suffix)")
    }
}

/// Literal native source text on the existing 2 pt rule; provisional/absent text cannot navigate.
private struct AskOnPageQuote: View {
    let quote: AskOnPage.Quote
    let finished: Bool
    let status: AskOnPageService.QuoteStatus?
    let find: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(quote.text).font(.body).foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if finished {
                    if quote.state == .notFound || status == .notFound {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Quote not found. Make sure it’s accurate!")
                        }
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
                        .padding(.top, 4)
                    } else if quote.state == .verified {
                        Button(action: find) {
                            HStack(spacing: 4) {
                                if status == .loading { ProgressView().controlSize(.mini) }
                                Text("Find on Page")
                                Image(systemName: "arrow.forward").offset(x: hovered && !reduceMotion ? 4 : 0)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary.opacity(hovered ? 0.8 : 0.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .onHover { h in
                            if reduceMotion { hovered = h }
                            else { withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)) { hovered = h } }
                        }
                        .accessibilityIdentifier("askOnPageFindQuote")
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Color {
    init(_ c: AskOnPageTone.RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b) }
}
