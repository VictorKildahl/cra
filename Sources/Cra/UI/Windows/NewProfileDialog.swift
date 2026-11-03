import AppKit
import SwiftUI

/// Arc 1.171's "Create a new Profile" dialog (Set Profile ▸ New Profile…), measured from a 2x
/// capture (1 Nov): a 450 × 426 pt navy card centred on the window, which dims behind it. Next
/// goes on to "Which Spaces should use this Profile?" (3 Nov), with the space it was opened for
/// ticked; Create Profile makes the profile and moves the ticked spaces onto it.
struct NewProfileDialog: View {
    let spaces: [Space]
    let onCreate: (String, Set<UUID>) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var ticked: Set<UUID>
    @State private var choosingSpaces = false
    @FocusState private var focused: Bool

    static let card = Color(hex: "#161C2F")
    static let body = Color(hex: "#B8B9C4")
    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    init(spaces: [Space], ticked: Set<UUID>, onCreate: @escaping (String, Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.spaces = spaces
        self.onCreate = onCreate
        self.onCancel = onCancel
        _ticked = State(initialValue: ticked)
    }

    var body: some View {
        if choosingSpaces {
            ProfileSpacesStep(spaces: spaces, ticked: $ticked, onBack: { choosingSpaces = false }) { onCreate(trimmed, ticked) }
        } else {
            nameStep
        }
    }

    private func next() {
        guard !trimmed.isEmpty else { return }
        if spaces.isEmpty { onCreate(trimmed, []) } else { choosingSpaces = true }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileAvatar().padding(.top, 38.5)
            Text("Create a new Profile")
                .font(.system(size: 17.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 19)
            Text("Profiles make your Spaces truly separate — with their own history, saved passwords, extensions, and other browsing data. No more flipping between work and personal accounts!")
                .font(.system(size: 14))
                .lineSpacing(0.7)
                .foregroundStyle(Self.body)
                .fixedSize(horizontal: false, vertical: true)
                // Arc's text column runs 2.5 pt past the field and buttons.
                .frame(width: 375.5, alignment: .leading)
                .padding(.top, 12)
            Text("What do you want to call this Profile?")
                .font(.system(size: 14))
                .foregroundStyle(Self.body)
                .padding(.top, 20)
            TextField("", text: $name, prompt: Text("Personal").foregroundStyle(Color(hex: "#9699A1")))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(next)
                .padding(.horizontal, 12.5)
                .frame(height: 49)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: "#23293B"), lineWidth: 1))
                .padding(.top, 7)
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 11, weight: .semibold))
                Text("Profiles are ") + Text("not synced").bold() + Text(" between computers.")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color(hex: "#8F929E"))
            .padding(.top, 4)
            HStack(spacing: 8.5) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, primary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Next", key: "↩", enabled: !trimmed.isEmpty, primary: true, action: next)
            }
            .padding(.top, 27)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 38.5)
        .frame(width: 450, height: 426)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }
}

/// Arc's dialog button: a label and its key in a small badge. `.accent` is the vivid blue of
/// Edit Pinned URL's Save (measured 1 Nov); disabled it looks like `.primary`.
struct DialogButton: View {
    enum Style { case secondary, primary, accent }
    let title: String
    let key: String
    let enabled: Bool
    let style: Style
    /// The key badge's size where it was measured (Edit Pinned URL); otherwise it fits the key.
    var badge: CGSize?
    let action: () -> Void

    init(title: String, key: String, enabled: Bool, primary: Bool, action: @escaping () -> Void) {
        self.init(title: title, key: key, enabled: enabled, style: primary ? .primary : .secondary, action: action)
    }

    init(title: String, key: String, enabled: Bool, style: Style, badge: CGSize? = nil, action: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.enabled = enabled
        self.style = style
        self.badge = badge
        self.action = action
    }

    private var accent: Bool { style == .accent && enabled }
    private var primary: Bool { style != .secondary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent ? .white : enabled ? Color(hex: "#EBEBEF") : Color(hex: "#5B5C7F"))
                Text(key).font(.system(size: key == "↩" ? 13 : 11, weight: .bold))
                    .foregroundStyle(accent ? Color(hex: "#EDEDFF") : enabled ? Color(hex: "#B7B7DD") : Color(hex: "#5F6193"))
                    .frame(minWidth: badge?.width ?? 27, maxWidth: badge?.width, minHeight: badge?.height ?? 19, maxHeight: badge?.height)
                    .padding(.horizontal, badge != nil || key == "↩" ? 0 : 2)
                    .background(RoundedRectangle(cornerRadius: badge == nil ? 5 : 3, style: .continuous)
                        .fill(accent ? Color(hex: "#464DFB") : primary ? Color(hex: enabled ? "#4E4C9A" : "#222469") : Color(hex: "#4E4C77")))
                    .overlay(RoundedRectangle(cornerRadius: badge == nil ? 5 : 3, style: .continuous)
                        .strokeBorder(accent ? Color(hex: "#6B71FE") : .clear, lineWidth: 1))
            }
            .padding(.leading, 12.5)
            .padding(.trailing, 12)
            .frame(height: 37)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent ? Color(hex: "#3239FB") : primary ? Color(hex: enabled ? "#3B3C8F" : "#1C1D4C") : Color(hex: "#302F60"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent ? Color(hex: "#5B61FD") : primary ? (enabled ? Color(hex: "#6362A9") : .clear) : Color(hex: "#6362A9"), lineWidth: 1)
            )
            // Arc's Save sits on a darker blue lip, ~1.5 pt below it.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style == .accent ? Color(hex: enabled ? "#2C3475" : "#1D2259") : .clear)
                    .offset(y: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Arc's profile glyph: a lavender smiley in a dashed ring with a green plus badge.
struct ProfileAvatar: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().strokeBorder(Color(hex: "#6262A3").opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 61, height: 61)
                Circle().fill(Color(hex: "#30305D")).frame(width: 54, height: 54)
                Circle().strokeBorder(Color(hex: "#6262A3"), lineWidth: 3).frame(width: 54, height: 54)
                VStack(spacing: 7) {
                    HStack(spacing: 9) {
                        Capsule().fill(Color(hex: "#C4C4DC")).frame(width: 4.5, height: 13)
                        Capsule().fill(Color(hex: "#C4C4DC")).frame(width: 4.5, height: 13)
                    }
                    SmileArc().stroke(Color(hex: "#C4C4DC"), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .frame(width: 26, height: 6)
                }
                .offset(y: 1)
            }
            ZStack {
                Circle().fill(Color(hex: "#5DA642")).frame(width: 17, height: 17)
                Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
            .overlay(Circle().strokeBorder(Color(hex: "#161C2F"), lineWidth: 1.5))
            .offset(x: 1, y: 1)
        }
        .frame(width: 61, height: 61)
    }
}

struct SmileArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        return p
    }
}

/// A borderless window over the main window: Arc's dim plus the dialog, and keys for its field.
final class DialogOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    convenience init<Content: View>(over parent: NSWindow, content: Content) {
        self.init(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        let root = ZStack {
            // Arc darkens the window to about 35% under its dialogs (sampled on 1 Nov).
            Color(white: 0.1).opacity(0.65)
            // One shadow for the card: without the group SwiftUI shadows every text and field on it.
            content.compositingGroup().shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
        contentView = NSHostingView(rootView: root)
    }

    /// Shows a dialog over `parent` (one at a time); `content` gets the closure that dismisses it.
    static func present<Content: View>(over parent: NSWindow, _ content: (@escaping () -> Void) -> Content) {
        guard parent.childWindows?.contains(where: { $0 is DialogOverlayWindow }) != true else { return }
        var overlay: DialogOverlayWindow?
        let close = { [weak parent] in
            guard let o = overlay else { return }
            parent?.removeChildWindow(o)
            o.orderOut(nil)
            overlay = nil
            parent?.makeKey()
        }
        let o = DialogOverlayWindow(over: parent, content: content(close))
        overlay = o
        parent.addChildWindow(o, ordered: .above)
        o.makeKeyAndOrderFront(nil)
    }
}
