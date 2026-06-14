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
    private var didTransferToDevice = false
    private var savedStateTrackID: String?
    private var pendingPlay: PendingPlay?

    private struct PendingPlay {
        let expectedTrackID: String?
        let expectedTrackURI: String?
        let startedAt: Date

        var isExpired: Bool {
            Date().timeIntervalSince(startedAt) > 4
        }

        func matches(_ track: SpotifyTrack) -> Bool {
            if let expectedTrackID, track.id == expectedTrackID { return true }
            if let expectedTrackURI, track.uri == expectedTrackURI { return true }
            if expectedTrackID == nil, expectedTrackURI == nil { return true }
            return false
        }

        func shouldIgnore(_ track: SpotifyTrack) -> Bool {
            !isExpired && !matches(track)
        }
    }

    init(auth: SpotifyAuthService, bridge: WebPlaybackBridge) {
        self.auth = auth
        self.bridge = bridge
        bridge.setTokenProvider { [auth] in
            try await auth.validAccessToken()
        }
    }

    /// Called when a new track begins playing (local UI history).
    var onTrackStarted: ((SpotifyTrack) -> Void)?

    func startEngine() async {
        guard auth.isAuthenticated else { return }
        do {
            let token = try await auth.validAccessToken()
            await bridge.initialize(with: token)
            if await bridge.waitForDevice(timeoutSeconds: 20) != nil {
                lastError = nil
                bridge.clearError()
                syncFromBridge()
                await syncNowPlayingFromNetwork()
            } else {
                lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
                await syncNowPlayingFromNetwork()
            }
        } catch {
            lastError = error.localizedDescription
            await syncNowPlayingFromNetwork()
        }
    }

    func restoreFromCache() {
        guard currentTrack == nil, let cached = PlaybackCache.load() else { return }
        currentTrack = cached.track
        isPlaying = cached.isPlaying
        positionMs = cached.positionMs
        durationMs = max(cached.durationMs, cached.track.durationMs)
        savedStateTrackID = cached.track.id
        if isPlaying {
            startPositionTimer()
        }
    }

    func syncNowPlayingFromNetwork() async {
        await refreshPlaybackStateFromAPI()
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

        if let pending = pendingPlay, pending.isExpired {
            pendingPlay = nil
        }

        if let playbackTrack = state.trackWindow?.currentTrack {
            let track = playbackTrack.asSpotifyTrack(fallbackDurationMs: max(durationMs, 1))

            if let pending = pendingPlay, pending.shouldIgnore(track) {
                if currentTrack != nil {
                    isPlaying = true
                    startPositionTimer()
                }
                return
            }

            pendingPlay = nil
            isPlaying = !state.paused
            positionMs = state.position
            if state.duration > 0 {
                durationMs = state.duration
            }
            applyNowPlaying(track, playing: !state.paused, positionMs: state.position)
        } else {
            isPlaying = !state.paused
            positionMs = state.position
            if state.duration > 0 {
                durationMs = state.duration
            }
            if isPlaying {
                startPositionTimer()
            } else {
                positionTimer?.invalidate()
                positionTimer = nil
            }
        }
    }

    func playContext(uri: String, offset: Int? = nil, nowPlaying track: SpotifyTrack? = nil) async {
        if let track { applyNowPlaying(track, playing: true) }
        await play(
            targetTrack: track,
            deviceAction: { try await api.play(deviceID: $0, contextURI: uri, offset: offset) }
        )
        await syncPlaybackAfterTransport()
    }

    func playTracks(_ uris: [String], offset: Int = 0, nowPlaying track: SpotifyTrack? = nil) async {
        if let track { applyNowPlaying(track, playing: true) }
        let slice = offset > 0 ? Array(uris.dropFirst(offset)) : uris
        await play(
            targetTrack: track,
            deviceAction: { try await api.play(deviceID: $0, uris: slice) }
        )
        await syncPlaybackAfterTransport()
    }

    func playTrack(_ track: SpotifyTrack) async {
        applyNowPlaying(track, playing: true)
        await play(
            targetTrack: track,
            deviceAction: { try await api.play(deviceID: $0, uris: [track.uri]) }
        )
        await syncPlaybackAfterTransport()
    }

    func togglePlayPause() async {
        guard let deviceID = await ensureDevice() else {
            lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            return
        }
        do {
            if isPlaying {
                try await api.pause(deviceID: deviceID)
                isPlaying = false
                positionTimer?.invalidate()
                positionTimer = nil
            } else if currentTrack != nil {
                try await api.play(deviceID: deviceID)
                isPlaying = true
                startPositionTimer()
            } else {
                lastError = "Select a track to play."
                return
            }
            clearErrors()
            persistPlaybackState()
            await syncPlaybackAfterTransport()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func next() async {
        await transport { try await api.skipToNext(deviceID: $0) }
        await syncPlaybackAfterTransport()
    }

    func previous() async {
        await transport { try await api.skipToPrevious(deviceID: $0) }
        await syncPlaybackAfterTransport()
    }

    func seek(to ms: Int) async {
        guard let deviceID = await ensureDevice() else { return }
        do {
            try await api.seek(deviceID: deviceID, positionMs: ms)
            positionMs = ms
            clearErrors()
            startPositionTimer()
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

    private func refreshPlaybackStateFromAPI() async {
        guard auth.isAuthenticated else { return }

        for attempt in 0 ..< 3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(600 * attempt))
            }
            do {
                guard let state = try await api.fetchPlayerState(),
                      let track = state.resolvedTrack else {
                    if currentTrack != nil {
                        isPlaying = false
                        positionTimer?.invalidate()
                        persistPlaybackState()
                    }
                    return
                }
                applyNowPlaying(
                    track,
                    playing: state.isPlaying,
                    positionMs: state.progressMs ?? positionMs
                )
                return
            } catch let error as SpotifyAPIError {
                if case .http(429, _) = error, attempt < 2 { continue }
                return
            } catch {
                return
            }
        }
    }

    private func syncPlaybackAfterTransport() async {
        try? await Task.sleep(for: .milliseconds(500))
        syncFromBridge()
        if currentTrack == nil || durationMs <= 0 {
            await refreshPlaybackStateFromAPI()
        }
    }

    private func applyNowPlaying(_ track: SpotifyTrack, playing: Bool, positionMs: Int = 0) {
        let resolved: SpotifyTrack
        if let current = currentTrack, current.id == track.id {
            resolved = track.mergingMetadata(from: current)
        } else {
            resolved = track
        }

        currentTrack = resolved
        if resolved.durationMs > 0 {
            durationMs = resolved.durationMs
        }
        isPlaying = playing
        self.positionMs = positionMs
        startPositionTimer()

        if savedStateTrackID != resolved.id {
            savedStateTrackID = resolved.id
            onTrackStarted?(resolved)
            Task { await refreshSavedState() }
        } else if !resolved.hasArtwork {
            Task { await enrichCurrentTrackArtworkIfNeeded() }
        }

        persistPlaybackState()
    }

    private func persistPlaybackState() {
        guard let track = currentTrack else { return }
        PlaybackCache.save(
            track: track,
            isPlaying: isPlaying,
            positionMs: positionMs,
            durationMs: durationMs
        )
    }

    private func enrichCurrentTrackArtworkIfNeeded() async {
        guard let track = currentTrack, !track.hasArtwork else { return }
        guard let fetched = try? await api.fetchTrack(id: track.id, priority: .background), fetched.hasArtwork else { return }
        currentTrack = track.mergingMetadata(from: fetched)
    }

    private func play(
        targetTrack: SpotifyTrack? = nil,
        deviceAction: (String) async throws -> Void
    ) async {
        pendingPlay = PendingPlay(
            expectedTrackID: targetTrack?.id,
            expectedTrackURI: targetTrack?.uri,
            startedAt: Date()
        )

        guard let deviceID = await ensureDevice() else {
            pendingPlay = nil
            lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            return
        }
        do {
            await bridge.pause()
            positionTimer?.invalidate()

            if !didTransferToDevice {
                try await api.transferPlayback(deviceID: deviceID, play: false)
                didTransferToDevice = true
            } else {
                try? await api.pause(deviceID: deviceID)
            }

            try await deviceAction(deviceID)
            clearErrors()
        } catch {
            pendingPlay = nil
            lastError = error.localizedDescription
            didTransferToDevice = false
        }
    }

    private func transport(_ action: (String) async throws -> Void) async {
        guard let deviceID = await ensureDevice() else {
            lastError = bridge.lastError ?? SpotifyAPIError.playbackNotReady.errorDescription
            return
        }
        do {
            try await action(deviceID)
            clearErrors()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func ensureDevice() async -> String? {
        if let deviceID = bridge.deviceID, bridge.isReady {
            return deviceID
        }
        await startEngine()
        if let deviceID = await bridge.waitForDevice(timeoutSeconds: 15) {
            return deviceID
        }
        await bridge.retryConnection()
        return await bridge.waitForDevice(timeoutSeconds: 10)
    }

    private func refreshSavedState() async {
        guard let id = currentTrack?.id else { return }
        isCurrentTrackSaved = await isTrackSaved(id: id)
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        guard isPlaying else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.positionMs = min(self.positionMs + 1000, max(self.durationMs, 1))
            }
        }
    }

    func stopTimers() {
        positionTimer?.invalidate()
        positionTimer = nil
        persistPlaybackState()
    }

    func clearSession() {
        stopTimers()
        currentTrack = nil
        isPlaying = false
        positionMs = 0
        durationMs = 0
        savedStateTrackID = nil
        pendingPlay = nil
        didTransferToDevice = false
        PlaybackCache.clear()
    }
}
