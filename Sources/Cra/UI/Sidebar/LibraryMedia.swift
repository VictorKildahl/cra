import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

/// Library ▸ Media's files (MediaLibrary): the folders read off the main thread, top level only,
/// as Arc reads them. Reading Desktop and Documents asks macOS for access the first time.
@MainActor
@Observable
final class MediaScanner {
    static let shared = MediaScanner()
    private(set) var files: [MediaLibrary.File] = []
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var thumbnails = NSCache<NSString, NSImage>()

    static func url(_ folder: MediaLibrary.Folder) -> URL? {
        let fm = FileManager.default
        switch folder {
        case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask).first
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .screenshots:
            // macOS's screenshot folder (Screenshot ▸ Options ▸ Save to), the Desktop by default.
            let set = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
            return set.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
                ?? fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
    }

    @ObservationIgnored private var pending: [MediaLibrary.Folder]?

    func rescan(_ folders: [MediaLibrary.Folder]) {
        // One scan at a time; the folders asked for meanwhile are read next.
        guard !scanning else { pending = folders; return }
        scanning = true
        let urls = folders.compactMap(Self.url)
        Task.detached(priority: .utility) {
            var found: [MediaLibrary.File] = []
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            for dir in urls {
                let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                          options: [.skipsHiddenFiles])) ?? []
                for u in items where MediaLibrary.isMedia(u.path) {
                    let v = try? u.resourceValues(forKeys: Set(keys))
                    guard v?.isRegularFile == true else { continue }
                    found.append(.init(path: u.path, date: v?.contentModificationDate ?? .distantPast))
                }
            }
            let result = MediaLibrary.shown(found, query: "")
            await MainActor.run {
                self.scanning = false
                if result != self.files { self.files = result }
                if let next = self.pending { self.pending = nil; self.rescan(next) }
            }
        }
    }

    /// A Quick Look thumbnail, cached; nil until it is drawn, then `done` runs on the main thread.
    func thumbnail(_ file: MediaLibrary.File, size: CGFloat, done: @escaping @MainActor (NSImage) -> Void) -> NSImage? {
        let key = "\(file.path)|\(file.date.timeIntervalSince1970)" as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: file.path), size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.thumbnails.setObject(image, forKey: key)
                    done(image)
                }
            }
        }
        return nil
    }
}

/// Arc's Media grid (measured at 2x on Arc 1.172.1): tiles 138 pt square, 10 pt apart in two
/// columns from 7 pt in, a faint fill (darker under the pointer) with 10 pt corners; the picture
/// fitted inside 12 pt in, framed in 4 pt of white with a soft shadow.
/// Arc 1.172.1's grid (Victor's Arc, 8 Nov 2026, 2x stills): in a 305 pt column the tiles are 132 pt,
/// 12 pt from the left, 16 pt apart, rows 8 pt apart.
enum MediaGridMetrics {
    static let gap: CGFloat = 16
    static let inset: CGFloat = 12
    static let trailing: CGFloat = 13
    static let rowGap: CGFloat = 8
    static func tile(width: CGFloat) -> CGFloat { max(60, ((width - inset - trailing - gap) / 2).rounded(.down)) }
    static func rowHeight(width: CGFloat) -> CGFloat { tile(width: width) + rowGap }
    /// The thumbnail's pixel size to ask for.
    static let tile: CGFloat = 138
    static let padding: CGFloat = 12
    static let frame: CGFloat = 4
}

final class MediaRowCell: NSView {
    private var tiles: [MediaTile] = []
    /// The picked file and where its picture is drawn, in screen points.
    var open: (MediaLibrary.File, NSRect?) -> Void = { _, _ in }

    override var isFlipped: Bool { true }

    func show(_ files: [MediaLibrary.File], ink: NSColor) {
        while tiles.count < 2 {
            let t = MediaTile()
            t.open = { [weak self] in self?.open($0, $1) }
            tiles.append(t)
            addSubview(t)
        }
        for (i, t) in tiles.enumerated() {
            t.isHidden = i >= files.count
            if i < files.count { t.show(files[i], ink: ink) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = MediaGridMetrics.self
        let w = m.tile(width: bounds.width)
        for (i, t) in tiles.enumerated() {
            t.frame = NSRect(x: m.inset + CGFloat(i) * (w + m.gap), y: 0, width: w, height: w)
        }
    }
}

final class MediaTile: NSView, NSDraggingSource {
    var open: (MediaLibrary.File, NSRect?) -> Void = { _, _ in }
    private var file: MediaLibrary.File?
    private var ink: NSColor = .white
    private let picture = CALayer()
    /// Arc marks a video with a white ▶ over its picture.
    private let play = NSImageView()
    private var hovering = false { didSet { refresh() } }
    private var downAt: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        picture.borderColor = NSColor.white.cgColor
        picture.borderWidth = MediaGridMetrics.frame
        picture.backgroundColor = NSColor.white.cgColor
        picture.contentsGravity = .resizeAspectFill
        picture.masksToBounds = false
        picture.shadowColor = NSColor.black.cgColor
        picture.shadowOpacity = 0.18
        picture.shadowRadius = 3
        picture.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(picture)
        play.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Video")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        play.contentTintColor = .white
        play.imageScaling = .scaleNone
        play.wantsLayer = true
        play.shadow = { let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowBlurRadius = 4; return sh }()
        play.isHidden = true
        addSubview(play)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ file: MediaLibrary.File, ink: NSColor) {
        self.ink = ink
        toolTip = file.name
        guard file != self.file else { refresh(); return }
        self.file = file
        play.isHidden = !["mov", "mp4", "m4v"].contains((file.path as NSString).pathExtension.lowercased())
        picture.contents = nil
        if let image = MediaScanner.shared.thumbnail(file, size: MediaGridMetrics.tile, done: { [weak self] image in
            guard self?.file == file else { return }
            self?.picture.contents = image
            self?.needsLayout = true
        }) {
            picture.contents = image
        }
        refresh()
        needsLayout = true
    }

    private func refresh() {
        layer?.backgroundColor = ink.withAlphaComponent(hovering ? 0.08 : 0.04).cgColor
    }

    override func layout() {
        super.layout()
        let box = bounds.insetBy(dx: MediaGridMetrics.padding, dy: MediaGridMetrics.padding)
        var size = (picture.contents as? NSImage)?.size ?? NSSize(width: 4, height: 3)
        if size.width <= 0 || size.height <= 0 { size = NSSize(width: 4, height: 3) }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = (size.width * scale).rounded(), h = (size.height * scale).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        picture.shadowPath = CGPath(rect: picture.bounds, transform: nil)
        CATransaction.commit()
        play.frame = NSRect(x: box.midX - 16, y: box.midY - 16, width: 32, height: 32)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    /// Dragging a tile out hands the file over, as dragging a download does: into a page's upload
    /// field, a message, the Finder.
    override func mouseDragged(with event: NSEvent) {
        guard let file, let start = downAt, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: file.path) as NSURL)
        item.setDraggingFrame(picture.frame, contents: (picture.contents as? NSImage) ?? NSWorkspace.shared.icon(forFile: file.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, let file, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        open(file, window.map { $0.convertToScreen(convert(picture.frame, to: nil)) })
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .generic]
    }
}

/// Arc's card over the Media page until it is turned on: "Your Media in the Library", what it
/// does, a Show Media button and the privacy line under it (Arc 1.172.1).
struct MediaOptInCard: View {
    let dark: Bool
    let show: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(red: 0.55, green: 0.47, blue: 0.93))
                .padding(.top, 4)
            Text("Your Media in the Library").font(.system(size: 13, weight: .semibold))
            Text("Quickly grab screenshots, images, and videos from your computer by showing them in the Cra Library!")
                .font(.system(size: 11.5)).multilineTextAlignment(.center).foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: show) {
                Text("Show Media").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.55, blue: 0.80), Color(red: 0.40, green: 0.42, blue: 0.95)],
                                             startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 8))
                Text("Media never leaves your computer and is not viewable by anyone but you.").font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 222)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(dark ? Color(white: 0.18) : .white)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
