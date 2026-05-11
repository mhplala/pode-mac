import Foundation
import AppKit
import MediaPlayer

/// Bridges Pode's player to two systems-level "press to play" surfaces:
///
/// 1. **MPRemoteCommandCenter** — macOS routes physical media keys
///    (Touch Bar, the F8 / "play" key on the keyboard, AirPods click,
///    Bluetooth headphone controls, Control Center "Now Playing", lock
///    screen) through this command center. Without subscribing here,
///    those keys do nothing for Pode.
///
/// 2. **NSEvent local monitor for Space key** — when the app window has
///    focus and the user isn't typing into a text field, pressing the
///    space bar toggles playback. The monitor checks the key window's
///    first responder and bails if it's any kind of text view, so it
///    doesn't steal space from search / settings / ask inputs.
///
/// Also keeps `MPNowPlayingInfoCenter` populated so Now Playing widgets
/// (Control Center, Touch Bar dial, Apple Watch) show the current
/// episode title / show / artwork-via-show.
///
/// Not annotated `@MainActor` because AppStore (its owner) isn't either.
/// The handlers themselves hop to main via `Task { @MainActor }` before
/// touching player state, so thread-safety is preserved at the boundary.
final class MediaCommandsService {
    private weak var player: AudioPlayerStore?
    private var spaceMonitor: Any?
    private var isHookedUp = false

    /// Latest episode + show, used to fill Now Playing info. Set from
    /// AppStore.startPlaying so the data is fresh for the system UI.
    var currentTitle: String = ""
    var currentArtist: String = ""

    func attach(player: AudioPlayerStore) {
        guard !isHookedUp else { return }
        self.player = player
        installRemoteCommands(player: player)
        installSpaceMonitor(player: player)
        isHookedUp = true
    }

    // MARK: - Remote commands

    private func installRemoteCommands(player: AudioPlayerStore) {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.play() }
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.pause() }
            return .success
        }

        // The physical Play/Pause key on Apple keyboards goes through
        // togglePlayPauseCommand specifically, not playCommand. Wiring
        // both gives us the widest coverage.
        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.toggle() }
            return .success
        }

        cc.skipForwardCommand.preferredIntervals = [30]
        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.skip(30) }
            return .success
        }

        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.skip(-15) }
            return .success
        }

        // The transport keys on some Macs come through next/previous
        // commands instead of skip — map those to ±15s too as a
        // reasonable default.
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.skip(30) }
            return .success
        }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor [weak player] in player?.skip(-15) }
            return .success
        }

        // The Now Playing scrubber drags route through this command.
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak player] in
                player?.commitSeek(to: event.positionTime)
            }
            return .success
        }
    }

    // MARK: - Space bar

    private func installSpaceMonitor(player: AudioPlayerStore) {
        // Local monitor fires for events delivered TO this app while it's
        // the front app. Returning nil swallows the event; returning the
        // original lets it propagate (typing into a TextField, etc).
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak player] event in
            // 49 is the macOS virtual key code for the space bar.
            guard event.keyCode == 49 else { return event }
            // Modifier-laden space (cmd-space for Spotlight etc.) is not ours.
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            guard mods.isEmpty else { return event }

            // Bail when a text field / text view owns the first responder.
            // The user is typing — they want a literal space character.
            if let win = NSApp.keyWindow, Self.isTextInput(win.firstResponder) {
                return event
            }

            // Otherwise, eat the event and toggle playback. Returning nil
            // prevents the system beep that would normally fire when the
            // key has nowhere to go.
            Task { @MainActor [weak player] in player?.toggle() }
            return nil
        }
    }

    /// True if the responder is part of a text-editing chain. We check
    /// against the NSText class and NSTextView (the editor that NSTextField
    /// uses internally) — that covers TextField, TextEditor, SecureField,
    /// and AppKit text fields embedded via NSViewRepresentable.
    private static func isTextInput(_ responder: NSResponder?) -> Bool {
        var r: NSResponder? = responder
        while let cur = r {
            if cur is NSText || cur is NSTextView { return true }
            // SwiftUI's TextField is hosted in an NSHostingView; the actual
            // editor is an NSTextView further up the chain.
            r = cur.nextResponder
        }
        return false
    }

    // MARK: - Now Playing info

    /// Push the current episode + show into Now Playing so the system UI
    /// (Control Center, Apple Watch, lock screen, Touch Bar) reflects
    /// what Pode is playing.
    func updateNowPlaying(
        title: String,
        artist: String,
        duration: Double,
        currentTime: Double,
        rate: Double,
        isPlaying: Bool
    ) {
        currentTitle = title
        currentArtist = artist
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0
        ]
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    /// Clear Now Playing info when nothing is loaded. Stops the system UI
    /// from showing a stale "Pode" entry.
    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
