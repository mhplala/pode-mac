import SwiftUI
import AppKit
import ImageIO

/// Process-wide in-memory cache for podcast cover artwork. Sits *in front of*
/// `URLCache.shared` (configured in `PodeApp.init` for 64 MB RAM + 256 MB
/// disk). The two caches do different jobs:
///
/// - `URLCache` stores compressed bytes. Hits avoid the network but still
///   pay decode cost on every render.
/// - `ImageMemoryCache` stores already-decoded `NSImage` objects keyed by
///   URL, **downsampled** to a target pixel cap. Hits are zero-cost —
///   the image renders synchronously on the first frame, no async, no
///   flicker, no task spin-up, AND no holding a 1200×1200 source at full
///   res for a 48 pt thumbnail.
///
/// Together: scrolling covers in the Browse / Library / Listen Now grids
/// stays at 60 fps after the first appearance, without the cache silently
/// growing to a gigabyte in RAM.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    /// Largest cover we render anywhere in the app is ~220 pt
    /// (Browse grid tiles, ListenNow hero). On 2× Retina that's
    /// 440 px. 512 leaves a hair of headroom for sharper resampling
    /// when the source is bigger than the target.
    static let maxPixelSize: Int = 512

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 400                  // up to 400 covers
        c.totalCostLimit = 64 * 1024 * 1024 // 64 MB decoded-pixel data
        return c
    }()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Store the decoded image. `cost` should be the DECODED pixel
    /// byte count (width × height × 4), NOT the compressed source
    /// length — otherwise NSCache thinks a 1200×1200 cover costs
    /// 120 KB when it actually occupies 5.7 MB, and the cache grows
    /// well past `totalCostLimit` before any eviction.
    func store(_ image: NSImage, for url: URL, cost: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Decode `data` into a downsampled `NSImage` plus its accurate
    /// in-memory cost in bytes. Uses ImageIO's thumbnail path which
    /// is dramatically cheaper than letting AppKit decode the full
    /// resolution and then resizing.
    static func decode(data: Data) -> (image: NSImage, cost: Int)? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg  = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else {
            // Fallback to the AppKit decoder. Should never happen in
            // practice; covers JPEG/PNG/WEBP fine via ImageIO.
            if let img = NSImage(data: data) {
                let cost = Int(img.size.width * img.size.height) * 4
                return (img, max(cost, 16_384))
            }
            return nil
        }
        let size = NSSize(width: cg.width, height: cg.height)
        let img  = NSImage(cgImage: cg, size: size)
        let cost = cg.width * cg.height * 4   // RGBA8 bytes per pixel
        return (img, cost)
    }
}

/// Drop-in replacement for `AsyncImage` that takes a synchronous fast-path
/// when the URL is already in `ImageMemoryCache`. Falls through to the same
/// `URLSession.shared` (and therefore the same `URLCache` disk layer) on a
/// miss, then promotes the result into the memory cache.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let animation: Animation?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?

    init(
        url: URL?,
        animation: Animation? = .easeOut(duration: 0.32),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.animation = animation
        self.content = content
        self.placeholder = placeholder
        // Fast-path: if the cover is already decoded in RAM, hand it to
        // SwiftUI synchronously so the very first frame shows the artwork
        // (no flicker, no .empty phase).
        if let url, let cached = ImageMemoryCache.shared.image(for: url) {
            _nsImage = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
            }
        }
        // CRITICAL: SwiftUI reuses view identity in LazyVGrid/LazyVStack —
        // when the row gets recycled with a *different* episode, our `init`
        // does NOT re-run, so `nsImage` still holds the previous episode's
        // decoded artwork until the async task swaps it. Result: visibly
        // wrong covers for a few hundred ms after every scroll.
        //
        // `.onChange(of: url)` fixes that by re-priming `nsImage` from the
        // cache (or clearing it to `nil` so the placeholder shows) the
        // moment the URL changes — same logic as `init`, but on every URL
        // mutation. `.task(id: url)` then fills the gap from network if
        // the cache missed.
        .onChange(of: url) { _, newURL in
            if let newURL, let cached = ImageMemoryCache.shared.image(for: newURL) {
                nsImage = cached
            } else {
                nsImage = nil
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }

        // Sync hit (e.g. set by another view between init and task).
        if nsImage == nil, let cached = ImageMemoryCache.shared.image(for: url) {
            await MainActor.run { nsImage = cached }
            return
        }
        if nsImage != nil { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Bail if the URL changed under us during the await — without
            // this, a stale request can resolve after the user scrolled
            // and overwrite the new (correct) cover with the previous one.
            guard !Task.isCancelled else { return }
            guard let decoded = ImageMemoryCache.decode(data: data) else { return }
            ImageMemoryCache.shared.store(decoded.image, for: url, cost: decoded.cost)
            await MainActor.run {
                // One more identity check on the main actor: by the time
                // we apply, the view may be displaying yet another URL.
                guard self.url == url else { return }
                if let animation {
                    withAnimation(animation) { nsImage = decoded.image }
                } else {
                    nsImage = decoded.image
                }
            }
        } catch {
            // Swallow — the placeholder (gradient + glyph) stays visible.
        }
    }
}
