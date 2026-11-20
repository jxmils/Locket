import Foundation

struct Book: Codable, Identifiable, Equatable {
    let id: String
    var author: String
    var timeZone: String
    var mine: Bool
    var stamps: [Stamp] = []
    var portrait: Data?
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

    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("dd MMM yyyy")
        return formatter.string(from: date)
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
        return pages.sorted { left, right in
            if left.stamp.posted == right.stamp.posted { return left.id < right.id }
            return left.stamp.posted > right.stamp.posted
        }
    }

    static func nextID(_ id: String?, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let current = ids.firstIndex(of: id) else { return ids.first }
        return ids[(current + 1) % ids.count]
    }
}
