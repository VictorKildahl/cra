import SwiftUI

/// Arc 1.171's "Edit Pinned URL" dialog (a pinned tab's or favorite's Edit Pinned URL…),
/// measured from a 2x capture (1 Nov, #54): a 393 × 265 pt navy card over the dimmed window, the
/// saved URL selected in its field. Arc enables Save for any text; Cra only for an address
/// (TypedURL.pinnedDestination), so a search or a script can't become the pinned page.
struct EditPinnedURLDialog: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    private static let card = Color(hex: "#161C2F")
    private static let body = Color(hex: "#B8B9C4")

    init(url: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: url)
    }

    private var destination: String? { TypedURL.pinnedDestination(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Pinned URL")
                .font(.system(size: 17.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 21, alignment: .top)
                .padding(.top, 55)
                .padding(.leading, 37.5)
            Text("This is what opens first when you click this tab or its favicon.")
                .font(.system(size: 14))
                .lineSpacing(0.8)
                .foregroundStyle(Self.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 304, height: 35, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.leading, 37.5)
            TextField("", text: $text, prompt: Text("Enter a URL…").foregroundStyle(Color(hex: "#A6A8B0")))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { if let destination { onSave(destination) } }
                .padding(.horizontal, 8.5)
                .frame(width: 318, height: 37)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color(hex: "#383E4F")))
                .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).strokeBorder(Color(hex: "#737884"), lineWidth: 1))
                .padding(.top, 15.5)
                .padding(.leading, 37.5)
            HStack(spacing: 7) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, style: .secondary, badge: CGSize(width: 35, height: 20), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Save", key: "↩", enabled: destination != nil, style: .accent, badge: CGSize(width: 27, height: 20)) {
                    if let destination { onSave(destination) }
                }
            }
            .padding(.top, 21)
            .padding(.trailing, 28)
            Spacer(minLength: 0)
        }
        .frame(width: 393, height: 265)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }
}
