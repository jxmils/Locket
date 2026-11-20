import SwiftUI
import WidgetKit

struct MailEntry: TimelineEntry {
    var date = Date()
    var name: String?
    var day: String?
    var id: String?
    var image: UIImage?
    var portrait: Data?
    var count = 0
}

struct MailProvider: TimelineProvider {
    func placeholder(in context: Context) -> MailEntry { MailEntry(name: "Sam", day: "Today") }
    func getSnapshot(in context: Context, completion: @escaping (MailEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MailEntry>) -> Void) {
        Task {
            // Show a tapped page immediately; network sync has a separate freshness interval.
            let defaults = UserDefaults(suiteName: Storage.group)
            if Date().timeIntervalSince1970 - (defaults?.double(forKey: "widget.sync") ?? 0) >= 900 {
                if (try? await CloudBooks().refresh()) != nil {
                    defaults?.set(Date().timeIntervalSince1970, forKey: "widget.sync")
                }
            }
            completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(900))))
        }
    }
    private func load() -> MailEntry {
        let mail = Storage.read().mail
        guard let page = mail.first(where: { $0.id == Storage.selectedPage }) ?? mail.first else { return MailEntry() }
        return MailEntry(name: page.book.author, day: page.stamp.dateLabel, id: page.id,
                         image: page.stamp.image(), portrait: page.book.portrait, count: mail.count)
    }
}

@main
struct FriendsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Storage.widget, provider: MailProvider()) { entry in
            MailWidgetView(entry: entry)
                .containerBackground(Paper.page, for: .widget)
                .widgetURL(URL(string: "locketstamps://postbox"))
        }
        .configurationDisplayName("Friends’ stamps")
        .description("Turn through the photo stamps your friends have shared.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MailWidgetView: View {
    let entry: MailEntry
    var body: some View {
        Group {
            if let name = entry.name {
                if entry.count > 1, let id = entry.id {
                    Button(intent: NextStamp(current: id)) { card(name) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stamp from \(name), \(entry.day ?? ""). Next stamp.")
                } else { card(name) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray")
                    Text("Postbox").font(.system(.title2, design: .serif))
                    Text("Open a friend’s book invitation to see their stamps here.").font(.caption)
                }.padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Paper.ink).privacySensitive()
    }
    @ViewBuilder private func card(_ name: String) -> some View {
        FriendWidgetFace(name: name, day: entry.day ?? "", image: entry.image, portrait: entry.portrait)
    }
}
