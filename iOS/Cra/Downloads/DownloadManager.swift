import CraCore
import PassKit
import QuickLook
import SwiftUI
import UIKit
import WebKit

/// Downloads: files go to the app's Documents/Downloads (the Files app shows it), numbered when a
/// name is taken, and are listed in `downloads.json` (`MobileDownloads`).
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    private(set) var list = MobileDownloads()
    private var listURL: URL?
    private var inFlight: [ObjectIdentifier: (file: URL, source: String)] = [:]
    /// Called on the main thread when a download has finished.
    var onFinish: ((MobileDownloads.Item) -> Void)?

    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load(from directory: URL) {
        let url = directory.appendingPathComponent("downloads.json")
        listURL = url
        if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(MobileDownloads.self, from: data) { list = loaded }
    }

    private func save() {
        guard let listURL, let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    func file(for item: MobileDownloads.Item) -> URL {
        Self.folder.appendingPathComponent(item.name)
    }

    func remove(_ ids: Set<UUID>) {
        for item in list.items where ids.contains(item.id) { try? FileManager.default.removeItem(at: file(for: item)) }
        list.remove(ids)
        save()
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? [])
        let file = Self.folder.appendingPathComponent(MobileDownloads.freeName(for: suggestedFilename, taken: taken))
        inFlight[ObjectIdentifier(download)] = (file, response.url?.absoluteString ?? download.originalRequest?.url?.absoluteString ?? "")
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let done = inFlight.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: done.file.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let item = MobileDownloads.Item(name: done.file.lastPathComponent, source: done.source, date: Date(), bytes: bytes)
        list.add(item)
        save()
        onFinish?(item)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let failed = inFlight.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: failed.file) }
    }

    // MARK: Opening

    /// Opens a download: a Wallet pass goes to Wallet, anything else is previewed.
    func open(_ item: MobileDownloads.Item, from presenter: UIViewController) {
        let url = file(for: item)
        if MobileDownloads.opening(forName: item.name) == .walletPass, let data = try? Data(contentsOf: url), let pass = try? PKPass(data: data),
           let add = PKAddPassesViewController(pass: pass) {
            return presenter.present(add, animated: true)
        }
        let preview = QLPreviewController()
        let source = PreviewSource(url: url)
        preview.dataSource = source
        objc_setAssociatedObject(preview, &PreviewSource.key, source, .OBJC_ASSOCIATION_RETAIN)
        presenter.present(preview, animated: true)
    }
}

private final class PreviewSource: NSObject, QLPreviewControllerDataSource {
    static var key = 0
    let url: URL

    init(url: URL) { self.url = url }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
}

final class DownloadsModel: ObservableObject {
    @Published var items: [MobileDownloads.Item]
    var open: (MobileDownloads.Item) -> Void = { _ in }
    var done: () -> Void = {}

    init() { items = DownloadManager.shared.list.items }

    func remove(_ ids: Set<UUID>) {
        DownloadManager.shared.remove(ids)
        items = DownloadManager.shared.list.items
    }
}

/// Settings ▸ Downloads.
struct DownloadsView: View {
    @ObservedObject var model: DownloadsModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.items) { item in
                    Button { model.open(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1).foregroundStyle(.primary)
                                Text(MobileDownloads.detail(for: item)).font(.footnote).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("download-row-\(item.name)")
                }
                .onDelete { offsets in model.remove(Set(offsets.map { model.items[$0].id })) }
            }
            .overlay {
                if model.items.isEmpty { Text("No Downloads").foregroundStyle(.secondary) }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.done() }.fontWeight(.semibold) } }
        }
    }
}
