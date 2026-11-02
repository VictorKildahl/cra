import CraCore
import Foundation
import Testing

/// GitHub #91: the recorder's fixed-size containers.
struct PerfHistogramTests {
    @Test(arguments: [(0.0, 0), (0.99, 0), (1.0, 1), (1.99, 1), (2.0, 2), (3.9, 2), (4.0, 3), (250.0, 8), (1000.0, 10),
                      (2000.0, 11), (16384.0, 15), (40000.0, 16), (1e15, 16), (-5.0, 0)])
    func bucketsArePowersOfTwo(ms: Double, bucket: Int) {
        #expect(LogHistogram.bucket(ms: ms) == bucket)
    }

    @Test func nonFiniteDurationsDontPoisonTheTotal() {
        var h = LogHistogram()
        h.record(.infinity)
        h.record(.nan)
        h.record(10)
        #expect(h.count == 3)
        #expect(h.totalMs == 10)
        #expect(h.maxMs == 10)
        #expect(h.buckets[LogHistogram.bucketCount - 1] == 1)   // infinity
        #expect(h.buckets[0] == 1)                              // NaN counts as 0
    }

    @Test func percentilesAreTheUpperEdgeOfTheirBucketCappedByTheMaximum() {
        var h = LogHistogram()
        #expect(h.percentile(0.5) == 0)
        for _ in 0..<90 { h.record(0.5) }
        for _ in 0..<9 { h.record(20) }
        h.record(700)
        #expect(h.percentile(0.5) == 1)
        #expect(h.percentile(0.95) == 32)
        #expect(h.percentile(1) == 700)
        #expect(h.percentile(2) == 700)
        #expect(h.count == 100)
        #expect(abs(h.meanMs - (45 + 180 + 700) / 100) < 1e-9)
    }

    @Test func histogramsAddBucketByBucket() {
        var a = LogHistogram(), b = LogHistogram()
        a.record(3)
        b.record(3)
        b.record(3000)
        a.add(b)
        #expect(a.count == 3)
        #expect(a.buckets[2] == 2)
        #expect(a.maxMs == 3000)
        #expect(a.totalMs == 3006)
        #expect(LogHistogram().meanMs == 0)
    }

    @Test func aHistogramFromAnOlderBuildWithFewerBucketsStillLoads() throws {
        let json = #"{"buckets":[1,2],"count":3,"totalMs":4,"maxMs":2}"#
        let h = try JSONDecoder().decode(LogHistogram.self, from: Data(json.utf8))
        #expect(h.buckets.count == LogHistogram.bucketCount)
        #expect(h.buckets[1] == 2)
        let back = try JSONDecoder().decode(LogHistogram.self, from: JSONEncoder().encode(h))
        #expect(back == h)
    }

    @Test func aRingKeepsTheNewestInOrder() {
        var r = PerfRing<Int>(capacity: 3)
        #expect(r.isEmpty)
        #expect(r.last == nil)
        for i in 1...5 { r.append(i) }
        #expect(r.elements == [3, 4, 5])
        #expect(r.last == 5)
        #expect(r.count == 3)
        #expect(r.appended == 5)
        r.updateLast { $0 = 50 }
        #expect(r.elements == [3, 4, 50])
        r.removeAll()
        #expect(r.isEmpty)
        r.updateLast { $0 = 1 }
        #expect(r.isEmpty)
        #expect(PerfRing<Int>(capacity: 0).capacity == 1)
    }

    @Test func aRingRoundTripsAndTrimsAFileFromALargerRing() throws {
        var r = PerfRing<String>(capacity: 2)
        r.append("a")
        let back = try JSONDecoder().decode(PerfRing<String>.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        let wide = #"{"capacity":2,"elements":["a","b","c"]}"#
        #expect(try JSONDecoder().decode(PerfRing<String>.self, from: Data(wide.utf8)).elements == ["b", "c"])
    }
}

struct PerfStallTests {
    let policy = PerfStallPolicy()

    @Test(arguments: [(249.0, nil), (250.0, PerfStall.Kind.stall), (999.0, .stall), (1000.0, .long), (2000.0, .hang)] as [(Double, PerfStall.Kind?)])
    func thresholds(ms: Double, kind: PerfStall.Kind?) {
        #expect(policy.kind(ms: ms) == kind)
    }

    @Test(arguments: [("kCFRunLoopDefaultMode", "default", true), ("NSEventTrackingRunLoopMode", "tracking", false),
                      ("NSModalPanelRunLoopMode", "modal", false), ("kCFRunLoopCommonModes", "common", true),
                      ("launch", "launch", false), ("CEFCustomMode", "CEFCustomMode", true)])
    func aHeldMenuOrADragIsNotAFreeze(mode: String, short: String, freeze: Bool) throws {
        let s = try #require(policy.stall(at: 10, ms: 600, mode: mode, marks: [], site: nil))
        #expect(s.mode == short)
        #expect(s.freeze == freeze)
    }

    @Test func breadcrumbsAreTheMarksOfTheSecondsBeforeTheStall() throws {
        let marks = [PerfMark(at: 1, label: "old"), PerfMark(at: 7, label: "swipe-begin"), PerfMark(at: 9.4, label: "page-shown"),
                     PerfMark(at: 11, label: "after")]
        let s = try #require(policy.stall(at: 10, ms: 500, mode: "kCFRunLoopDefaultMode", marks: marks, site: "example.com"))
        #expect(s.marks == ["swipe-begin", "page-shown"])
        #expect(s.site == "example.com")
        #expect(s.kind == .stall)
        #expect(policy.stall(at: 10, ms: 100, mode: "kCFRunLoopDefaultMode", marks: marks, site: nil) == nil)
    }

    @Test func breadcrumbsAreCappedToTheNewest() throws {
        var p = PerfStallPolicy()
        p.breadcrumbLimit = 2
        let marks = (0..<5).map { PerfMark(at: Double($0), label: "m\($0)") }
        #expect(try #require(p.stall(at: 5, ms: 300, mode: "x", marks: marks, site: nil)).marks == ["m3", "m4"])
    }

    @Test func aMarkNeverKeepsAnAddress() {
        #expect(PerfMark(at: 0, label: "cra://open?url=https%3A%2F%2Fexample.com%2Fsecret").label == "cra://open")
        #expect(PerfMark(at: 0, label: "first\nsecond").label == "first")
        #expect(PerfMark(at: 0, label: String(repeating: "x", count: 500)).label.count == 120)
    }
}
