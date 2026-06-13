import Foundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    let auth: SpotifyAuthService
    let bridge: WebPlaybackBridge

    private(set) var isPlaying = false
    private(set) var positionMs = 0
    private(set) var durationMs = 0
    private(set) var currentTrack: SpotifyTrack?
    private(set) var volume: Double = 0.8
    private(set) var isCurrentTrackSaved = false
    private(set) var queue: [SpotifyTrack] = []
    var lastError: String?

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: auth) }
    private var positionTimer: Timer?
    private var playbackPollTimer: Timer?
    private var didTransferToDevice = false

    init(auth: SpotifyAuthService, bridge: WebPlaybackBridge) {
        self.auth = auth
        self.bridge = bridge
        bridge.setTokenProvider { [auth] in
            try await auth.validAccessToken()
        }
    }

    func startEngine() async {
        guard auth.isAuthenticated else { return }
        do {
            let token = try await auth.validAccessToken()
            await bridge.initialize(with: token)
            if await bridge.waitForDevice(timeoutSeconds: 20) != nil {
                lastError = nil
                bridge.clearError()
                startPlaybackPolling()
            } else {
                lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshTokenForEngine() async {
        guard auth.isAuthenticated else { return }
        do {
            let token = try await auth.validAccessToken()
            await bridge.updateToken(token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncFromBridge() {
        guard let state = bridge.playbackState else { return }
        isPlaying = !state.paused
        positionMs = state.position
        durationMs = max(state.duration, durationMs)
        if let track = state.trackWindow?.currentTrack {
            applyNowPlaying(
                SpotifyTrack(
                    id: track.id ?? track.uri?.replacingOccurrences(of: "spotify:track:", with: "") ?? UUID().uuidString,
                    name: track.name ?? "Unknown",
                    uri: track.uri ?? "",
                    durationMs: track.durationMs ?? state.duration,
                    artists: track.artists ?? [],
                    album: track.album,
                    isLocal: nil
                ),
                playing: !state.paused,
                positionMs: state.position
            )
        }
    }

    func playContext(uri: String, offset: Int? = nil, nowPlaying track: SpotifyTrack? = nil) async {
        if let track { applyNowPlaying(track, playing: true) }
        await play(deviceAction: { try await api.play(deviceID: $0, contextURI: uri, offset: offset) })
        await refreshPlaybackStateFromAPI()
    }

    func playTracks(_ uris: [String], offset: Int = 0, nowPlaying track: SpotifyTrack? = nil) async {
        if let track { applyNowPlaying(track, playing: true) }
        let slice = offset > 0 ? Array(uris.dropFirst(offset)) : uris
        await play(deviceAction: { try await api.play(deviceID: $0, uris: slice) })
        await refreshPlaybackStateFromAPI()
    }

    func playTrack(_ track: SpotifyTrack) async {
        applyNowPlaying(track, playing: true)
        await play(deviceAction: { try await api.play(deviceID: $0, uris: [track.uri]) })
        await refreshPlaybackStateFromAPI()
    }

    func togglePlayPause() async {
        guard let deviceID = await bridge.waitForDevice(timeoutSeconds: 5) else {
            lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            return
        }
        do {
            if isPlaying {
                try await api.pause(deviceID: deviceID)
                isPlaying = false
            } else if currentTrack != nil {
                try await api.play(deviceID: deviceID)
                isPlaying = true
            } else {
                lastError = "Select a track to play."
                return
            }
            clearErrors()
            await refreshPlaybackStateFromAPI()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func next() async {
        await transport { try await api.skipToNext(deviceID: $0) }
        await refreshPlaybackStateFromAPI()
    }

    func previous() async {
        await transport { try await api.skipToPrevious(deviceID: $0) }
        await refreshPlaybackStateFromAPI()
    }

    func seek(to ms: Int) async {
        guard let deviceID = await bridge.waitForDevice(timeoutSeconds: 5) else { return }
        do {
            try await api.seek(deviceID: deviceID, positionMs: ms)
            positionMs = ms
            clearErrors()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setVolume(_ value: Double) async {
        volume = value
        await bridge.setVolume(value)
    }

    func addToQueue(_ track: SpotifyTrack) async {
        do {
            try await api.addToQueue(uri: track.uri)
            try await refreshQueue()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshQueue() async throws {
        let response = try await api.fetchQueue()
        queue = response.queue
        if currentTrack == nil, let playing = response.currentlyPlaying {
            applyNowPlaying(playing, playing: isPlaying)
        }
    }

    func toggleSaveCurrentTrack() async {
        guard let track = currentTrack else { return }
        do {
            if isCurrentTrackSaved {
                try await api.removeTrack(id: track.id)
                isCurrentTrackSaved = false
            } else {
                try await api.saveTrack(id: track.id)
                isCurrentTrackSaved = true
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleSave(track: SpotifyTrack, isSaved: Bool) async -> Bool {
        do {
            if isSaved {
                try await api.removeTrack(id: track.id)
                return false
            } else {
                try await api.saveTrack(id: track.id)
                return true
            }
        } catch {
            lastError = error.localizedDescription
            return isSaved
        }
    }

    func isTrackSaved(id: String) async -> Bool {
        (try? await api.isTrackSaved(id: id)) ?? false
    }

    func clearErrors() {
        lastError = nil
        bridge.clearError()
    }

    func refreshPlaybackStateFromAPI() async {
        guard auth.isAuthenticated else { return }
        do {
            guard let state = try await api.fetchPlayerState(), let track = state.item else { return }
            applyNowPlaying(track, playing: state.isPlaying, positionMs: state.progressMs ?? positionMs)
        } catch {
            // Keep optimistic UI if the player endpoint is briefly empty.
        }
    }

    private func applyNowPlaying(_ track: SpotifyTrack, playing: Bool, positionMs: Int = 0) {
        currentTrack = track
        durationMs = track.durationMs
        isPlaying = playing
        self.positionMs = positionMs
        startPositionTimer()
        Task { await refreshSavedState() }
    }

    private func play(deviceAction: (String) async throws -> Void) async {
        guard let deviceID = await bridge.waitForDevice(timeoutSeconds: 10) else {
            lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            return
        }
        do {
            if !didTransferToDevice {
                try await api.transferPlayback(deviceID: deviceID)
                didTransferToDevice = true
                try await Task.sleep(for: .milliseconds(400))
            }
            try await deviceAction(deviceID)
            clearErrors()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func transport(_ action: (String) async throws -> Void) async {
        guard let deviceID = await bridge.waitForDevice(timeoutSeconds: 5) else { return }
        do {
            try await action(deviceID)
            clearErrors()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshSavedState() async {
        guard let id = currentTrack?.id else { return }
        isCurrentTrackSaved = await isTrackSaved(id: id)
    }

    private func startPlaybackPolling() {
        playbackPollTimer?.invalidate()
        playbackPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshPlaybackStateFromAPI()
            }
        }
        Task { await refreshPlaybackStateFromAPI() }
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        guard isPlaying else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.positionMs = min(self.positionMs + 1000, self.durationMs)
            }
        }
    }

    func stopTimers() {
        positionTimer?.invalidate()
        positionTimer = nil
        playbackPollTimer?.invalidate()
        playbackPollTimer = nil
    }
}
