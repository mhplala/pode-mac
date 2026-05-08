import SwiftUI
import SwiftData

@main
struct PodeApp: App {
    let modelContainer: ModelContainer
    @State private var store: AppStore

    init() {
        // Generous URLCache so cover artwork doesn't refetch every time the
        // grid scrolls back into view. AsyncImage uses the shared session.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,        // 64 MB in-memory
            diskCapacity: 256 * 1024 * 1024,         // 256 MB on disk
            diskPath: "pode-url-cache"
        )

        let schema = Schema([
            Show.self, Episode.self, TranscriptLineModel.self,
            Highlight.self, Concept.self, AppSettingsRecord.self
        ])
        let config = ModelConfiguration("Pode", schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to set up SwiftData container: \(error)")
        }
        let player = AudioPlayerStore()
        let app = AppStore(player: player)
        _store = State(initialValue: app)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .modelContainer(modelContainer)
                .frame(minWidth: 1100, idealWidth: 1440, minHeight: 720, idealHeight: 900)
                .onAppear {
                    store.attach(modelContainer.mainContext)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
