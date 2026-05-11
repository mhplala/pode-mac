import SwiftUI
import SwiftData

@main
struct PodeApp: App {
    let modelContainer: ModelContainer
    @State private var store: AppStore
    /// Long-lived download/transcribe state. Owned at app scope so jobs
    /// survive the user navigating away from the episode page.
    @State private var downloads: DownloadStore
    @State private var transcribes: TranscribeStore

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
            Highlight.self, Concept.self, AppSettingsRecord.self,
            QueueItem.self
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
        let dl = DownloadStore()
        _downloads = State(initialValue: dl)
        _transcribes = State(initialValue: TranscribeStore(downloadStore: dl))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(downloads)
                .environment(transcribes)
                .modelContainer(modelContainer)
                // Min width sized so the Episode page's 2-column layout
                // (header on top + tabs flex + AI 380 + sidebar) always fits.
                // Below this we collapse to 1-col stacked.
                .frame(minWidth: 1080, idealWidth: 1440, minHeight: 760, idealHeight: 920)
                // Pin the app to light mode app-wide. The current visual
                // language (cream paper, orange bloom, dark serif ink) is
                // designed against a light canvas — system Dark Mode would
                // wreck the contrast on glass surfaces and Ink.* tokens.
                // Lift this once a proper dark palette is designed.
                .preferredColorScheme(.light)
                .onAppear {
                    store.attach(modelContainer.mainContext)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
