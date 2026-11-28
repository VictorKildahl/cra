import Foundation

/// Cra's data folder as Chromium names it. Chromium resolves its user data folder through symbolic links and creates a
/// profile only right inside the resolved one, so a data folder moved to another disk with a link left in its place
/// made every profile but Default fail ("Cannot create profile at path"), with black pages in their spaces (#906).
public enum DataFolderPath {
    /// `folder` with every symbolic link resolved, as realpath(3) gives it (/tmp is /private/tmp: Foundation's
    /// resolvingSymlinksInPath drops /private again); a folder that can't be resolved (not there yet) as given.
    public static func resolved(_ folder: URL) -> URL {
        guard let real = realpath(folder.path, nil) else { return folder }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }
}
