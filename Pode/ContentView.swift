import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottom) {
            // Bloom is extracted so it only re-renders when its three settings
            // change — not on every player tick or toast.
            BloomLayer(
                accentHex: store.settings.accentHex,
                strength: store.settings.bloomStrength,
                secondary: store.settings.showSecondaryBloom
            )
            .equatable()

            HStack(spacing: 12) {
                Sidebar()
                    .background(GlassBackground(variant: .sidebar))
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 12)

                ZStack {
                    viewSwitch
                        .id(viewIdentifier)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 4)),
                                removal: .opacity
                            )
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.22), value: viewIdentifier)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Toasts
            VStack(spacing: 8) {
                ForEach(store.toasts) { t in
                    Text(t.message)
                        .font(.sans(12.5, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(Ink.onPaper)
                                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 8)
                        )
                }
            }
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)

            PlayerDockView()
        }
    }

    @ViewBuilder
    private var viewSwitch: some View {
        switch store.view {
        case .listenNow: ListenNowView()
        case .browse: BrowseView()
        case .library: LibraryView()
        case .knowledge: KnowledgeView()
        case .settings: SettingsView()
        case .show(let id): ShowDetailView(showId: id)
        case .episode(let id): EpisodeView(episodeId: id)
        }
    }

    /// Animation key. Distinct cases get distinct ids so SwiftUI cross-fades.
    /// We collapse `.show(_)` and `.episode(_)` regardless of id so navigating
    /// between two episodes feels like a content swap, not a full page swap.
    private var viewIdentifier: String {
        switch store.view {
        case .listenNow: return "listen-now"
        case .browse: return "browse"
        case .library: return "library"
        case .knowledge: return "knowledge"
        case .settings: return "settings"
        case .show(let id): return "show-\(id)"
        case .episode(let id): return "episode-\(id)"
        }
    }
}

/// Re-renders only when its inputs change — Equatable view + simple props.
private struct BloomLayer: View, Equatable {
    let accentHex: String
    let strength: Double
    let secondary: Bool

    var body: some View {
        BloomBackdrop(
            accent: Color(hex: accentHex),
            strength: strength,
            secondary: secondary
        )
    }

    static func == (lhs: BloomLayer, rhs: BloomLayer) -> Bool {
        lhs.accentHex == rhs.accentHex &&
        lhs.strength == rhs.strength &&
        lhs.secondary == rhs.secondary
    }
}
