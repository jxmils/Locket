import Foundation
import CryptoKit

let day = "2026-11-20"
let now = ISO8601DateFormatter().date(from: day + "T12:00:00Z")!
let stamp = Stamp(id: day, day: day, posted: now, photo: "p", thumbnail: "s")
let key = Data(repeating: 1, count: 32)
var owner = Book(id: "owner", author: "Owner", timeZone: "UTC", mine: false, stamps: [stamp], mailbox: key, discussionKey: key)
var me = Book(id: "me", author: "Me", timeZone: "UTC", mine: true)
let page = Shelf.Page(book: owner, stamp: stamp)
let target = page.activityTarget!
let record = "comment-first"
let text = try JSONEncoder().encode(StampMessage(action: "comment", text: "What a view!"))
let bytes = try AES.GCM.seal(text, using: SymmetricKey(data: key), authenticating: Data((target + record).utf8)).combined!
me.activities = [
    .init(id: record, target: target, kind: "note", day: day, created: now, contents: bytes),
    .init(id: "copied", target: target, kind: "note", day: day, created: now, contents: bytes),
    .init(id: "pin-today", target: target, kind: "pin", day: day, created: now, contents: nil)
]
var shelf = Shelf(books: [me, owner])
precondition(shelf.replies(to: page).map(\.message.text) == ["What a view!"])
precondition(shelf.pins(in: me, on: now).map(\.id) == [page.id])
precondition(shelf.pins(in: me, on: now.addingTimeInterval(86400)).isEmpty)
shelf.books[1].discussionKey = Data(repeating: 2, count: 32)
precondition(shelf.replies(to: page).isEmpty)
shelf.books[1].priorDiscussionKeys = [key]
precondition(shelf.replies(to: page).count == 1)
shelf.books[1].discussionKey = nil
precondition(shelf.replies(to: page).isEmpty)
shelf.books.removeLast()
precondition(shelf.replies(to: page).isEmpty && shelf.pins(in: me, on: now).isEmpty)
print("Passed private comment access, replay rejection, key rotation and daily pins.")
