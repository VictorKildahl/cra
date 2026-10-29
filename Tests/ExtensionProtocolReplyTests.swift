import Foundation

@main
enum ExtensionProtocolReplyTests {
    @MainActor
    static func main() async {
        var completions: [Result<Int, Error>] = []
        var lateReplies = 0
        let timedOut = ExtensionProtocolReply<Int>(method: "Target.attachToTarget", timeout: 0.01,
                                                   onLateReply: { _ in lateReplies += 1 }) { completions.append($0) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        expect(completions.count == 1, "a missing renderer reply completes at the deadline")
        if case let .failure(error)? = completions.first {
            expect((error as? ExtensionProtocolTimeout)?.method == "Target.attachToTarget", "timeout identifies the failed operation")
        } else { fatalError("missing timeout error") }
        timedOut.resolve(.success(42))
        timedOut.resolve(.success(42))
        expect(completions.count == 1, "late or duplicate replies cannot resume a timed-out continuation twice")
        expect(lateReplies == 1, "late attach cleanup runs once")

        var successes = 0
        var unexpectedLate = 0
        let successful = ExtensionProtocolReply<Int>(method: "Runtime.evaluate", timeout: 0.01,
                                                      onLateReply: { _ in unexpectedLate += 1 }) { result in
            if case .success(7) = result { successes += 1 } else { fatalError("successful call timed out") }
        }
        successful.resolve(.success(7))
        try? await Task.sleep(nanoseconds: 80_000_000)
        successful.resolve(.success(7))
        expect(successes == 1, "successful reply cancels its real scheduled deadline")
        expect(unexpectedLate == 0, "a duplicate successful reply does not detach a valid session")
        print("Extension protocol lifecycle: 6 checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
