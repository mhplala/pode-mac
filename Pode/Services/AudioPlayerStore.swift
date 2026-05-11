import Foundation
import AVFoundation
import Observation

@Observable
final class AudioPlayerStore {
    private(set) var currentEpisodeID: String?
    private(set) var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    private(set) var errorMessage: String?

    /// User-controlled playback speed. AVPlayer's `rate` is also the
    /// "is playing" signal (rate == 0 ⇒ paused), so we keep our preferred
    /// rate separately here and only push it onto AVPlayer when playing.
    /// Stored as Double so it round-trips cleanly through AppSettings.
    var playbackRate: Double = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    var onPositionChanged: ((_ episodeID: String, _ time: Double, _ duration: Double) -> Void)?
    var onFinished: ((_ episodeID: String) -> Void)?
    var onWillStop: ((_ episodeID: String, _ time: Double, _ duration: Double) -> Void)?

    func load(episodeID: String, source: URL, startAt: Double = 0) {
        teardown()
        let item = AVPlayerItem(url: source)
        let player = AVPlayer(playerItem: item)
        self.player = player
        currentEpisodeID = episodeID
        errorMessage = nil
        currentTime = startAt
        duration = 0

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if let dur = self.player?.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                self.duration = dur
            }
            if let id = self.currentEpisodeID {
                self.onPositionChanged?(id, self.currentTime, self.duration)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            if let id = self.currentEpisodeID {
                self.onFinished?(id)
            }
        }

        if startAt > 0 {
            seek(to: startAt)
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        // AVPlayer.play() forces rate=1.0; re-apply the user's chosen
        // rate after so the speed preference survives pause/play cycles.
        if playbackRate != 1.0 {
            player.rate = Float(playbackRate)
        }
        isPlaying = true
    }

    /// Update playback speed. If we're currently playing, push the new
    /// rate onto AVPlayer immediately; if paused, just store it — the
    /// next `play()` will apply it.
    func setPlaybackRate(_ newRate: Double) {
        playbackRate = newRate
        if isPlaying {
            player?.rate = Float(newRate)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        if let id = currentEpisodeID {
            onWillStop?(id, currentTime, duration)
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Default seek — uses a small tolerance (250ms each side) so AVPlayer
    /// doesn't burn cycles on precise frame-accurate seeks. Good for
    /// click-to-seek, transcript line jumps, +/- 15s skips.
    func seek(to seconds: Double) {
        seek(to: seconds, tolerance: CMTime(seconds: 0.25, preferredTimescale: 600))
    }

    /// Variant for high-frequency seeks (live scrubbing). Larger tolerance =
    /// faster decoder catch-up, less stutter while the user drags.
    func seek(to seconds: Double, tolerance: CMTime) {
        guard let player else { return }
        let target = max(0, seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = target
    }

    /// Final commit — frame-accurate landing point after a drag ends.
    func commitSeek(to seconds: Double) {
        guard let player else { return }
        let target = max(0, seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    func setError(_ msg: String?) { errorMessage = msg }

    func teardown() {
        if let id = currentEpisodeID {
            onWillStop?(id, currentTime, duration)
        }
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let end = endObserver { NotificationCenter.default.removeObserver(end); endObserver = nil }
        player?.pause()
        player = nil
        isPlaying = false
    }
}
