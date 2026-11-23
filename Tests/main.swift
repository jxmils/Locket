import Foundation

let book = Book(id: "me", author: "J", timeZone: "America/New_York", mine: true)
let iso = ISO8601DateFormatter()
func date(_ s: String) -> Date { iso.date(from: s)! }
precondition(book.day(date("2026-03-08T04:59:59Z")) == "2026-03-07")
precondition(book.day(date("2026-03-08T05:00:00Z")) == "2026-03-08")
precondition(book.day(date("2026-03-09T04:00:00Z")) == "2026-03-09")
let s = Stamp(id: "2026-11-20", day: "2026-11-20", posted: date("2026-11-20T12:30:00Z"), photo: "p", thumbnail: "t")
let mine = Book(id: "me", author: "Me", timeZone: "UTC", mine: true, stamps: [s])
let a = Book(id: "a", author: "A", timeZone: "UTC", mine: false, stamps: [s])
let b = Book(id: "b", author: "B", timeZone: "UTC", mine: false, stamps: [s])
let data = try JSONEncoder().encode(Shelf(account: "one", books: [b, mine, a]))
let restored = try JSONDecoder().decode(Shelf.self, from: data)
let ids = restored.mail.map(\.id)
precondition(ids == ["a/2026-11-20", "b/2026-11-20"])
precondition(Shelf.nextID(nil, in: ids) == ids[0])
precondition(Shelf.nextID(ids[0], in: ids) == ids[1])
precondition(Shelf.nextID(ids[1], in: ids) == ids[0])
precondition(Shelf.nextID("removed", in: []) == nil)
print("Passed postal dates, DST rollover, archive persistence, friend isolation and widget paging.")

let late = date("2026-11-21T01:00:00Z")
let west = Book(id: "west", author: "West", timeZone: "America/New_York", mine: false, stamps: [s])
let quiet = Book(id: "quiet", author: "Quiet", timeZone: "UTC", mine: false)
let mixed = Shelf(books: [mine, a, west, quiet])
precondition(mixed.postbox(on: s.posted).map(\.book.id) == ["a", "west"])
precondition(mixed.postbox(on: late).map(\.book.id) == ["west"])
precondition(mixed.postbox(on: date("2026-11-21T05:00:00Z")).isEmpty)
precondition(mixed.mail.count == 2)
print("Passed daily Postbox checks for empty books, older posts, author-local midnight, and archive access.")

var mondayCalendar = Calendar(identifier: .gregorian)
mondayCalendar.firstWeekday = 2
let leap = StampMonth(key: "2024-02", calendar: mondayCalendar)!
precondition(leap.days.firstIndex(of: 1) == 3 && leap.days.last == 29)
var sundayCalendar = mondayCalendar
sundayCalendar.firstWeekday = 1
precondition(StampMonth(key: "2026-11", calendar: sundayCalendar)?.days.firstIndex(of: 1) == 0)
precondition(StampMonth(key: "2026-11", calendar: mondayCalendar)?.days.firstIndex(of: 1) == 6)
precondition(StampMonth(key: "2025-02")?.days.compactMap { $0 }.count == 28)
precondition(StampMonth(key: "2026-13") == nil)
print("Passed stamp book calendar month lengths, leap day and weekday alignment.")
