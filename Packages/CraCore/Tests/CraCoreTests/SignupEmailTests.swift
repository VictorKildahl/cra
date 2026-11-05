import CraCore
import Testing

struct SignupEmailTests {
    @Test func explicitEmailNeedsSignupAndAnAppropriateField() {
        let ordinary = "type: text\nid: register_email\nplaceholder: email example"
        #expect(SignupEmail.field(hints: ordinary, signup: true) == .email)
        #expect(SignupEmail.field(hints: ordinary, signup: false) == .skip)
        #expect(SignupEmail.field(hints: "type: text\nautocomplete: email", signup: true) == .email)
        for hints in ["type: text\nname: emailVerificationCode", "type: email\nlabel: Friend’s email", "type: password\nid: email", "type: text\nautocomplete: one-time-code", "type: text\nlabel: First name", "type: text\nlabel: Username"] {
            #expect(SignupEmail.field(hints: hints, signup: true) == .skip)
        }
    }

    @Test func classifierReceivesOnlyAllowedSanitizedLabelMetadata() {
        let hints = "type: text\nlabel: Courriel\nid: identity\nvalue: private-value\nplaceholder: contact@somewhere.org 610083 https://private.example/a?secret=1"
        #expect(SignupEmail.field(hints: hints, signup: true) == .askModel("label: courriel"))
        #expect(SignupEmail.field(hints: "type: text\nvalue: user@example.org", signup: true) == .skip)
    }

    @Test func preferredAddressesKeepAliasesAndRejectInvalidInput() {
        #expect(SignupEmail.address("  alex+shop@my.example\n") == "alex+shop@my.example")
        for address in ["a@@example.org", "@", "hello world@example.org", "a@bad..domain", "x@\ny.com", "a@-example.com"] {
            #expect(SignupEmail.address(address) == nil)
        }
    }
}
