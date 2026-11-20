import AppIntents
import WidgetKit

struct NextStamp: AppIntent {
    static let title: LocalizedStringResource = "Next friend’s stamp"
    static let openAppWhenRun = false
    @Parameter(title: "Current stamp") var current: String
    init() {}
    init(current: String) { self.current = current }
    func perform() async throws -> some IntentResult {
        Storage.selectedPage = Shelf.nextID(current, in: Storage.read().mail.map(\.id))
        WidgetCenter.shared.reloadTimelines(ofKind: Storage.widget)
        return .result()
    }
}
