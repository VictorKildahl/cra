import AppKit
import SwiftUI

/// Arc 1.171's "Create a new Profile" dialog (Set Profile ▸ New Profile…), measured from a 2x
/// capture (1 Nov): a 450 × 426 pt navy card centred on the window, which dims behind it.
struct NewProfileDialog: View {
    let onCreate: (String) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private static let card = Color(hex: "#161C2F")
    private static let body = Color(hex: "#B8B9C4")
    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
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
                .onSubmit { if !trimmed.isEmpty { onCreate(trimmed) } }
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
                DialogButton(title: "Next", key: "↩", enabled: !trimmed.isEmpty, primary: true) { onCreate(trimmed) }
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

/// Arc's dialog button: a label and its key in a small badge.
private struct DialogButton: View {
    let title: String
    let key: String
    let enabled: Bool
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? Color(hex: "#EBEBEF") : Color(hex: "#5B5C7F"))
                Text(key).font(.system(size: key == "↩" ? 13 : 11, weight: .bold))
                    .foregroundStyle(enabled ? Color(hex: "#B7B7DD") : Color(hex: "#5F6193"))
                    .frame(minWidth: 27, minHeight: 19)
                    .padding(.horizontal, key == "↩" ? 0 : 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(primary ? Color(hex: enabled ? "#4E4C9A" : "#222469") : Color(hex: "#4E4C77")))
            }
            .padding(.leading, 12.5)
            .padding(.trailing, 12)
            .frame(height: 37)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? Color(hex: enabled ? "#3B3C8F" : "#1C1D4C") : Color(hex: "#302F60"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(primary ? (enabled ? Color(hex: "#6362A9") : .clear) : Color(hex: "#6362A9"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Arc's profile glyph: a lavender smiley in a dashed ring with a green plus badge.
private struct ProfileAvatar: View {
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

private struct SmileArc: Shape {
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
            content.shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
        contentView = NSHostingView(rootView: root)
    }
}
