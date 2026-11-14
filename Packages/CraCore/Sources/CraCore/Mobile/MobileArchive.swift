import Foundation

/// The Archive list: closed and timed-out tabs by the day they were last looked at.
public enum MobileArchive {
    public struct Section: Equatable, Identifiable {
        /// "TODAY", "YESTERDAY", or the day's date in capitals.
        public var title: String
        public var tabs: [MobileTab]
        public var id: String { title }
    }

    /// `tabs` newest first, grouped by day, keeping those whose title or address contains `query`.
    public static func sections(_ tabs: [MobileTab], matching query: String, now: Date, calendar: Calendar = .current,
                                locale: Locale = .current) -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = tabs.filter { needle.isEmpty || $0.title.lowercased().contains(needle) || $0.url.lowercased().contains(needle) }
            .sorted { $0.lastActive > $1.lastActive }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let today = calendar.startOfDay(for: now)
        var sections: [Section] = []
        for tab in shown {
            let day = calendar.startOfDay(for: tab.lastActive)
            let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title = days <= 0 ? "TODAY" : days == 1 ? "YESTERDAY" : formatter.string(from: tab.lastActive).uppercased(with: locale)
            if sections.last?.title == title {
                sections[sections.count - 1].tabs.append(tab)
            } else {
                sections.append(Section(title: title, tabs: [tab]))
            }
        }
        return sections
    }

    /// A row's second line: the address without its scheme.
    public static func subtitle(for tab: MobileTab) -> String {
        var text = tab.url
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { text.removeFirst(scheme.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}
