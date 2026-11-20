import SwiftUI
import CloudKit
import WidgetKit

@MainActor
final class Library: ObservableObject {
    static let main = Library()
    lazy var cloud = CloudBooks()
    @Published var shelf = Storage.read()
    @Published var message: String?
    @Published var saving = false

    func refresh(silent: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if Storage.captureTab != nil { return }
        #endif
        do {
            let updated = try await cloud.refresh()
            if updated != shelf {
                shelf = updated
                WidgetCenter.shared.reloadTimelines(ofKind: Storage.widget)
            }
        }
        catch LocketIssue.busy { shelf = Storage.read() }
        catch { shelf = Storage.read(); if !silent { message = error.localizedDescription } }
    }
    func create(_ name: String) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do { try await cloud.createBook(author: name); await refresh() }
        catch { message = error.localizedDescription }
    }
    func publish(_ data: Data) async -> Bool {
        guard !saving, let book = shelf.own else { return false }
        saving = true
        defer { saving = false }
        do {
            let jpeg = try await Task.detached { try Storage.bytes(data, limit: 1600) }.value
            try await cloud.post(jpeg: jpeg, book: book)
        } catch {
            await refresh(silent: true)
            message = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }
    func setPortrait(_ jpeg: Data?, for book: Book) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await cloud.setPortrait(jpeg, for: book)
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do { try await cloud.accept(metadata); await refresh() }
        catch { message = error.localizedDescription }
    }
}

final class ShareScene: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let share = options.cloudKitShareMetadata { Task { await Library.main.accept(share) } }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await Library.main.accept(metadata) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = ShareScene.self
        return config
    }
}

@main
struct LocketApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library = Library.main
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Home().environmentObject(library)
                .task(id: phase) {
                    guard phase == .active else { return }
                    while !Task.isCancelled {
                        await library.refresh(silent: true)
                        do { try await Task.sleep(for: .seconds(120)) } catch { return }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    Task { await library.refresh() }
                }
        }
    }
}
