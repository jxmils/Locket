import Foundation

struct Book: Codable, Identifiable, Equatable {
    let id: String
    var author: String
    var timeZone: String
    var mine: Bool
    var stamps: [Stamp] = []
    var portrait: Data?
    var mailbox: Data?
    var keyring: Data?
    // This key is unwrapped locally after reading a mutually shared book.
    var discussionKey: Data?
    var priorDiscussionKeys: [Data]?
    var activities: [BookActivity]?
    var changeToken: Data?

    func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct Stamp: Codable, Identifiable, Equatable {
    let id: String
    let day: String
    let posted: Date
    let photo: String
    let thumbnail: String

    var dateLabel: String { formattedDay("dd MMM yyyy") }
    var weekdayLabel: String { formattedDay("EEE d") }
    var monthLabel: String { formattedDay("MMMM yyyy") }
    private func formattedDay(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Calendar slots use the civil dates printed on the stamps, even when the reader travels.
struct StampMonth {
    let weekdays: [String]
    let days: [Int?]

    init?(key: String, calendar source: Calendar = .current) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = source.locale ?? .current
        calendar.timeZone = .gmt
        calendar.firstWeekday = source.firstWeekday
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let names = calendar.shortStandaloneWeekdaySymbols
        weekdays = (0..<7).map { names[(calendar.firstWeekday - 1 + $0) % 7] }
        days = Array(repeating: nil, count: offset) + range.map { Optional($0) }
    }
}

struct Shelf: Codable, Equatable {
    var account: String?
    var books: [Book] = []
    var own: Book? { books.first(where: \.mine) }
    var friends: [Book] {
        books.filter { !$0.mine }.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
    }
    struct Page: Identifiable {
        let book: Book
        let stamp: Stamp
        var id: String { book.id + "/" + stamp.id }
    }
    var mail: [Page] {
        let pages: [Page] = friends.flatMap { book in book.stamps.map { Page(book: book, stamp: $0) } }
        return pages.sorted(by: Self.latestFirst)
    }

    func postbox(on date: Date) -> [Page] {
        friends.compactMap { book -> Page? in
            let today = book.day(date)
            guard let stamp = book.stamps.first(where: { $0.day == today }) else { return nil }
            return Page(book: book, stamp: stamp)
        }.sorted(by: Self.latestFirst)
    }

    private static func latestFirst(_ left: Page, _ right: Page) -> Bool {
        if left.stamp.posted == right.stamp.posted { return left.id < right.id }
        return left.stamp.posted > right.stamp.posted
    }

    static func nextID(_ id: String?, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let current = ids.firstIndex(of: id) else { return ids.first }
        return ids[(current + 1) % ids.count]
    }
}

struct BookActivity: Codable, Equatable, Identifiable {
    let id: String
    let target: String
    let kind: String
    let day: String
    let created: Date
    let contents: Data?
}
