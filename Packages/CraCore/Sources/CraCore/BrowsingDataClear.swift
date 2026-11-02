import Foundation

/// Arc's Clear Browsing Data (Settings ▸ Profiles) opens Chrome's settings at Privacy and security,
/// where "Delete browsing data" is Chrome's dialog. Arc's command bar reads Chromium's history, so
/// what the dialog deletes leaves it (Arc 1.171, offline copy, 2 Nov 2026: after "Last 7 days" the
/// command bar listed no history for the deleted pages). Cra's command bar reads its own history
/// (history.json) and learned picks (commandbar.json), which follow the dialog: its delete sends
/// `chrome.send("clearBrowsingData", [callback, data types, time period])` (Chromium 156,
/// settings_clear_browsing_data_handler.cc), which Cra hears on the page. Reported on X,
/// 1 Nov 2026: cleared history kept showing in the command bar.
public enum BrowsingDataClear {
    public static let pageURL = "chrome://settings/clearBrowserData"
    /// browsing_data::prefs::kDeleteBrowsingHistory.
    public static let historyDataType = "browser.clear_data.browsing_history"

    public enum Range: Equatable {
        case allTime
        /// Visited at or after the date.
        case since(Date)
        /// Visited before the date.
        case before(Date)

        public func contains(_ date: Date) -> Bool {
            switch self {
            case .allTime: return true
            case .since(let d): return date >= d
            case .before(let d): return date < d
            }
        }
    }

    /// The history the dialog deletes, or nil when history isn't among what it deletes.
    /// `timePeriod` is browsing_data::TimePeriod.
    public static func historyRange(dataTypes: [String], timePeriod: Int, now: Date) -> Range? {
        guard dataTypes.contains(historyDataType) else { return nil }
        let day: TimeInterval = 86400
        switch timePeriod {
        case 0: return .since(now.addingTimeInterval(-3600))  // LAST_HOUR
        case 1: return .since(now.addingTimeInterval(-day))  // LAST_DAY
        case 2: return .since(now.addingTimeInterval(-7 * day))  // LAST_WEEK
        case 3: return .since(now.addingTimeInterval(-28 * day))  // FOUR_WEEKS
        case 4: return .allTime  // ALL_TIME
        case 5: return .before(now.addingTimeInterval(-30 * day))  // OLDER_THAN_30_DAYS
        case 6: return .since(now.addingTimeInterval(-15 * 60))  // LAST_15_MINUTES
        default: return nil
        }
    }

    /// The message's arguments after the callback id, as the page hands them over (JSON).
    public static func historyRange(messageJSON: String, now: Date) -> Range? {
        guard let data = messageJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [Any], args.count == 2,
              let types = args[0] as? [String], let period = args[1] as? Int else { return nil }
        return historyRange(dataTypes: types, timePeriod: period, now: now)
    }

    /// History and learned signals without `range`. Cra keeps a page's last visit only, so a
    /// page last visited inside the range goes with all its visits. Learned picks of pages that
    /// went go too, all of them for all time, and so do tab switches inside the range.
    public static func clearing(_ range: Range, history: [String: HistoryEntry],
                                ranking: RankingData) -> (history: [String: HistoryEntry], ranking: RankingData) {
        let kept = history.filter { !range.contains($0.value.lastVisit) }
        var r = ranking
        if range == .allTime {
            r.queriesToSelected = [:]
        } else {
            let gone = Set(history.keys).subtracting(kept.keys)
            r.queriesToSelected = r.queriesToSelected.filter { !gone.contains($0.value) }
        }
        r.recentlySwitchedToTabs = r.recentlySwitchedToTabs
            .mapValues { $0.filter { !range.contains($0) } }
            .filter { !$0.value.isEmpty }
        return (kept, r)
    }
}
