import CraCore
import Testing

struct DataFolderOwnerTests {
    private let alive: Set<Int32> = [500, 777]

    /// A test copy with a data folder of its own owns it while the installed Cra runs (GitHub #299's scenario).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/299"))
    func aFolderNoOneLocksIsFree() {
        #expect(DataFolderOwner.isFree(lockTarget: nil, host: "mac", me: 777) { alive.contains($0) })
    }

    @Test func anotherLiveCraOnTheFolderHoldsIt() {
        #expect(!DataFolderOwner.isFree(lockTarget: "mac-500", host: "mac", me: 777) { alive.contains($0) })
    }

    @Test func aStaleLockOrOursIsFree() {
        #expect(DataFolderOwner.isFree(lockTarget: "mac-321", host: "mac", me: 777) { alive.contains($0) })
        #expect(DataFolderOwner.isFree(lockTarget: "mac-777", host: "mac", me: 777) { alive.contains($0) })
    }

    @Test func aHostNameWithDashesStillParses() {
        #expect(!DataFolderOwner.isFree(lockTarget: "victors-mac-book-500", host: "victors-mac-book", me: 777) { alive.contains($0) })
        #expect(DataFolderOwner.isFree(lockTarget: "victors-mac-book-321", host: "victors-mac-book", me: 777) { alive.contains($0) })
    }

    @Test func anotherHostOrAnUnreadableLockCountsAsHeld() {
        #expect(!DataFolderOwner.isFree(lockTarget: "other-321", host: "mac", me: 777) { alive.contains($0) })
        #expect(!DataFolderOwner.isFree(lockTarget: "garbage", host: "mac", me: 777) { alive.contains($0) })
    }
}
