import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The production typed adapter, compiled with the installed Foundation Models SDK and no CEF.
@main @MainActor
enum TidyTabsModelTests {
    private static var checks = 0

    static func main() async throws {
        let tabs = (0..<8).map { TidyTabs.Tab(id: UUID(), title: "Tab \($0)", host: "example.org") }
        let initial = TidyTabs.request(tabs: tabs, existingGroups: [], maximumBytes: TidyTabs.maximumPromptBytes)!
        var calls = 0
        let answer = try await TidyTabsModel.group(initial) { request in
            calls += 1
            if calls == 1 { throw TidyTabsModel.Failure.contextLimit(request) }
            return .init(request: request, proposals: [.init(name: "Kept", tabs: [0, 1, 999])])
        }
        let plan = answer.request.plan(answer.proposals)
        check(calls == 2 && answer.request.tabIDs == Array(initial.tabIDs.prefix(4)), "overflow retries exactly once with a smaller captured prefix")
        check(plan.newGroups == [.init(name: "Kept", tabs: [0, 1])]
              && plan.newGroups[0].tabs.map { answer.request.tabIDs[$0] } == Array(initial.tabIDs.prefix(2)),
              "the successful reduced answer validates and resolves against its own original sidebar IDs")

        // A native attempt may preflight-shrink before generation overflows. Retry that failed
        // request, not the larger initial request that could preflight to the same size again.
        calls = 0
        let preflighted = try await TidyTabsModel.group(initial) { request in
            calls += 1
            if calls == 1 { throw TidyTabsModel.Failure.contextLimit(request.reduced()!) }
            return .init(request: request, proposals: [])
        }
        check(calls == 2 && preflighted.request.tabs.count == 2 && preflighted.proposals.isEmpty,
              "overflow after preflight reduction strictly shrinks the actual failed attempt and retains successful empty output")

        calls = 0
        do {
            _ = try await TidyTabsModel.group(initial) { request in
                calls += 1
                throw TidyTabsModel.Failure.contextLimit(request)
            }
            check(false, "a second context overflow must propagate")
        } catch TidyTabsModel.Failure.contextLimit(let failed) {
            check(calls == 2 && failed.tabIDs == Array(initial.tabIDs.prefix(4)), "second overflow returns failure without a third request")
        }
        calls = 0
        do {
            _ = try await TidyTabsModel.group(initial) { _ in
                calls += 1
                throw TidyTabsModel.Failure.unavailable
            }
            check(false, "generic failure must not become a successful answer")
        } catch TidyTabsModel.Failure.unavailable {
            check(calls == 1, "unavailable generation propagates without a context retry")
        }
        calls = 0
        do {
            _ = try await TidyTabsModel.group(initial) { _ in
                calls += 1
                throw CancellationError()
            }
            check(false, "cancellation must not become a successful answer")
        } catch is CancellationError {
            check(calls == 1, "cancelled generation propagates without retry")
        }
        let minimal = TidyTabs.request(tabs: Array(tabs.prefix(1)), existingGroups: [])!
        do {
            _ = try await TidyTabsModel.group(minimal) { request in throw TidyTabsModel.Failure.contextLimit(request) }
            check(false, "an unshrinkable request must not become a successful answer")
        } catch TidyTabsModel.Failure.contextLimit(let failed) {
            check(failed == minimal, "minimal overflow preserves the failed mapping and propagates failure")
        }
        print("Tidy Tabs model: \(checks) checks passed")
        if CommandLine.arguments.contains("--real") { try await realSamples() }
    }

    private static func realSamples() async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.4, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else {
                print("REAL MODEL UNAVAILABLE: \(model.availability)")
                return
            }
            let instructions = try await model.tokenCount(for: Instructions { TidyTabs.instructions })
            let schema = try await model.tokenCount(for: TidyAnswer.generationSchema)
            print("REAL MODEL: context=\(model.contextSize), instructionTokens=\(instructions), schemaTokens=\(schema), minimumResponseReserve=\(TidyTabs.minimumResponseTokens), framingReserve=\(TidyTabs.framingTokens)")
            check(schema <= TidyTabs.fallbackSchemaTokens, "the fixed schema fits the documented macOS 26.0–26.3 fallback schema reserve")
            let samples = [
                ["nitehawk cinema - Google Search", "Amazon: Amazing Deals on Home Goods, Gifts and More", "toaster reviews wirecutter",
                 "What you should look for in buying a toaster", "June 25 | Weekly View", "Barbie Movie | Pavilion Theater"],
                ["Best toaster reviews - Wirecutter", "Buy a two-slice toaster - Kitchen Shop", "Work calendar - Tuesday appointments",
                 "Team meeting schedule - Calendar", "Barbie showtimes - Pavilion Theater", "Oppenheimer tickets - Nitehawk Cinema"],
                ["京都旅行のホテル予約", "京都の観光スポットと交通", "パン作りの基本レシピ", "自家製パンの材料と作り方", "仕事の予定表", "チーム会議のカレンダー"]
            ]
            for (index, titles) in samples.enumerated() {
                let tabs = titles.map { TidyTabs.Tab(id: UUID(), title: $0, host: "") }
                let request = TidyTabs.request(tabs: tabs, existingGroups: [], maximumBytes: TidyTabsModel.promptByteLimit)!
                let started = Date()
                let answer = try await TidyTabsModel.group(request)
                let tokens = try await model.tokenCount(for: answer.request.prompt)
                let validated = answer.request.plan(answer.proposals)
                print("REAL SAMPLE \(index + 1): tabs=\(answer.request.tabs.count), promptBytes=\(answer.request.promptBytes), inputTokens=\(instructions + schema + tokens), elapsed=\(Date().timeIntervalSince(started))")
                print("SYNTHETIC INPUT: \(titles)")
                print("RAW GROUPS: \(answer.proposals)")
                print("VALIDATED GROUPS: \(validated.newGroups)")
                check(answer.request.tabIDs == request.tabIDs, "small synthetic sample retains every captured tab ID")
                check(instructions + schema + tokens + answer.request.responseTokens + TidyTabs.framingTokens <= model.contextSize,
                      "real sample's counted components plus response/framing reserves fit the model context")
            }
            // Ordinary English may exceed the conservative byte fallback while fitting exact
            // tokens. A Unicode stress input follows the same production preflight and mapping.
            for (label, titles) in [("English60", (0..<60).map { "Project planning note \($0)" }),
                                    ("Unicode60", (0..<60).map { "\($0) " + String(repeating: "京都🧹", count: 100) })] {
                let request = TidyTabs.request(tabs: titles.map { .init(id: UUID(), title: $0, host: "") },
                                               existingGroups: [], maximumBytes: TidyTabsModel.promptByteLimit)!
                let initialCost = try await model.tokenCount(for: request.prompt) + instructions + schema
                    + request.responseTokens + TidyTabs.framingTokens
                let answer = try await TidyTabsModel.group(request)
                let finalCost = try await model.tokenCount(for: answer.request.prompt) + instructions + schema
                    + answer.request.responseTokens + TidyTabs.framingTokens
                print("REAL BUDGET \(label): initialTabs=\(request.tabs.count), selectedTabs=\(answer.request.tabs.count), initialCost=\(initialCost), finalCost=\(finalCost), responseReserve=\(answer.request.responseTokens)")
                check(finalCost <= model.contextSize && answer.request.tabIDs == Array(request.tabIDs.prefix(answer.request.tabs.count)),
                      "production token preflight preserves a fitting captured prefix")
                check(initialCost <= model.contextSize ? answer.request.tabIDs == request.tabIDs : answer.request.tabs.count < request.tabs.count,
                      "exact preflight reduces only requests that exceed the complete token budget")
                if label == "English60" {
                    check(request.tabs.count == 60 && answer.request.tabs.count == 60 && request.promptBytes > TidyTabs.fallbackPromptBytes,
                          "newer SDK uses context that fits an ordinary 60-tab English batch beyond the fallback byte cap")
                }
            }
        }
        #endif
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
