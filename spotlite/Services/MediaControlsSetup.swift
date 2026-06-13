import AppKit
import MediaPlayer

@MainActor
enum MediaControlsSetup {
    static func configure(model: AppModel) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { _ in
            Task { @MainActor in
                if !model.playback.isPlaying { await model.playback.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in
                if model.playback.isPlaying { await model.playback.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in await model.playback.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in await model.playback.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in await model.playback.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                await model.playback.seek(to: Int(event.positionTime * 1000))
            }
            return .success
        }
    }

    static func updateNowPlaying(model: AppModel) {
        guard let track = model.playback.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyPlaybackDuration: Double(model.playback.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(model.playback.positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: model.playback.isPlaying ? 1 : 0,
        ]
        if let url = track.artworkURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = NSImage(data: data) {
                    await MainActor.run {
                        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    }
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
