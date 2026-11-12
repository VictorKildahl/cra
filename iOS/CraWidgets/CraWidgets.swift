import SwiftUI
import WidgetKit

/// Cra's widgets, after Arc Search's: a small one that opens the app ready to search, a medium
/// one with a search field and Voice and Spaces buttons, and one for the Lock Screen. They show
/// nothing that changes, so one timeline entry is all there is; each part is a link into the app
/// (`cra://search`, `cra://voice`, `cra://spaces`).
@main
struct CraWidgetBundle: WidgetBundle {
    var body: some Widget {
        SearchWidget()
    }
}

struct SearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.kildahl.cra.search", provider: StillProvider()) { _ in
            SearchWidgetView()
        }
        .configurationDisplayName("Cra")
        .description("Open Cra")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct StillEntry: TimelineEntry {
    let date = Date()
}

struct StillProvider: TimelineProvider {
    func placeholder(in context: Context) -> StillEntry { StillEntry() }
    func getSnapshot(in context: Context, completion: @escaping (StillEntry) -> Void) { completion(StillEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StillEntry>) -> Void) {
        completion(Timeline(entries: [StillEntry()], policy: .never))
    }
}

enum WidgetLink {
    static let search = URL(string: "cra://search")!
    static let voice = URL(string: "cra://voice")!
    static let spaces = URL(string: "cra://spaces")!
}

struct SearchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryCircular:
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold)).widgetURL(WidgetLink.search)
            case .accessoryRectangular:
                Label("Search", systemImage: "magnifyingglass").font(.headline).widgetURL(WidgetLink.search)
            default: small
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.74, green: 0.73, blue: 0.83), Color(red: 0.86, green: 0.78, blue: 0.82)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
            Text("Search").font(.system(size: 16, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary.opacity(0.7))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.white.opacity(0.65), in: Capsule())
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("WidgetMark").resizable().frame(width: 34, height: 34)
            Spacer(minLength: 0)
            field
        }
        .widgetURL(WidgetLink.search)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("WidgetMark").resizable().frame(width: 30, height: 30)
                Link(destination: WidgetLink.search) { field }
            }
            HStack(spacing: 10) {
                Link(destination: WidgetLink.voice) { button("Voice", symbol: "mic.fill") }
                Link(destination: WidgetLink.spaces) { button("Spaces", symbol: "desktopcomputer") }
            }
        }
    }

    private func button(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
