import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum LocketIssue: LocalizedError {
    case signIn, busy, photo, used, name, unavailable, mutual, comment
    var errorDescription: String? {
        switch self {
        case .mutual: "Share your books with each other to leave likes and comments."
        case .comment: "Write a comment between 1 and 500 characters."
        case .signIn: "Sign in to iCloud in Settings to use your stamp book."
        case .busy: "Your book is updating. Try again in a moment."
        case .photo: "That photo couldn’t be opened. Try another one."
        case .used: "Today’s stamp is already in your book."
        case .name: "Enter a name for your book."
        case .unavailable: "Your shared storage is unavailable. Check the app’s signing configuration."
        }
    }
}

enum Storage {
    static let group = "group.com.jasonmiller.Locket"
    static let widget = "FriendsStamps"
    #if DEBUG && targetEnvironment(simulator)
    static var captureTab: String? { ProcessInfo.processInfo.environment["LOCKET_CAPTURE_TAB"] }
    #endif

    static var root: URL? {
        #if DEBUG && targetEnvironment(simulator)
        if captureTab != nil {
            return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("LocketCapture")
        }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func read() -> Shelf {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("books.json")),
              let shelf = try? JSONDecoder().decode(Shelf.self, from: data) else { return Shelf() }
        return shelf
    }

    static func write(_ shelf: Shelf, to root: URL) throws {
        try JSONEncoder().encode(shelf).write(to: root.appendingPathComponent("books.json"), options: .atomic)
    }

    // The widget and the app can refresh at the same time. Only one may advance zone tokens.
    static func withWriter<T>(_ work: (URL) async throws -> T) async throws -> T {
        guard let root else { throw LocketIssue.unavailable }
        let fd = open(root.appendingPathComponent("writer.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LocketIssue.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw LocketIssue.busy }
        defer { flock(fd, LOCK_UN) }
        return try await work(root)
    }

    static func bytes(_ image: Data, limit: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: limit
              ] as CFDictionary) else { throw LocketIssue.photo }
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw LocketIssue.photo }
        CGImageDestinationAddImage(output, bitmap, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw LocketIssue.photo }
        return data as Data
    }

    static func prune(_ shelf: Shelf, at root: URL) {
        let retained = Set(shelf.books.flatMap { $0.stamps.flatMap { [$0.photo, $0.thumbnail] } })
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == "jpg" && !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static var selectedPage: String? {
        get { UserDefaults(suiteName: group)?.string(forKey: "widget.page") }
        set { UserDefaults(suiteName: group)?.set(newValue, forKey: "widget.page") }
    }
}
