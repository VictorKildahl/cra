// CEF boundaries needed by production download history/destination code; no Chromium runs.
public enum CraDownloadControl: Int { case pause, resume, cancel }
public enum CraCEFRuntime {
    public static func setDownloadDestinationHandler(_ handler: @escaping (String?, String, @escaping (String?) -> Void) -> Void) {}
    public static func controlDownload(_ id: UInt32, action: CraDownloadControl) -> Bool { false }
}
