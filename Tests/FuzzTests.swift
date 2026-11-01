import Foundation

/// Feeds the parsers of other browsers' files with mutated copies of the fixtures: Chromium's
/// SNSS session, Bookmarks and Preferences, and Arc's StorableSidebar.json. Built with
/// AddressSanitizer by scripts/fuzz.sh; a crash or an ASan report fails the run and leaves the
/// input in $CRA_FUZZ_OUT/crash-input. Seeded, so a run repeats exactly (CRA_FUZZ_SEED).
/// Xcode's toolchain has no libFuzzer on macOS; this is the coverage-blind kind, mutations of
/// real files rather than random bytes, which is what reaches past the first format check.
@main
enum FuzzTests {
    @MainActor
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        let iterations = Int(env["CRA_FUZZ_ITERATIONS"] ?? "") ?? 20000
        var rng = SplitMix(seed: UInt64(env["CRA_FUZZ_SEED"] ?? "") ?? 0xC4A)
        let out = URL(fileURLWithPath: env["CRA_FUZZ_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("cra-fuzz-\(UUID().uuidString)", isDirectory: true)
        let arc = work.appendingPathComponent("Arc", isDirectory: true), profile = work.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: arc, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        setenv("CRA_DATA_DIR", work.path, 1)
        setenv("CRA_ARC_DIR", arc.path, 1)

        let chromium = fixtures.appendingPathComponent("Chromium/Default")
        let session = try Data(contentsOf: chromium.appendingPathComponent("Sessions/Session_13300000000000000"))
        let targets: [(name: String, seed: Data, run: (Data) throws -> Void)] = [
            ("SNSS session", session, { _ = ChromiumImporter.parseSession($0) }),
            ("Bookmarks", try Data(contentsOf: chromium.appendingPathComponent("Bookmarks")), {
                try $0.write(to: profile.appendingPathComponent("Bookmarks"))
                _ = ChromiumImporter.bookmarks(profile: profile)
            }),
            ("Preferences", try Data(contentsOf: chromium.appendingPathComponent("Preferences")), {
                try $0.write(to: profile.appendingPathComponent("Preferences"))
                _ = ExtensionImporter.disabledIDs(inProfile: profile)
            }),
            ("StorableSidebar.json", try Data(contentsOf: fixtures.appendingPathComponent("Arc/StorableSidebar.json")), {
                try $0.write(to: arc.appendingPathComponent("StorableSidebar.json"))
                _ = try? ArcImporter.plan()
            }),
        ]
        let current = out.appendingPathComponent("crash-input")
        for (name, seed, run) in targets {
            for _ in 0..<iterations / targets.count {
                let input = mutate(seed, others: targets.map(\.seed), &rng)
                // Written first: if the parser takes the process down, this is the reproducer.
                try input.write(to: current)
                try run(input)
            }
            print("fuzz: \(name): \(iterations / targets.count) inputs")
        }
        try? FileManager.default.removeItem(at: current)
        print("Fuzz: no crash in \(iterations) inputs")
    }

    /// One to four byte-level edits, or a JSON-aware one for JSON seeds.
    static func mutate(_ seed: Data, others: [Data], _ rng: inout SplitMix) -> Data {
        if seed.first == UInt8(ascii: "{"), rng.next(4) == 0, let json = try? JSONSerialization.jsonObject(with: seed),
           let data = try? JSONSerialization.data(withJSONObject: mutateJSON(json, &rng, depth: 0), options: [.fragmentsAllowed]) {
            return data
        }
        var b = [UInt8](seed)
        for _ in 0...rng.next(4) {
            guard !b.isEmpty else { break }
            let i = rng.next(b.count)
            switch rng.next(7) {
            case 0: b[i] ^= UInt8(1 << rng.next(8))
            case 1: b[i] = [0, 0xFF, 0x7F, 0x80, 0x01, 0xFE][rng.next(6)]
            case 2: b.removeSubrange(i..<min(b.count, i + 1 + rng.next(16)))
            case 3: b.insert(contentsOf: (0..<1 + rng.next(8)).map { _ in UInt8(rng.next(256)) }, at: i)
            case 4: b = Array(b.prefix(i))
            case 5:
                let j = rng.next(b.count), n = min(1 + rng.next(32), b.count - j)
                b.insert(contentsOf: b[j..<(j + n)], at: i)
            default:
                let other = [UInt8](others[rng.next(others.count)])
                if !other.isEmpty { let j = rng.next(other.count); b.insert(contentsOf: other[j..<min(other.count, j + 1 + rng.next(32))], at: i) }
            }
        }
        // Lengths at the extremes: the parsers read sizes from the file itself.
        if b.count >= 12, rng.next(3) == 0 {
            let i = 8 + rng.next(b.count - 11)
            for (k, v) in [0xFF, 0xFF, 0xFF, 0x7F].enumerated() where i + k < b.count { b[i + k] = UInt8(v) }
        }
        return Data(b)
    }

    static func mutateJSON(_ value: Any, _ rng: inout SplitMix, depth: Int) -> Any {
        let replacements: [Any] = [NSNull(), 0, -1, Int.max, 1.5, "", "x", [Any](), [String: Any](), true]
        if rng.next(6) == 0 || depth > 12 { return replacements[rng.next(replacements.count)] }
        if var d = value as? [String: Any] {
            for k in d.keys where rng.next(3) == 0 { d[k] = mutateJSON(d[k]!, &rng, depth: depth + 1) }
            if rng.next(8) == 0, let k = d.keys.randomElement() { d[k] = nil }
            return d
        }
        if var a = value as? [Any] {
            for i in a.indices where rng.next(3) == 0 { a[i] = mutateJSON(a[i], &rng, depth: depth + 1) }
            if rng.next(8) == 0, !a.isEmpty { a.swapAt(rng.next(a.count), rng.next(a.count)) }
            if rng.next(10) == 0, !a.isEmpty { a.removeLast() }
            return a
        }
        return value
    }
}

/// SplitMix64: small, seedable, the same sequence on every Mac.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(_ bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % UInt64(max(bound, 1)))
    }
}
