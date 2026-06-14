import Foundation
import Observation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case liked = "Liked Songs"
    case playlists = "Playlists"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .liked: "heart.fill"
        case .playlists: "music.note.list"
        }
    }
}

enum SearchCategory: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppModel {
    let auth = SpotifyAuthService()
    let bridge = WebPlaybackBridge()
    private(set) var playback: PlaybackCoordinator

    var selectedSection: SidebarSection = .home
    var detailPath = NavigationPath()
    var searchQuery = ""
    var searchCategory: SearchCategory = .tracks
    var showQueue = false
    var isLoadingLibrary = false
    var bannerError: String?

    private(set) var recentlyPlayed: [RecentlyPlayedItem] = []
    private(set) var savedTracks: [SavedTrackItem] = []
    private(set) var playlists: [SpotifyPlaylist] = []
    private(set) var searchResults = SpotifySearchResults(tracks: nil, albums: nil, artists: nil, playlists: nil)
    private var savedTrackIDs: Set<String> = []
    private var saveStatuses: [String: TrackSaveStatus] = [:]

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: auth) }

    func saveStatus(for trackID: String) -> TrackSaveStatus {
        if let existing = saveStatuses[trackID] {
            return existing
        }
        let status = TrackSaveStatus(trackID: trackID, isSaved: savedTrackIDs.contains(trackID))
        saveStatuses[trackID] = status
        return status
    }

    init() {
        playback = PlaybackCoordinator(auth: auth, bridge: bridge)
        playback.onTrackStarted = { [weak self] track in
            self?.recordLocalPlay(track)
        }
    }

    func onAppear() async {
        if auth.isAuthenticated {
            playback.restoreFromCache()
            restoreLibraryFromCache(allowStale: true)
            await bootstrapSession()
        }
    }

    func onAuthenticated() async {
        playback.restoreFromCache()
        restoreLibraryFromCache(allowStale: true)
        await bootstrapSession()
    }

    func bootstrapSession() async {
        async let library: Void = loadLibrary(forceRefresh: false)
        await playback.startEngine()
        await library
        try? await Task.sleep(for: .seconds(1))
        await loadHome()
    }

    func loadHome() async {
        let local = recentlyPlayed
        do {
            let apiItems = try await api.fetchRecentlyPlayed(priority: .userInteractive)
            recentlyPlayed = Self.mergeRecentlyPlayed(api: apiItems, local: local)
            persistLibraryCache()
        } catch {
            if recentlyPlayed.isEmpty {
                recentlyPlayed = local
            }
            if recentlyPlayed.isEmpty {
                bannerError = error.localizedDescription
            }
            if isRateLimit(error), recentlyPlayed.isEmpty {
                Task { await retryRecentlyPlayedLater() }
            }
        }
        await enrichRecentlyPlayedArtwork()
        prefetchArtwork(from: recentlyPlayed.compactMap(\.resolvedTrack))
    }

    func recordLocalPlay(_ track: SpotifyTrack) {
        let playedAt = ISO8601DateFormatter().string(from: Date())
        let entry = RecentlyPlayedItem(track: track, playedAt: playedAt)
        var merged = recentlyPlayed.filter { $0.resolvedTrack?.id != track.id }
        merged.insert(entry, at: 0)
        recentlyPlayed = Array(merged.prefix(50))
        persistLibraryCache()
        if !track.hasArtwork {
            Task { await enrichRecentlyPlayedArtwork() }
        }
    }

    private func enrichRecentlyPlayedArtwork() async {
        var updated = recentlyPlayed
        var changed = false

        for index in updated.indices {
            guard let track = updated[index].resolvedTrack, !track.hasArtwork else { continue }
            guard let fetched = try? await api.fetchTrack(id: track.id, priority: .background), fetched.hasArtwork else { continue }
            updated[index] = RecentlyPlayedItem(
                track: track.mergingMetadata(from: fetched),
                playedAt: updated[index].playedAt
            )
            changed = true
            try? await Task.sleep(for: .milliseconds(120))
        }

        if changed {
            recentlyPlayed = updated
            persistLibraryCache()
        }
    }

    private static func mergeRecentlyPlayed(
        api: [RecentlyPlayedItem],
        local: [RecentlyPlayedItem]
    ) -> [RecentlyPlayedItem] {
        var bestByID: [String: RecentlyPlayedItem] = [:]

        for item in api + local {
            guard let id = item.resolvedTrack?.id else { continue }
            if let existing = bestByID[id] {
                bestByID[id] = preferredRecentlyPlayed(existing, item)
            } else {
                bestByID[id] = item
            }
        }

        return Array(bestByID.values.sorted { $0.playedAt > $1.playedAt }.prefix(50))
    }

    private static func preferredRecentlyPlayed(_ lhs: RecentlyPlayedItem, _ rhs: RecentlyPlayedItem) -> RecentlyPlayedItem {
        let lhsHasArt = lhs.resolvedTrack?.hasArtwork == true
        let rhsHasArt = rhs.resolvedTrack?.hasArtwork == true

        if lhsHasArt != rhsHasArt {
            return lhsHasArt ? lhs : rhs
        }
        if lhs.playedAt != rhs.playedAt {
            return lhs.playedAt > rhs.playedAt ? lhs : rhs
        }
        if let lhsTrack = lhs.resolvedTrack, let rhsTrack = rhs.resolvedTrack {
            let mergedTrack = lhsTrack.mergingMetadata(from: rhsTrack)
            return RecentlyPlayedItem(track: mergedTrack, playedAt: max(lhs.playedAt, rhs.playedAt))
        }
        return lhs
    }

    func loadLibrary(forceRefresh: Bool = false) async {
        if !forceRefresh, restoreLibraryFromCache(allowStale: false) {
            Task { await refreshLibraryFromNetwork() }
            return
        }

        await refreshLibraryFromNetwork()
    }

    func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        do {
            searchResults = try await api.search(
                query: query,
                types: ["track", "album", "artist", "playlist"]
            )
        } catch {
            bannerError = error.localizedDescription
        }
    }

    func syncPlaybackFromBridge() {
        let interval = PerformanceSignposts.beginBridgeSync()
        defer { PerformanceSignposts.endBridgeSync(interval) }

        playback.syncFromBridge()
        MediaControlsSetup.updateNowPlaying(model: self)
    }

    func clearBanner() {
        bannerError = nil
        playback.clearErrors()
    }

    var activeErrorMessage: String? {
        bannerError ?? playback.lastError ?? bridge.lastError
    }

    func setTrackSaved(_ id: String, saved: Bool) {
        if saved {
            savedTrackIDs.insert(id)
        } else {
            savedTrackIDs.remove(id)
        }
        saveStatus(for: id).isSaved = saved
    }

    func selectSection(_ section: SidebarSection) {
        if section != selectedSection {
            detailPath = NavigationPath()
        }
        selectedSection = section
    }

    func openPlaylist(_ playlist: SpotifyPlaylist) {
        selectedSection = .playlists
        detailPath.append(playlist)
    }

    func openAlbum(_ album: SpotifyAlbum) {
        detailPath.append(album)
    }

    func openArtist(_ artist: SpotifyArtist) {
        detailPath.append(artist)
    }

    func openPlaylistFromSearch(_ playlist: SpotifyPlaylist) {
        detailPath.append(playlist)
    }

    private func refreshLibraryFromNetwork() async {
        let interval = PerformanceSignposts.beginLibraryRefresh()
        defer { PerformanceSignposts.endLibraryRefresh(interval) }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        var errors: [String] = []

        async let playlistsTask: Result<SpotifyPaging<SpotifyPlaylist>, Error> = {
            do {
                return .success(try await api.fetchPlaylists(limit: 50, priority: .userInteractive))
            } catch {
                return .failure(error)
            }
        }()
        async let savedTracksTask: Result<SpotifyPaging<SavedTrackItem>, Error> = {
            do {
                return .success(try await api.fetchSavedTracks(limit: 50, priority: .userInteractive))
            } catch {
                return .failure(error)
            }
        }()

        switch await playlistsTask {
        case .success(let page):
            playlists = page.items
            prefetchArtworkURLs(page.items.compactMap { $0.images?.first?.url }.compactMap(URL.init(string:)))
        case .failure(let error):
            errors.append("Playlists: \(error.localizedDescription)")
        }

        switch await savedTracksTask {
        case .success(let page):
            savedTracks = page.items.filter { $0.resolvedTrack != nil }
            applySavedTrackIDs(Set(savedTracks.compactMap { $0.resolvedTrack?.id }))
            prefetchArtwork(from: savedTracks.compactMap(\.resolvedTrack))
        case .failure(let error):
            errors.append("Liked songs: \(error.localizedDescription)")
            if isRateLimit(error) {
                Task { await retryLikedSongsLater() }
            }
        }

        if !playlists.isEmpty || !savedTracks.isEmpty {
            persistLibraryCache()
        }

        do {
            let apiItems = try await api.fetchRecentlyPlayed(priority: .background)
            recentlyPlayed = Self.mergeRecentlyPlayed(api: apiItems, local: recentlyPlayed)
            persistLibraryCache()
            prefetchArtwork(from: recentlyPlayed.compactMap(\.resolvedTrack))
            Task { await enrichRecentlyPlayedArtwork() }
        } catch let error where isRateLimit(error) {
            Task { await retryRecentlyPlayedLater() }
        } catch {
            errors.append("Recently played: \(error.localizedDescription)")
        }

        if playlists.isEmpty && savedTracks.isEmpty {
            bannerError = errors.joined(separator: " ")
        } else if !errors.isEmpty {
            bannerError = errors.joined(separator: " ")
        } else {
            bannerError = nil
        }
    }

    @discardableResult
    private func restoreLibraryFromCache(allowStale: Bool) -> Bool {
        let cached = allowStale ? LibraryCache.loadSnapshotAllowingStale() : LibraryCache.loadSnapshot()
        guard let cached else { return false }
        savedTracks = cached.savedTracks
        playlists = cached.playlists
        recentlyPlayed = cached.recentlyPlayed
        applySavedTrackIDs(Set(savedTracks.compactMap { $0.resolvedTrack?.id }))
        prefetchArtwork(from: savedTracks.compactMap(\.resolvedTrack))
        prefetchArtwork(from: recentlyPlayed.compactMap(\.resolvedTrack))
        prefetchArtworkURLs(playlists.compactMap { $0.images?.first?.url }.compactMap(URL.init(string:)))
        return !savedTracks.isEmpty || !playlists.isEmpty || !recentlyPlayed.isEmpty
    }

    private func applySavedTrackIDs(_ ids: Set<String>) {
        savedTrackIDs = ids
        for (trackID, status) in saveStatuses {
            status.isSaved = ids.contains(trackID)
        }
    }

    private func prefetchArtwork(from tracks: [SpotifyTrack]) {
        prefetchArtworkURLs(tracks.compactMap(\.artworkURL))
    }

    private func prefetchArtworkURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { await ArtworkCache.shared.prefetch(urls: urls) }
    }

    private func persistLibraryCache() {
        LibraryCache.saveSnapshot(
            CachedLibrarySnapshot(
                savedTracks: savedTracks,
                playlists: playlists,
                recentlyPlayed: recentlyPlayed,
                fetchedAt: Date()
            )
        )
    }

    private func isRateLimit(_ error: Error) -> Bool {
        if case SpotifyAPIError.http(429, _) = error { return true }
        return false
    }

    private func retryRecentlyPlayedLater() async {
        try? await Task.sleep(for: .seconds(12))
        do {
            let local = recentlyPlayed
            let apiItems = try await api.fetchRecentlyPlayed(priority: .background)
            recentlyPlayed = Self.mergeRecentlyPlayed(api: apiItems, local: local)
            persistLibraryCache()
        } catch {
            // Local history remains visible.
        }
    }

    private func retryLikedSongsLater() async {
        try? await Task.sleep(for: .seconds(10))
        do {
            let page = try await api.fetchSavedTracks(limit: 50, priority: .background)
            savedTracks = page.items.filter { $0.resolvedTrack != nil }
            applySavedTrackIDs(Set(savedTracks.compactMap { $0.resolvedTrack?.id }))
            prefetchArtwork(from: savedTracks.compactMap(\.resolvedTrack))
            persistLibraryCache()
            if !savedTracks.isEmpty, bannerError?.contains("Liked songs") == true {
                bannerError = nil
            }
        } catch {
            // Keep playlists visible; user can refresh manually.
        }
    }
}
