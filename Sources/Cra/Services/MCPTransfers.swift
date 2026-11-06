import CraCEF
import Darwin
import Foundation

/// Private, bounded file transfers. Upload copies stay alive while Chromium's File objects
/// can read them; completed downloads are explicit exports and remain after disconnect.
@MainActor
final class MCPTransfers {
    private var uploads: [URL: Int] = [:]
    private var uploadBytes = 0
    private var closed = false
    private var downloads: [UUID: Download] = [:]
    private weak var browser: CraBrowser?
    init(_ browser: CraBrowser) { self.browser = browser }

    func close() {
        closed = true
        browser?.cancelAgentDownload()
        for download in downloads.values { download.cancel(); download.timeout?.cancel(); download.timeout = nil }
        for folder in uploads.keys { try? FileManager.default.removeItem(at: folder) }
        uploads.removeAll(); uploadBytes = 0
    }

    func stage(_ paths: [String]) async throws -> [String] {
        guard !closed, uploads.count < 16 else { throw failure("Upload staging limit reached or tab closed.") }
        let budget = 64 * 1024 * 1024 - uploadBytes
        // File reads/copies can block on storage. Keep them off the browser's main thread.
        let staged = try await Task.detached(priority: .utility) { try Self.copyFiles(paths, budget: budget) }.value
        guard !closed else {
            try? FileManager.default.removeItem(at: staged.directory)
            throw failure("Tab closed while staging upload files.")
        }
        uploads[staged.directory] = staged.bytes; uploadBytes += staged.bytes
        return staged.paths
    }

    var isEmpty: Bool { uploads.isEmpty && downloads.isEmpty }
    func discard(_ paths: [String]) {
        guard let first = paths.first else { return }
        let folder = URL(fileURLWithPath: first).deletingLastPathComponent().deletingLastPathComponent()
        guard let bytes = uploads.removeValue(forKey: folder) else { return }
        uploadBytes -= bytes
        try? FileManager.default.removeItem(at: folder)
    }

    private struct Staged: Sendable { let directory: URL; let paths: [String]; let bytes: Int }
    nonisolated private static func copyFiles(_ paths: [String], budget: Int) throws -> Staged {
        let directory = try Self.directory(kind: "upload")
        do {
            var staged: [String] = [], bytes = 0
            for (index, path) in paths.enumerated() {
                guard path.hasPrefix("/"), !path.contains("\0") else { throw failure("Upload paths must be absolute local file paths.") }
                let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard fd >= 0 else { throw failure("Cannot open upload file (symlinks are refused).") }
                defer { Darwin.close(fd) }
                var stat = stat()
                guard fstat(fd, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG, stat.st_size >= 0,
                      stat.st_size <= 16 * 1024 * 1024, bytes + Int(stat.st_size) <= budget else {
                    throw failure("Uploads require regular files, at most 16 MiB each and 64 MiB staged per tab.")
                }
                // Separate directories preserve duplicate filenames without overwriting.
                let parent = directory.appendingPathComponent(String(index), isDirectory: true)
                guard mkdir(parent.path, 0o700) == 0 else { throw failure("Cannot create upload staging directory.") }
                let destination = parent.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard output >= 0 else { throw failure("Cannot create private upload copy.") }
                defer { Darwin.close(output) }
                var remaining = Int(stat.st_size), buffer = [UInt8](repeating: 0, count: 65536)
                while remaining > 0 {
                    let count = read(fd, &buffer, min(remaining, buffer.count))
                    guard count > 0 else { throw failure("Upload file changed or could not be read.") }
                    var offset = 0
                    while offset < count {
                        let written = buffer.withUnsafeBytes { write(output, $0.baseAddress!.advanced(by: offset), count - offset) }
                        guard written > 0 else { throw failure("Cannot write upload copy.") }
                        offset += written
                    }
                    remaining -= count
                }
                var after = Darwin.stat()
                guard fstat(fd, &after) == 0, after.st_size == stat.st_size,
                      after.st_mtimespec.tv_sec == stat.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == stat.st_mtimespec.tv_nsec else {
                    throw failure("Upload file changed while copying. Inspect it before retrying.")
                }
                bytes += Int(stat.st_size); staged.append(destination.path)
            }
            return Staged(directory: directory, paths: staged, bytes: bytes)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    func run(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        guard let browser, browser.isAgent else { throw failure("Download tools require a background tab opened by this connection.") }
        if name == "page_download" {
            guard downloads.count < 8, !downloads.values.contains(where: { $0.state == "in_progress" }) else {
                throw failure("One download at a time and eight downloads per agent tab are supported.")
            }
            guard browser.agentDownloadReady else { throw failure("Previous download cancellation is still settling. Poll download_status or close this agent tab and open another. A 60-second timeout closes a stalled tab.") }
            guard let text = arguments["url"] as? String, MCPProtocol.navigable(text),
                  var components = URLComponents(string: text) else { throw failure("Download requires an HTTP(S) URL.") }
            components.fragment = nil
            guard let url = components.url?.absoluteString else { throw failure("Invalid download URL.") }
            let download = Download(folder: try Self.directory(kind: "download"), browser: browser)
            downloads[download.id] = download
            guard browser.startAgentDownload(url, path: download.file.path, update: { [weak download] info in
                download?.update(info)
            }) else { downloads.removeValue(forKey: download.id); download.cancel(); throw failure("Download could not start.") }
            download.startTimeout()
            return try MCPCDP.content(download.result)
        }
        guard let id = (arguments["downloadId"] as? String).flatMap(UUID.init(uuidString:)), let download = downloads[id] else {
            throw failure("Download ID does not belong to this tab.")
        }
        if name == "download_cancel" { download.cancel() }
        return try MCPCDP.content(download.result)
    }

    nonisolated static func directory(kind: String) throws -> URL {
        let root = AppPaths.file("mcp-transfers")
        guard mkdir(root.path, 0o700) == 0 || errno == EEXIST else { throw failure("Cannot create transfer directory.") }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Transfer directory is not a safe directory.") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else { throw failure("Transfer directory must be owned by you with mode 0700.") }
        let name = kind + "-" + UUID().uuidString
        guard mkdirat(fd, name, 0o700) == 0 else { throw failure("Cannot create private transfer directory.") }
        return root.appendingPathComponent(name, isDirectory: true)
    }

    /// Called only after acquiring the exclusive MCP listener lock. Completed downloads are
    /// exports; only upload copies from a crashed/previous server are disposable.
    nonisolated static func removeAbandonedUploads() {
        let root = AppPaths.file("mcp-transfers")
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix("upload-") && UUID(uuidString: String(folder.lastPathComponent.dropFirst(7))) != nil {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    nonisolated private static func failure(_ message: String) -> MCPCDP.Failure { MCPCDP.Failure(message: message) }
    private func failure(_ message: String) -> MCPCDP.Failure { Self.failure(message) }

    private final class Download {
        let id = UUID()
        let folder: URL
        var file: URL { folder.appendingPathComponent("download") }
        weak var browser: CraBrowser?
        var state = "in_progress", suggestedName = ""
        var bytes: Int64 = 0, total: Int64 = -1
        var timeout: Task<Void, Never>?
        init(folder: URL, browser: CraBrowser) { self.folder = folder; self.browser = browser }
        func startTimeout() {
            timeout = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(60))
                    guard let self else { return }
                    self.timeout = nil
                    if self.state == "in_progress" || self.state == "cancelled" && self.browser?.agentDownloadReady == false {
                        self.cancel(expired: true)
                    }
                } catch {}
            }
        }
        func update(_ info: CraDownloadInfo) {
            guard state == "in_progress" else { return }
            bytes = info.receivedBytes; total = info.totalBytes; suggestedName = info.suggestedName
            switch info.state {
            case .complete:
                let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                var metadata = stat()
                if fd >= 0, fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                   metadata.st_size <= 64 * 1024 * 1024, fchmod(fd, 0o600) == 0 { state = "completed" }
                else { state = "failed" }
                if fd >= 0 { Darwin.close(fd) }
            case .cancelled: state = "cancelled"
            case .interrupted: state = "failed"
            default: break
            }
            if state != "in_progress" { timeout?.cancel(); timeout = nil }
            if state == "cancelled" || state == "failed" { try? FileManager.default.removeItem(at: folder) }
        }
        func cancel(expired: Bool = false) {
            guard state == "in_progress" || expired && state == "cancelled" else { return }
            state = expired ? "timed_out" : "cancelled"
            browser?.cancelAgentDownload()
            // StartDownload has no cancellable item before response headers arrive. Closing
            // the owned windowless browser bounds that otherwise unabortable request.
            if expired { browser?.close() }
            if expired || browser?.agentDownloadReady == true { timeout?.cancel(); timeout = nil }
            try? FileManager.default.removeItem(at: folder)
        }
        var result: [String: Any] {
            var result: [String: Any] = ["downloadId": id.uuidString, "status": state, "canStartNext": browser?.isClosed == false && browser?.agentDownloadReady == true, "receivedBytes": bytes, "totalBytes": total, "suggestedName": suggestedName]
            if state == "completed" { result["path"] = file.path }
            if state == "timed_out" { result["recovery"] = "This agent tab timed out. Call tab_close on this tabId to release its slot, then open a new background tab." }
            else if state == "cancelled", browser?.agentDownloadReady == false { result["recovery"] = "Cancellation is settling. Poll canStartNext or close this tab and open another." }
            return result
        }
    }
}
