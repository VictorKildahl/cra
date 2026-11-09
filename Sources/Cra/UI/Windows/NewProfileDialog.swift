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

    static let card = DialogTheme.card
    static let body = DialogTheme.body
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
        .modifier(DialogSurface())
        .onAppear { focused = true }
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
            .overlay(Circle().strokeBorder(DialogTheme.card, lineWidth: 1.5))
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
