import Foundation

struct ExtensionProtocolTimeout: Error {
    let method: String
}

/// CEF may never reply after its renderer closes. Bound an asynchronous service call
/// and complete its continuation once; a late attach can still release its session.
/// This main-queue deadline cannot interrupt a synchronous block inside the CEF bridge.
@MainActor
final class ExtensionProtocolReply<Value> {
    private var completion: ((Result<Value, Error>) -> Void)?
    private let onLateReply: ((Result<Value, Error>) -> Void)?
    private var deadline: DispatchWorkItem?
    private var expired = false
    private var handledLateReply = false

    init(method: String, timeout: TimeInterval, onLateReply: ((Result<Value, Error>) -> Void)? = nil,
         completion: @escaping (Result<Value, Error>) -> Void) {
        self.completion = completion
        self.onLateReply = onLateReply
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.completion != nil else { return }
            self.expired = true
            self.resolve(.failure(ExtensionProtocolTimeout(method: method)))
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func resolve(_ result: Result<Value, Error>) {
        guard let completion else {
            if expired, !handledLateReply {
                handledLateReply = true
                onLateReply?(result)
            }
            return
        }
        self.completion = nil
        deadline?.cancel()
        deadline = nil
        completion(result)
    }
}
