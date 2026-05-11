import SwiftUI
import AppKit

// MARK: - Tokens

enum Ink {
    static let primary = Color(.sRGB, white: 0, opacity: 0.95)
    static let secondary = Color(hex: "#615d59")
    static let tertiary = Color(hex: "#87857f")
    static let muted = Color(hex: "#a39e98")
    static let onPaper = Color(hex: "#141413")
    static let dark = Color(hex: "#1f1f1d")
}

enum Brand {
    static let orange = Color(hex: "#d06a3a")
    static let orange700 = Color(hex: "#8e3d18")
}

enum Success {
    static let primary = Color(hex: "#1f7a4c")
}

enum Danger {
    static let primary = Color(hex: "#b53333")
}

extension Font {
    /// New York for Latin, with PingFang SC as the cascade fallback for CJK.
    /// SwiftUI's stock `.system(design: .serif)` falls back to a Songti-style
    /// serif for Chinese, which we don't want — we want sans (PingFang) for CJK.
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let nsWeight = NSFontWeight.from(weight)
        let baseDesc = NSFont.systemFont(ofSize: size, weight: nsWeight)
            .fontDescriptor
            .withDesign(.serif) ?? NSFont.systemFont(ofSize: size, weight: nsWeight).fontDescriptor

        // PingFang SC at the same point size is appended to the cascade list.
        // The OS consults this list when the primary font lacks a glyph (i.e.
        // for CJK characters, since New York doesn't ship CJK glyphs).
        let pingfang = NSFontDescriptor(fontAttributes: [.name: "PingFangSC-Regular"])
        let cascaded = baseDesc.addingAttributes([
            .cascadeList: [pingfang]
        ])
        if let nsFont = NSFont(descriptor: cascaded, size: size) {
            return Font(nsFont)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private enum NSFontWeight {
    static func from(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

// MARK: - Brand accent (driven by Settings → AppSettings.accentHex)

/// Live brand accent. Bound by `ContentView` from `settings.accentHex` so the
/// accent picker actually changes the UI. Views read via:
///     @Environment(\.brandAccent) private var accent
/// Falls back to the static `Brand.orange` when no environment is set.
private struct BrandAccentKey: EnvironmentKey {
    static let defaultValue: Color = Brand.orange
}

extension EnvironmentValues {
    var brandAccent: Color {
        get { self[BrandAccentKey.self] }
        set { self[BrandAccentKey.self] = newValue }
    }
}

// MARK: - Glass

enum GlassVariant {
    case panel, sidebar, chip, dock, deep, tile
}

// Liquid-glass surfaces. We use `.ultraThinMaterial` (most translucent) and
// only a very faint white tint on top so the bloom + canvas read through
// the panel. Inner highlight border + a single soft shadow give depth.
struct GlassBackground: View {
    let variant: GlassVariant

    var body: some View {
        let r = cornerRadiusFor(variant)
        let tint: Color = variant == .sidebar ? Color(hex: "#fcfaf7") : .white
        let tintOpacity: Double = {
            switch variant {
            case .panel:   return 0.18
            case .sidebar: return 0.22
            case .chip:    return 0.20
            case .dock:    return 0.22
            case .deep:    return 0.10
            case .tile:    return 0.10
            }
        }()
        Group {
            switch variant {
            case .panel, .sidebar, .dock:
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(tint.opacity(tintOpacity))
                    )
            case .chip:
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(tintOpacity)))
            case .deep:
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(tint.opacity(tintOpacity))
                    )
            case .tile:
                // Repeated grid surfaces → no live material blur. A flat
                // translucent fill over the bloom is visually almost
                // indistinguishable but ~10× cheaper on a 4×N Browse grid.
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(tint.opacity(tintOpacity * 0.5))
                    )
            }
        }
        // Inner-highlight border — the white stroke that makes glass read.
        .overlay(
            shape
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        // Single soft warm shadow. Skip on tiles (24 shadows in a grid is
        // a measurable hit) — the cover art's own shadow gives them depth.
        .shadow(
            color: Color(hex: "#3c2814").opacity(variant == .tile ? 0 : 0.10),
            radius: variant == .tile ? 0 : 16,
            x: 0, y: variant == .tile ? 0 : 8
        )
    }

    private var shape: AnyShape {
        switch variant {
        case .chip: return AnyShape(Capsule())
        default:
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadiusFor(variant), style: .continuous))
        }
    }

    private func cornerRadiusFor(_ v: GlassVariant) -> CGFloat {
        switch v {
        // Sidebar's top-left corner has the macOS traffic-light buttons sitting
        // on top of it. We deliberately keep this radius small so the buttons
        // (centred near 12, 14) sit *inside* the curve concentrically — match
        // Apple's Finder / Notes style.
        case .sidebar: return 12
        case .panel, .dock: return 18
        case .deep: return 14
        case .tile: return 28
        case .chip: return 999
        }
    }
}

struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path
    init<S: Shape>(_ s: S) { _path = { s.path(in: $0) } }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

extension View {
    func glass(_ variant: GlassVariant) -> some View {
        background(GlassBackground(variant: variant))
    }
}

// MARK: - Glass scroll
//
// Wraps a ScrollView with hidden system indicators and an overlaid
// ultraThinMaterial thumb, matching the rest of the liquid-glass surfaces.

struct GlassScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var contentH: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var viewportH: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                content()
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: GlassScrollMetricsKey.self,
                                value: GlassScrollMetrics(
                                    offsetY: -inner.frame(in: .named("glassScroll")).origin.y,
                                    contentH: inner.size.height
                                )
                            )
                        }
                    )
            }
            .coordinateSpace(name: "glassScroll")
            .scrollIndicators(.hidden)
            .onPreferenceChange(GlassScrollMetricsKey.self) { m in
                offsetY = m.offsetY
                contentH = m.contentH
            }
            .onAppear { viewportH = outer.size.height }
            .onChange(of: outer.size.height) { _, new in viewportH = new }
            .overlay(alignment: .topTrailing) {
                if contentH > viewportH + 4 {
                    let thumbH = max(48, viewportH * (viewportH / contentH))
                    let maxOffset = max(1, contentH - viewportH)
                    let progress = max(0, min(1, offsetY / maxOffset))
                    let thumbY = progress * (viewportH - thumbH)
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.18)))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        )
                        .frame(width: hovering ? 8 : 5, height: thumbH)
                        .offset(x: -4, y: thumbY)
                        .animation(.easeOut(duration: 0.12), value: hovering)
                        .onHover { hovering = $0 }
                }
            }
        }
    }
}

private struct GlassScrollMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentH: CGFloat = 0
}

private struct GlassScrollMetricsKey: PreferenceKey {
    static var defaultValue = GlassScrollMetrics()
    static func reduce(value: inout GlassScrollMetrics, nextValue: () -> GlassScrollMetrics) {
        value = nextValue()
    }
}

// MARK: - Cover

struct CoverView: View {
    let artworkUrl: String?
    let title: String
    /// Hard size cap when `fill = false` (default). Also used as a hint for
    /// the gradient-fallback glyph font when `fill = false`.
    var size: CGFloat = 56
    var radius: CGFloat = 12
    var playing: Bool = false
    /// When true, ignore `size` for framing and let the cover fill its
    /// container as a 1:1 square. Use in grid cells where the parent already
    /// constrains width and you want the artwork to span the cell.
    var fill: Bool = false

    var body: some View {
        let (c1, c2) = Fmt.colorsFor(title)
        ZStack {
            gradientFallback(c1: c1, c2: c2)

            if let url = artworkUrl, !url.isEmpty, let u = URL(string: url) {
                // CachedImage hits the in-memory NSCache synchronously on
                // init, so a cover that's already been seen renders on the
                // first frame with zero flicker. AsyncImage didn't —
                // it always spun up an async Task and replayed the
                // .empty → .success transition, which is what looked like
                // "re-loading" even though URLCache was warm.
                CachedImage(url: u) { img in
                    img.resizable().scaledToFill()
                        .transition(.opacity)
                } placeholder: {
                    Color.clear
                }
            }

            if playing {
                bars
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(
            maxWidth: fill ? .infinity : size,
            maxHeight: fill ? .infinity : size
        )
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private func gradientFallback(c1: Color, c2: Color) -> some View {
        // Glyph + radial sized off the actual rendered dimensions when
        // `fill: true` so the fallback character scales with the cover.
        // Otherwise we use the explicit `size` hint (cheaper than a
        // GeometryReader when the size is known up front).
        if fill {
            GeometryReader { geo in
                let dim = min(geo.size.width, geo.size.height)
                ZStack {
                    LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [Color.white.opacity(0.3), .clear],
                                   center: .topLeading,
                                   startRadius: 0, endRadius: dim * 0.7)
                    Text(Fmt.glyph(for: title))
                        .font(.serif(dim * 0.5, weight: .medium))
                        .italic()
                        .foregroundColor(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                }
            }
        } else {
            ZStack {
                LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.3), .clear], center: .topLeading, startRadius: 0, endRadius: size * 0.7)
                Text(Fmt.glyph(for: title))
                    .font(.serif(size * 0.5, weight: .medium))
                    .italic()
                    .foregroundColor(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            }
        }
    }

    private var bars: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                BarsAnim(delay: Double(i) * 0.08)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 14)
        .background(
            Capsule().fill(Color.black.opacity(0.45))
        )
    }
}

private struct BarsAnim: View {
    let delay: Double
    @State private var on = false
    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: on ? 12 : 4)
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Ink.onPaper)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(13, weight: .semibold))
            .foregroundColor(Ink.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.85 : 0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

struct GhostSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(12, weight: .medium))
            .foregroundColor(Ink.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0.04))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(12.5, weight: .medium))
            .foregroundColor(configuration.isPressed ? Brand.orange : Ink.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

struct PlayMiniStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(0.95))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Brand.orange : Ink.onPaper)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct IconBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Ink.secondary)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.85 : 0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Eyebrow / mono labels

struct EyebrowText: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10.5, weight: .semibold))
            .tracking(1.3)
            .foregroundColor(Ink.tertiary)
    }
}

struct MetaMono: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(11))
            .foregroundColor(Ink.tertiary)
    }
}

struct BadgeSoft: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.sans(10.5, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Brand.orange.opacity(0.1))
        )
        .foregroundColor(Brand.orange700)
    }
}

// MARK: - Bloom backdrop

struct BloomBackdrop: View {
    let accent: Color
    let strength: Double
    let secondary: Bool

    var body: some View {
        ZStack {
            // Paper canvas — opaque base, no transparency
            Color(hex: "#f6f3ee")
            LinearGradient(
                colors: [Color(hex: "#f5e6d8").opacity(0.6), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            LinearGradient(
                colors: [.clear, Color(hex: "#efe7df").opacity(0.5)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Primary terracotta bloom — RadialGradient does its own blur
            // cheaper than `.blur(radius:)` which is a Gaussian GPU pass.
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.55), accent.opacity(0.20), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 420
                        )
                    )
                    .frame(width: 720, height: 720)
                    .position(x: geo.size.width - 60, y: 240)
                    .opacity(strength * 0.65)

                if secondary {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#e8c79e").opacity(0.55),
                                         Color(hex: "#e8c79e").opacity(0.18),
                                         .clear],
                                center: .center,
                                startRadius: 40,
                                endRadius: 380
                            )
                        )
                        .frame(width: 640, height: 640)
                        .position(x: -40, y: geo.size.height - 80)
                        .opacity(strength * 0.5)
                }
            }
        }
        // Rasterize the entire backdrop into a single Metal-backed offscreen
        // layer. Materials sit on top and only blur this one cheap layer.
        .drawingGroup(opaque: true, colorMode: .extendedLinear)
        .ignoresSafeArea()
    }
}

// MARK: - Pill segmented

struct Pill<T: Hashable>: View {
    let value: T
    @Binding var selection: T
    let label: String

    var body: some View {
        Button {
            selection = value
        } label: {
            Text(label)
                .font(.sans(12.5, weight: selection == value ? .semibold : .medium))
                .foregroundColor(selection == value ? Ink.primary : Ink.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selection == value ? Color.white.opacity(0.95) : .clear)
                        .shadow(color: selection == value ? .black.opacity(0.06) : .clear, radius: 2, x: 0, y: 1)
                )
                // Make the entire pill rectangle clickable, not just the
                // text glyphs — fixes "I clicked but nothing happened".
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PillBar<T: Hashable>: View {
    let items: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                Pill(value: item.value, selection: $selection, label: item.label)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}
