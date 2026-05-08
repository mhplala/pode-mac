import SwiftUI
import SwiftData
import AppKit

// Reposition the macOS traffic-light buttons. With `.hiddenTitleBar`, the
// system places them at ~ (12, 14) from the top-left of the window, which
// can collide with the panel's top-left corner when the panel is inset by
// 12pt. We push them down + right so they sit comfortably inside whatever
// corner area the panel happens to expose.
private struct TrafficLightPositioner: NSViewRepresentable {
    let target: CGPoint  // desired (x, y) of the close button's origin in title-bar coords (y from bottom)

    func makeCoordinator() -> Coordinator { Coordinator(target: target) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(window: v.window)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.target = target
        context.coordinator.apply()
    }

    final class Coordinator {
        var target: CGPoint
        weak var window: NSWindow?
        private var frameObs: NSKeyValueObservation?

        init(target: CGPoint) { self.target = target }

        func attach(window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            apply()
            // Re-apply on resize — system layout may rewrite button frames.
            frameObs = window.observe(\.frame, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.apply() }
            }
        }

        func apply() {
            guard let window else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = types.compactMap { window.standardWindowButton($0) }
            guard buttons.count == 3 else { return }
            // Preserve native spacing.
            let spacing = max(0, buttons[1].frame.minX - buttons[0].frame.maxX)
            let width = buttons[0].frame.width
            for (i, b) in buttons.enumerated() {
                let x = target.x + CGFloat(i) * (width + spacing)
                b.setFrameOrigin(CGPoint(x: x, y: target.y))
            }
        }
    }
}

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

                ZStack(alignment: .bottom) {
                    viewSwitch
                        .id(viewIdentifier)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 4)),
                                removal: .opacity
                            )
                        )

                    PlayerDockView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.22), value: viewIdentifier)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

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
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(
            // Title-bar coords use NSView default isFlipped = false, so y is
            // measured from the bottom of the title-bar view (height ≈ 28).
            // Native default is y ≈ 6 (centred light). Lower y → lights
            // pushed visually DOWN. We want them sitting on top of the panel,
            // around 22pt from window top → y = 28 - 22 + 7(radius) = 13 ish.
            // After tuning by eye, 4 looks right.
            TrafficLightPositioner(target: CGPoint(x: 22, y: -2))
        )
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
