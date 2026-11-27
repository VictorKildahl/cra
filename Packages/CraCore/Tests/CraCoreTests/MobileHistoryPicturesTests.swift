import CraCore
import Testing

/// The pictures of the pages behind Back and Forward that the iPhone's page swipe shows: which
/// are kept, and which navigations leave a page worth a picture.
struct MobileHistoryPicturesTests {
    /// Keys stay in the order they were used, oldest first.
    @Test func keysKeepTheOrderTheyWereUsed() {
        var list = MobileRecentList<Int>(limit: 3)
        #expect(list.touch(1).isEmpty)
        #expect(list.touch(2).isEmpty)
        #expect(list.keys == [1, 2])
        #expect(list.contains(1))
        #expect(!list.contains(3))
    }

    /// Past the limit the oldest go, and are returned so their pictures can be dropped.
    @Test func theOldestAreDroppedAtTheLimit() {
        var list = MobileRecentList<Int>(limit: 3)
        for key in 1...3 { list.touch(key) }
        #expect(list.touch(4) == [1])
        #expect(list.keys == [2, 3, 4])
        var none = MobileRecentList<Int>(limit: 0)
        #expect(none.touch(1) == [1])
        #expect(none.keys.isEmpty)
    }

    /// Using a key again makes it the newest, so a page gone back to outlives one left long ago.
    @Test func touchingAKeyAgainMakesItTheNewest() {
        var list = MobileRecentList<Int>(limit: 3)
        for key in 1...3 { list.touch(key) }
        #expect(list.touch(1).isEmpty)
        #expect(list.keys == [2, 3, 1])
        #expect(list.touch(4) == [2])
        #expect(list.keys == [3, 1, 4])
    }

    @Test func removedKeysAreGone() {
        var list = MobileRecentList<Int>(limit: 3)
        for key in 1...3 { list.touch(key) }
        list.remove(2)
        list.remove(9)
        #expect(list.keys == [1, 3])
        list.removeAll()
        #expect(list.keys.isEmpty)
    }

    /// Eight pictures in all, across every tab.
    @Test func eightPicturesAreKept() {
        #expect(MobileHistoryPictures.kept == 8)
    }

    /// A jump to a fragment of the same page keeps the page, so no picture is taken; anything
    /// else that leaves the address is a new page.
    @Test func aFragmentJumpIsNotANewPage() {
        #expect(MobileHistoryPictures.isFragmentJump(from: "https://a.com/p", to: "https://a.com/p#top"))
        #expect(MobileHistoryPictures.isFragmentJump(from: "https://a.com/p#one", to: "https://a.com/p#two"))
        #expect(!MobileHistoryPictures.isFragmentJump(from: "https://a.com/p#one", to: "https://a.com/p"))
        #expect(!MobileHistoryPictures.isFragmentJump(from: "https://a.com/p", to: "https://a.com/q#top"))
        #expect(!MobileHistoryPictures.isFragmentJump(from: "https://a.com/p", to: "https://a.com/p"))
        #expect(!MobileHistoryPictures.isFragmentJump(from: nil, to: "https://a.com/p#top"))
    }
}
