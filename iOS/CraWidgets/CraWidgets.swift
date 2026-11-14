import AppIntents
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
        // The capsule runs off the right edge: the widget lays itself out edge to edge.
        .contentMarginsDisabled()
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
            if family == .systemSmall || family == .systemMedium { Self.gradient } else { Color.clear }
        }
    }

    /// Arc Search's widget, from 60fps.design's "Add Widget" clip: deep indigo at the top left
    /// (#18008c) through purple (#a83d9a) to hot pink at the bottom right (#f44683).
    static let gradient = LinearGradient(stops: [
        .init(color: Color(red: 0x18 / 255, green: 0x00 / 255, blue: 0x8c / 255), location: 0),
        .init(color: Color(red: 0x6a / 255, green: 0x2f / 255, blue: 0xa8 / 255), location: 0.38),
        .init(color: Color(red: 0xc8 / 255, green: 0x43 / 255, blue: 0x96 / 255), location: 0.68),
        .init(color: Color(red: 0xff / 255, green: 0x40 / 255, blue: 0x6c / 255), location: 1),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The white search capsule; on the widget it runs off the right edge, as Arc Search's does.
    private func capsule(height: CGFloat, text: CGFloat) -> some View {
        HStack {
            Text("Search").font(.system(size: text, weight: .regular)).foregroundStyle(Color(white: 0.62))
            Spacer(minLength: 0)
        }
        .padding(.leading, height * 0.42)
        .frame(height: height)
        .background(Color.white, in: Capsule())
    }

    /// A dark translucent button with a white glyph: voice search and Spaces.
    private func roundButton(_ symbol: String, label: String? = nil, size: CGSize) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: size.height * 0.36, weight: .semibold))
            if let label { Text(label).font(.system(size: 14, weight: .semibold)) }
        }
        .foregroundStyle(.white.opacity(0.92))
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.16), in: Capsule())
    }

    /// The buttons open their link through an intent (iOS 18); before that the whole widget searches.
    @ViewBuilder
    private func linked<Content: View>(_ url: URL, @ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOSApplicationExtension 18.0, *) {
            Button(intent: OpenURLIntent(url)) { content() }.buttonStyle(.plain)
        } else {
            content()
        }
    }

    /// Small: the mark at the top left, the capsule beside it running off the edge, voice and
    /// Spaces along the bottom. Positions as fractions of the widget's side, measured on the clip.
    private var small: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack(alignment: .topLeading) {
                Image("WidgetMark").resizable().scaledToFit()
                    .frame(width: side * 0.17, height: side * 0.17)
                    .position(x: side * 0.2, y: side * 0.28)
                capsule(height: side * 0.26, text: side * 0.1)
                    .frame(width: side * 0.75)
                    .position(x: side * 0.36 + side * 0.375, y: side * 0.27)
                HStack(spacing: side * 0.07) {
                    linked(WidgetLink.voice) { roundButton("mic.fill", size: CGSize(width: side * 0.35, height: side * 0.22)) }
                    linked(WidgetLink.spaces) { roundButton("desktopcomputer", size: CGSize(width: side * 0.35, height: side * 0.22)) }
                }
                .position(x: side * 0.5, y: side * 0.77)
            }
            .frame(width: side, height: geo.size.height)
        }
        .widgetURL(WidgetLink.search)
    }

    /// Medium: the same parts across the wider widget (Arc Search's medium widget was not seen).
    private var medium: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Image("WidgetMark").resizable().scaledToFit()
                    .frame(width: height * 0.17, height: height * 0.17)
                    .position(x: height * 0.2, y: height * 0.28)
                Link(destination: WidgetLink.search) {
                    capsule(height: height * 0.26, text: height * 0.1)
                }
                .frame(width: width - height * 0.36 + height * 0.2)
                .position(x: height * 0.36 + (width - height * 0.36 + height * 0.2) / 2, y: height * 0.27)
                HStack(spacing: height * 0.07) {
                    Link(destination: WidgetLink.voice) { roundButton("mic.fill", label: "Voice", size: CGSize(width: (width - height * 0.5) / 2, height: height * 0.22)) }
                    Link(destination: WidgetLink.spaces) { roundButton("desktopcomputer", label: "Spaces", size: CGSize(width: (width - height * 0.5) / 2, height: height * 0.22)) }
                }
                .position(x: width / 2, y: height * 0.77)
            }
        }
    }
}
