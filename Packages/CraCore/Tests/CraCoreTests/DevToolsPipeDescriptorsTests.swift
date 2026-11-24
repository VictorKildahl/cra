import CraCore
import Foundation
import Testing

/// Cra holds Chromium's DevTools pipe descriptors from the first line of main and frees them just
/// before Chromium starts, so files macOS opens in between, or ones a launcher leaked, can't take
/// them (#752). These use descriptors far above the test process's own, which other tests running
/// alongside never reach. The app's real 3 and 4 are covered by extension-action-fds-held.scenario.
@Suite(.serialized) struct DevToolsPipeDescriptorsTests {
    static let fds: [Int32] = [200, 201]

    static func isNull(_ fd: Int32) -> Bool {
        var st = stat(), null = stat()
        return fstat(fd, &st) == 0 && stat("/dev/null", &null) == 0 && st.st_rdev == null.st_rdev && (st.st_mode & S_IFMT) == S_IFCHR
    }

    static func isOpen(_ fd: Int32) -> Bool { fcntl(fd, F_GETFD) != -1 }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/752"))
    func holdsFreeDescriptorsUntilReleased() {
        for fd in Self.fds { close(fd) }
        let found = DevToolsPipeDescriptors.reserve(Self.fds)
        #expect(found == [200: .free, 201: .free])
        for fd in Self.fds {
            #expect(Self.isNull(fd))
            #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0, "a child process must not inherit the hold")
        }
        #expect(DevToolsPipeDescriptors.release(Self.fds) == Self.fds)
        for fd in Self.fds { #expect(!Self.isOpen(fd)) }
        // Released once: a second release has nothing of its own to close.
        #expect(DevToolsPipeDescriptors.release(Self.fds).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/752"))
    func takesOverDescriptorsALauncherLeftOpen() throws {
        var ends: [Int32] = [0, 0]
        try #require(pipe(&ends) == 0)
        defer { close(ends[0]); close(ends[1]) }
        #expect(dup2(ends[0], 200) == 200)
        close(201)
        let found = DevToolsPipeDescriptors.reserve(Self.fds)
        guard case .open = found[200] else { Issue.record("200 was open: \(String(describing: found[200]))"); return }
        #expect(found[201] == .free)
        #expect(Self.isNull(200))
        #expect(DevToolsPipeDescriptors.release(Self.fds) == Self.fds)
        for fd in Self.fds { #expect(!Self.isOpen(fd)) }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/752"))
    func leavesAFileSomethingElsePutThere() throws {
        DevToolsPipeDescriptors.reserve(Self.fds)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cra-752-\(UUID().uuidString)")
        let other = open(file.path, O_RDWR | O_CREAT, 0o600)
        try #require(other >= 0)
        defer { close(other); unlink(file.path) }
        #expect(dup2(other, 200) == 200)
        #expect(DevToolsPipeDescriptors.release(Self.fds) == [201])
        #expect(Self.isOpen(200), "not Cra's /dev/null any more: whoever put it there keeps it")
        close(200)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/752"))
    func leavesAFileOfMacOSsOwnOpenAtLaunch() throws {
        let system = open("/System/Library/CoreServices/SystemVersion.plist", O_RDONLY)
        try #require(system >= 0)
        defer { close(system) }
        #expect(dup2(system, 200) == 200)
        close(201)
        let found = DevToolsPipeDescriptors.reserve(Self.fds)
        guard case .system(let path) = found[200] else { Issue.record("200 was macOS's: \(String(describing: found[200]))"); return }
        #expect(path.hasSuffix("SystemVersion.plist"))
        #expect(!Self.isNull(200), "a framework's file stays where it is")
        #expect(DevToolsPipeDescriptors.release(Self.fds) == [201])
        #expect(Self.isOpen(200))
        close(200)
        #expect(DevToolsPipeDescriptors.isSystemFile("/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Resources/HIToolbox.rsrc"))
        #expect(DevToolsPipeDescriptors.isSystemFile("/usr/share/icu/icudt76l.dat"))
        #expect(!DevToolsPipeDescriptors.isSystemFile("/dev/null"))
        #expect(!DevToolsPipeDescriptors.isSystemFile("/Users/someone/Library/Logs/launcher.log"))
        #expect(!DevToolsPipeDescriptors.isSystemFile(nil))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/752"))
    func logLineSaysWhetherChromiumGetsThePipe() {
        #expect(DevToolsPipeDescriptors.logLine(found: [3: .free, 4: .free], freed: [3, 4])
            == "devtools pipe: descriptors 3 and 4 free for Chromium")
        #expect(DevToolsPipeDescriptors.logLine(found: [3: .open(path: "/dev/null"), 4: .open(path: nil)], freed: [3, 4])
            == "devtools pipe: descriptors 3 and 4 free for Chromium; open at launch, taken over: 3 (/dev/null), 4 (?)")
        #expect(DevToolsPipeDescriptors.logLine(found: [3: .free, 4: .free], freed: [3])
            == "devtools pipe: descriptors 3 and 4 not all free (freed 3 only): Chromium starts without the pipe")
        #expect(DevToolsPipeDescriptors.logLine(found: [3: .system(path: "/System/HIToolbox.rsrc"), 4: .free], freed: [4])
            == "devtools pipe: descriptors 3 and 4 not all free (freed 4 only): Chromium starts without the pipe; macOS's own at launch, left: 3 (/System/HIToolbox.rsrc)")
    }
}
