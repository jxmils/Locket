import CloudKit
import Foundation
import CryptoKit

struct CloudBooks {
    static let containerID = "iCloud.com.jasonmiller.Locket"
    let container = CKContainer(identifier: Self.containerID)
    let ownZone = CKRecordZone.ID(zoneName: "StampBook", ownerName: CKCurrentUserDefaultName)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func createBook(author: String) async throws {
        let name = String(author.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { throw LocketIssue.name }
        _ = try await privateDB.save(CKRecordZone(zoneID: ownZone))
        let record = CKRecord(recordType: "Book", recordID: .init(recordName: "book", zoneID: ownZone))
        record["author"] = name
        record["timeZone"] = TimeZone.current.identifier
        do { try await insert(record) }
        catch let e as CKError where e.code == .serverRecordChanged { /* Already created on another device. */ }
    }

    // The day in the owner's book timezone is also the CloudKit record ID.
    // Create-only writes enforce one stamp even if two phones publish together.
    func post(jpeg: Data, book: Book) async throws {
        let account = try await container.userRecordID().recordName
        guard book.mine, Storage.read().account == account else { throw LocketIssue.signIn }
        let now = Date()
        let day = book.day(now)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try jpeg.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let stamp = CKRecord(recordType: "Stamp", recordID: .init(recordName: day, zoneID: ownZone))
        stamp["posted"] = now
        stamp["photo"] = CKAsset(fileURL: file)
        do { try await insert(stamp) }
        catch let e as CKError where e.code == .serverRecordChanged { throw LocketIssue.used }
    }

    private func insert(_ record: CKRecord) async throws {
        let result = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        guard let saved = result.saveResults[record.recordID] else { throw CocoaError(.fileWriteUnknown) }
        _ = try saved.get()
    }

    func setPortrait(_ jpeg: Data?, for book: Book) async throws {
        let account = try await container.userRecordID().recordName
        guard book.mine, Storage.read().own?.id == book.id, Storage.read().account == account else {
            throw LocketIssue.signIn
        }
        let record = try await privateDB.record(for: .init(recordName: "book", zoneID: ownZone))
        record["portrait"] = jpeg
        _ = try await privateDB.save(record)
    }

    func invitation(author: String) async throws -> CKShare {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZone)
        do { if let existing = try await privateDB.record(for: id) as? CKShare { return existing } }
        catch let e as CKError where e.code == .unknownItem {}
        let share = CKShare(recordZoneID: ownZone)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "\(author)’s stamp book"
        guard let saved = try await privateDB.save(share) as? CKShare else { throw CocoaError(.fileWriteUnknown) }
        return saved
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        guard metadata.containerIdentifier == Self.containerID else { return }
        let outcomes = try await container.accept([metadata])
        _ = try outcomes[metadata]?.get()
    }

    func refresh() async throws -> Shelf {
        try await Storage.withWriter { root in
            var shelf = Storage.read()
            let status = try await container.accountStatus()
            if status == .noAccount {
                try Storage.write(Shelf(), to: root)
                Storage.prune(Shelf(), at: root)
                throw LocketIssue.signIn
            }
            guard status == .available else { throw LocketIssue.signIn }
            let account = try await container.userRecordID().recordName
            if shelf.account != account {
                shelf = Shelf(account: account)
                try Storage.write(shelf, to: root)
                Storage.prune(shelf, at: root)
            }
            let sharedZones = try await sharedDB.allRecordZones().map(\.zoneID).filter { $0.zoneName == ownZone.zoneName }
            let active = Set(([ownZone] + sharedZones).map(zoneKey))
            shelf.books.removeAll { !active.contains($0.id) }
            try Storage.write(shelf, to: root)
            Storage.prune(shelf, at: root)
            for zone in [ownZone] + sharedZones {
                let mine = zone == ownZone
                let key = zoneKey(zone)
                var book = shelf.books.first { $0.id == key } ?? Book(id: key, author: "", timeZone: "UTC", mine: mine)
                do {
                    try await update(&book, db: mine ? privateDB : sharedDB, zone: zone, root: root)
                } catch let e as CKError where [.zoneNotFound, .userDeletedZone, .permissionFailure].contains(e.code) {
                    shelf.books.removeAll { $0.id == key }
                    try Storage.write(shelf, to: root)
                    continue
                }
                shelf.books.removeAll { $0.id == key }
                if !book.author.isEmpty { shelf.books.append(book) }
                try Storage.write(shelf, to: root)
            }
            if shelf.own != nil {
                // Always clear previous access before deriving it from the current shares.
                for i in shelf.books.indices { shelf.books[i].discussionKey = nil; shelf.books[i].priorDiscussionKeys = nil }
                try Storage.write(shelf, to: root)
                try await syncMailboxes(&shelf)
                try Storage.write(shelf, to: root)
            }
            Storage.prune(shelf, at: root)
            return shelf
        }
    }

    private func zoneKey(_ id: CKRecordZone.ID) -> String { Storage.key(id.ownerName + "/" + id.zoneName) }

    private func update(_ book: inout Book, db: CKDatabase, zone: CKRecordZone.ID, root: URL) async throws {
        var token = book.changeToken.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        if token == nil { book.stamps = []; book.activities = []; book.author = "" }
        while true {
            do {
                let page = try await db.recordZoneChanges(inZoneWith: zone, since: token)
                for outcome in page.modificationResultsByID.values {
                    let record = try outcome.get().record
                    let id = record.recordID.recordName
                    if record.recordType == "Book" {
                        book.mailbox = record["mailbox"] as? Data
                        book.keyring = record["keyring"] as? Data
                        book.portrait = record["portrait"] as? Data
                        book.author = record["author"] as? String ?? "Friend"
                        book.timeZone = record["timeZone"] as? String ?? "UTC"
                    } else if record.recordType == "StampActivity",
                              let target = record["target"] as? String, let kind = record["kind"] as? String,
                              let day = record["day"] as? String {
                        var entries = book.activities ?? []
                        entries.removeAll { $0.id == id }
                        entries.append(BookActivity(id: id, target: target, kind: kind, day: day,
                            created: record.creationDate ?? .distantPast, contents: record["contents"] as? Data))
                        book.activities = entries
                    } else if record.recordType == "Stamp" {
                        guard let url = (record["photo"] as? CKAsset)?.fileURL else { throw LocketIssue.photo }
                        let stem = Storage.key(book.id + "/" + id)
                        let stamp = Stamp(id: id, day: id, posted: record.creationDate ?? record["posted"] as? Date ?? .distantPast,
                                          photo: stem + ".jpg", thumbnail: stem + "-small.jpg")
                        let data = try Data(contentsOf: url)
                        try data.write(to: root.appendingPathComponent(stamp.photo), options: .atomic)
                        try Storage.bytes(data, limit: 550).write(to: root.appendingPathComponent(stamp.thumbnail), options: .atomic)
                        book.stamps.removeAll { $0.id == id }
                        book.stamps.append(stamp)
                    }
                }
                let deleted = Set(page.deletions.map { $0.recordID.recordName })
                book.stamps.removeAll { deleted.contains($0.id) }
                book.activities?.removeAll { deleted.contains($0.id) }
                token = page.changeToken
                if !page.moreComing { break }
            } catch let e as CKError where e.code == .changeTokenExpired && token != nil {
                token = nil
                book.activities = []
                book.stamps = []
                book.author = ""
            }
        }
        book.stamps.sort { $0.day > $1.day }
        if let token { book.changeToken = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) }
    }
}

extension Shelf.Page {
    var activityTarget: String? {
        book.mailbox.map { Storage.key($0.base64EncodedString() + "/" + stamp.id) }
    }
}

enum StampAction: String { case like, comment, pin }

extension CloudBooks {
    // This record lives in the owner's private default zone, outside the shared book zone.
    private func identity() async throws -> Curve25519.KeyAgreement.PrivateKey {
        let id = CKRecord.ID(recordName: "stampnote-mailbox-v1")
        func read() async throws -> Curve25519.KeyAgreement.PrivateKey {
            let record = try await privateDB.record(for: id)
            guard let data = record["secret"] as? Data else { throw LocketIssue.unavailable }
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        do { return try await read() }
        catch let error as CKError where error.code == .unknownItem {
            let key = Curve25519.KeyAgreement.PrivateKey()
            let record = CKRecord(recordType: "MailboxIdentity", recordID: id)
            record["secret"] = key.rawRepresentation
            do { try await insert(record); return key }
            catch let conflict as CKError where conflict.code == .serverRecordChanged { return try await read() }
        }
    }

    private func wrappingKey(_ me: Curve25519.KeyAgreement.PrivateKey, _ peer: Data) throws -> SymmetricKey {
        let secret = try me.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: peer))
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("Stampnote/book-sharing/v1".utf8),
                                              sharedInfo: Data(), outputByteCount: 32)
    }

    private func syncMailboxes(_ shelf: inout Shelf) async throws {
        guard let own = shelf.books.firstIndex(where: \.mine) else { return }
        let identity = try await identity()
        let publicKey = identity.publicKey.rawRepresentation
        let myID = Storage.key(publicKey.base64EncodedString())
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZone)
        let accepted: Set<String>
        do {
            let share = try await privateDB.record(for: shareID) as? CKShare
            accepted = Set((share?.participants ?? []).compactMap { participant in
                guard participant.acceptanceStatus == .accepted, participant.role != .owner,
                      let name = participant.userIdentity.userRecordID?.recordName else { return nil }
                return zoneKey(.init(zoneName: ownZone.zoneName, ownerName: name))
            })
        } catch let error as CKError where error.code == .unknownItem {
            accepted = []
        }

        // Only mutual readers receive this book's conversation keys. Rotate the current
        // key after removal, retaining older keys so remaining readers can read history.
        let previous = (shelf.books[own].keyring.flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) }) ?? [:]
        let ownerKey = try wrappingKey(identity, publicKey)
        var history = previous[myID].flatMap { unwrap($0, with: ownerKey) } ?? []
        var peers: [String: SymmetricKey] = [:]
        for i in shelf.books.indices where i != own && accepted.contains(shelf.books[i].id) {
            guard let peer = shelf.books[i].mailbox else { continue }
            let key = try wrappingKey(identity, peer)
            peers[Storage.key(peer.base64EncodedString())] = key
            if let ringData = shelf.books[i].keyring,
               let otherRing = try? JSONDecoder().decode([String: Data].self, from: ringData),
               let wrapped = otherRing[myID], let keys = unwrap(wrapped, with: key) {
                shelf.books[i].discussionKey = keys.first
                shelf.books[i].priorDiscussionKeys = Array(keys.dropFirst())
            }
        }
        peers[myID] = ownerKey
        let removed = previous.keys.contains { peers[$0] == nil }
        let rotate = history.isEmpty || removed
        if rotate { history.insert(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, at: 0) }
        var ring = previous.filter { peers[$0.key] != nil }
        let payload = try JSONEncoder().encode(history)
        for (reader, key) in peers where rotate || ring[reader] == nil {
            ring[reader] = try AES.GCM.seal(payload, using: key).combined
        }
        if previous != ring || shelf.books[own].mailbox != publicKey {
            let record = try await privateDB.record(for: .init(recordName: "book", zoneID: ownZone))
            // Do not replace a ring another device published after our last change token.
            guard (record["keyring"] as? Data) == shelf.books[own].keyring else { throw LocketIssue.busy }
            record["mailbox"] = publicKey
            let data = try JSONEncoder().encode(ring)
            record["keyring"] = data
            _ = try await privateDB.save(record)
            shelf.books[own].keyring = data
        }
        shelf.books[own].mailbox = publicKey
        shelf.books[own].discussionKey = history.first
        shelf.books[own].priorDiscussionKeys = Array(history.dropFirst())
    }

    private func unwrap(_ wrapped: Data, with key: SymmetricKey) -> [Data]? {
        guard let box = try? AES.GCM.SealedBox(combined: wrapped),
              let data = try? AES.GCM.open(box, using: key),
              let keys = try? JSONDecoder().decode([Data].self, from: data),
              !keys.isEmpty, keys.allSatisfy({ $0.count == 32 }) else { return nil }
        return keys
    }

    func write(_ action: StampAction, page: Shelf.Page, text: String, id: String, remove: Bool) async throws {
        let shelf = try await refresh()
        let account = try await container.userRecordID().recordName
        guard shelf.account == account, let own = shelf.own, let source = shelf.books.first(where: { $0.id == page.book.id }),
              let stamp = source.stamps.first(where: { $0.id == page.stamp.id }),
              let target = Shelf.Page(book: source, stamp: stamp).activityTarget else { throw LocketIssue.signIn }
        let day = own.day(.now)
        let recordID: String
        switch action {
        case .like: recordID = "like-" + target
        case .pin: recordID = "pin-" + day + "-" + target
        case .comment: recordID = "comment-" + id
        }
        let rid = CKRecord.ID(recordName: recordID, zoneID: ownZone)
        if remove {
            do { _ = try await privateDB.deleteRecord(withID: rid) }
            catch let e as CKError where e.code == .unknownItem {}
            return
        }
        let record = CKRecord(recordType: "StampActivity", recordID: rid)
        record["target"] = target
        record["day"] = day
        if action == .pin {
            guard !source.mine else { return }
            record["kind"] = "pin"
        } else {
            guard let room = source.discussionKey else { throw LocketIssue.mutual }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard action == .like || (1...500).contains(clean.count) else { throw LocketIssue.comment }
            record["kind"] = "note"
            let payload = try JSONEncoder().encode(StampMessage(action: action.rawValue, text: clean))
            record["contents"] = try AES.GCM.seal(payload, using: SymmetricKey(data: room),
                                                  authenticating: Data((target + recordID).utf8)).combined
        }
        do { try await insert(record) }
        catch let e as CKError where e.code == .serverRecordChanged { /* Retried submission. */ }
    }
}

struct StampMessage: Codable {
    let action: String
    let text: String
}
struct StampReply: Identifiable {
    let id: String
    let book: Book
    let activity: BookActivity
    let message: StampMessage
}

extension Shelf {
    func replies(to page: Page) -> [StampReply] {
        guard let source = books.first(where: { $0.id == page.book.id }),
              let stamp = source.stamps.first(where: { $0.id == page.stamp.id }),
              let target = Page(book: source, stamp: stamp).activityTarget, let key = source.discussionKey else { return [] }
        return books.filter { $0.mine || $0.discussionKey != nil }.flatMap { book in
            (book.activities ?? []).compactMap { entry -> StampReply? in
                guard entry.target == target, entry.kind == "note", let data = entry.contents,
                      let box = try? AES.GCM.SealedBox(combined: data),
                      let bytes = ([key] + (source.priorDiscussionKeys ?? [])).lazy.compactMap({ secret in
                          try? AES.GCM.open(box, using: SymmetricKey(data: secret), authenticating: Data((target + entry.id).utf8))
                      }).first,
                      let message = try? JSONDecoder().decode(StampMessage.self, from: bytes) else { return nil }
                return StampReply(id: book.id + "/" + entry.id, book: book, activity: entry, message: message)
            }
        }.sorted { ($0.activity.created, $0.id) < ($1.activity.created, $1.id) }
    }

    func pins(in book: Book, on date: Date) -> [Page] {
        let today = book.day(date)
        let targets = Set((book.activities ?? []).filter { $0.kind == "pin" && $0.day == today }.map(\.target))
        guard !targets.isEmpty else { return [] }
        return books.flatMap { candidate in candidate.stamps.compactMap { stamp in
            let page = Page(book: candidate, stamp: stamp)
            return page.activityTarget.map(targets.contains) == true ? page : nil
        }}.sorted { $0.stamp.posted > $1.stamp.posted }
    }
}
