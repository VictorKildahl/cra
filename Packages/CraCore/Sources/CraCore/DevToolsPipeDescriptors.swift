import Foundation

/// Descriptors 3 and 4, kept free for Chromium's DevTools pipe.
///
/// Chrome's `--remote-debugging-pipe`, the trusted client that toolbar extension buttons need
/// (`Extensions.triggerAction`), reads fd 3 and writes fd 4. On the Mac no switch moves it
/// (`--remote-debugging-io-pipes` is Windows only). The bridge makes the pipe only when both are
/// free as Chromium starts, and by then AppKit has opened files of its own. On a Mac where
/// HIToolbox.rsrc and Localized.rsrc took 3 and 4, every extension button opened its popup page in
/// a window of its own, Bitwarden 48 pt wide (#752).
///
/// So Cra holds both on /dev/null from the first line of main, before AppKit opens a file. One
/// already open then was left by the process that launched Cra, and Cra takes it over. A file of
/// macOS's own (under /System or /usr) stays: a framework opened it before main and reads it.
/// Cra lets go of them just before Chromium starts.
public enum DevToolsPipeDescriptors {
    /// Chrome's read and write ends (kReadFD, kWriteFD in devtools_pipe_handler.cc).
    public static let chromium: [Int32] = [3, 4]

    /// What `reserve` found at a descriptor.
    public enum Found: Equatable, Sendable {
        case free
        /// Open already, taken over: the file's path when macOS can name it.
        case open(path: String?)
        /// Open already on a file of macOS's own, left as it is: Chromium starts without the pipe.
        case system(path: String)
    }

    /// A file a system framework has open (HIToolbox.rsrc, a Localized.rsrc): never taken from it.
    public static func isSystemFile(_ path: String?) -> Bool {
        guard let path else { return false }
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/")
    }

    /// The /dev/null that `reserve` put at each descriptor (device and inode), so `release` closes
    /// only its own and never a file something else put there since.
    nonisolated(unsafe) private static var held: [Int32: (dev: dev_t, ino: ino_t)] = [:]

    /// Holds each descriptor on /dev/null, close-on-exec, and returns what was there before.
    @discardableResult
    public static func reserve(_ fds: [Int32] = chromium) -> [Int32: Found] {
        let raw = open("/dev/null", O_RDWR | O_CLOEXEC)
        guard raw >= 0 else { return [:] }
        // Above all of them: open() itself may have handed out one of the descriptors to hold.
        let null = fcntl(raw, F_DUPFD_CLOEXEC, (fds.max() ?? 2) + 1)
        close(raw)
        guard null >= 0 else { return [:] }
        defer { close(null) }
        var found: [Int32: Found] = [:]
        for fd in fds {
            if fcntl(fd, F_GETFD) == -1 {
                found[fd] = .free
            } else {
                let path = path(of: fd)
                if let path, isSystemFile(path) { found[fd] = .system(path: path); continue }
                found[fd] = .open(path: path)
            }
            guard dup2(null, fd) == fd else { continue }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            var st = stat()
            if fstat(fd, &st) == 0 { held[fd] = (st.st_dev, st.st_ino) }
        }
        return found
    }

    /// Closes each descriptor that still holds `reserve`'s /dev/null and returns the ones freed.
    @discardableResult
    public static func release(_ fds: [Int32] = chromium) -> [Int32] {
        var freed: [Int32] = []
        for fd in fds {
            guard let mine = held.removeValue(forKey: fd) else { continue }
            var st = stat()
            guard fstat(fd, &st) == 0, st.st_dev == mine.dev, st.st_ino == mine.ino else { continue }
            close(fd)
            freed.append(fd)
        }
        return freed
    }

    /// cra.log's line for the start-up: whether Chromium gets the pipe, and any descriptor a
    /// launcher had left open.
    public static func logLine(found: [Int32: Found], freed: [Int32], fds: [Int32] = chromium) -> String {
        let names = fds.map(String.init)
        let list = names.count == 2 ? "\(names[0]) and \(names[1])" : names.joined(separator: ", ")
        var line = Set(freed) == Set(fds)
            ? "devtools pipe: descriptors \(list) free for Chromium"
            : "devtools pipe: descriptors \(list) not all free (freed \(freed.map(String.init).joined(separator: ", ")) only): Chromium starts without the pipe"
        let taken = fds.compactMap { fd -> String? in
            guard case .open(let path) = found[fd] else { return nil }
            return "\(fd) (\(path ?? "?"))"
        }
        if !taken.isEmpty { line += "; open at launch, taken over: " + taken.joined(separator: ", ") }
        let left = fds.compactMap { fd -> String? in
            guard case .system(let path) = found[fd] else { return nil }
            return "\(fd) (\(path))"
        }
        if !left.isEmpty { line += "; macOS's own at launch, left: " + left.joined(separator: ", ") }
        return line
    }

    private static func path(of fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }
}
