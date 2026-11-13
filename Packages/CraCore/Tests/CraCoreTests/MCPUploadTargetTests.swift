import CraCore
import Testing

struct MCPUploadTargetTests {
    typealias Around = MCPUploadTarget.Surroundings

    @Test func theInputItselfAndItsLabel() {
        #expect(MCPUploadTarget.choose(Around(isFileInput: true)) == .itself)
        // A file input inside a component with others is still exactly what was asked for.
        #expect(MCPUploadTarget.choose(Around(isFileInput: true, components: [3])) == .itself)
        // A label picks its own control even when its shadow root holds another input.
        #expect(MCPUploadTarget.choose(Around(labelsFileInput: true, components: [2])) == .label)
        #expect(MCPUploadTarget.choose(Around(labelsFileInput: true)).via == "label")
    }

    /// reddit.com's settings-dropzone: the button and the hidden input share a shadow root.
    @Test func aButtonInTheInputsShadowRoot() {
        #expect(MCPUploadTarget.choose(Around(components: [1, 1])) == .component(0))
        // A dropzone nested in a component (settings-avatar-image-upload) with no input of its own.
        #expect(MCPUploadTarget.choose(Around(components: [0, 1])) == .component(1))
        // The nearest component decides; an outer one with more inputs doesn't make it ambiguous.
        #expect(MCPUploadTarget.choose(Around(components: [1, 4])) == .component(0))
        #expect(MCPUploadTarget.choose(Around(components: [0, 1])).via == "component")
    }

    @Test func aHostOrDropZoneHoldingTheInput() {
        #expect(MCPUploadTarget.choose(Around(inside: 1)) == .inside)
        #expect(MCPUploadTarget.choose(Around(inside: 1, components: [5])) == .inside)
        guard case .refused(let message) = MCPUploadTarget.choose(Around(inside: 2, components: [1])) else {
            Issue.record("Two inputs inside the target must be refused"); return
        }
        #expect(message.contains("2 file inputs"))
    }

    @Test func neverAGuess() {
        // Plain DOM: nothing inside, no component around. A page's only file input elsewhere doesn't count.
        guard case .refused(let none) = MCPUploadTarget.choose(Around()) else { Issue.record("Nothing to upload into"); return }
        #expect(none.contains("No file input"))
        // Two inputs behind one button.
        guard case .refused(let two) = MCPUploadTarget.choose(Around(components: [0, 2, 1])) else {
            Issue.record("Two inputs in the nearest component must be refused"); return
        }
        #expect(two.contains("2 file inputs"))
        // A text field (or its label) in a component that holds an uploader is not that uploader.
        guard case .refused(let field) = MCPUploadTarget.choose(Around(isOtherField: true, components: [1])) else {
            Issue.record("A text field is never an uploader"); return
        }
        #expect(field.contains("form field"))
        #expect(MCPUploadTarget.choose(Around(isOtherField: true)).via == nil)
    }
}
