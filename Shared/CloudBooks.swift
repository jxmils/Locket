import CloudKit
import Foundation

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
            Storage.prune(shelf, at: root)
            return shelf
        }
    }

    private func zoneKey(_ id: CKRecordZone.ID) -> String { Storage.key(id.ownerName + "/" + id.zoneName) }

    private func update(_ book: inout Book, db: CKDatabase, zone: CKRecordZone.ID, root: URL) async throws {
        var token = book.changeToken.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        if token == nil { book.stamps = []; book.author = "" }
        while true {
            do {
                let page = try await db.recordZoneChanges(inZoneWith: zone, since: token)
                for outcome in page.modificationResultsByID.values {
                    let record = try outcome.get().record
                    let id = record.recordID.recordName
                    if record.recordType == "Book" {
                        book.portrait = record["portrait"] as? Data
                        book.author = record["author"] as? String ?? "Friend"
                        book.timeZone = record["timeZone"] as? String ?? "UTC"
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
                token = page.changeToken
                if !page.moreComing { break }
            } catch let e as CKError where e.code == .changeTokenExpired && token != nil {
                token = nil
                book.stamps = []
                book.author = ""
            }
        }
        book.stamps.sort { $0.day > $1.day }
        if let token { book.changeToken = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) }
    }
}
