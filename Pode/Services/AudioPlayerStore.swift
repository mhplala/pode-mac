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
        isPlaying = true
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

    func seek(to seconds: Double) {
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
