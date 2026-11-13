// The only CEF API DownloadHistory needs. Files, persistence and thumbnails use production code.
public enum CraDownloadControl: Int { case pause, resume, cancel }
public enum CraCEFRuntime {
    public static func controlDownload(_ id: UInt32, action: CraDownloadControl) -> Bool { false }
}
