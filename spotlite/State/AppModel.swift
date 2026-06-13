import Foundation
import Observation

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
    var searchQuery = ""
    var searchCategory: SearchCategory = .tracks
    var showQueue = false
    var isLoadingLibrary = false
    var bannerError: String?

    private(set) var recentlyPlayed: [RecentlyPlayedItem] = []
    private(set) var savedTracks: [SavedTrackItem] = []
    private(set) var playlists: [SpotifyPlaylist] = []
    private(set) var searchResults = SpotifySearchResults(tracks: nil, albums: nil, artists: nil, playlists: nil)
    private(set) var savedTrackIDs: Set<String> = []

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: auth) }

    init() {
        playback = PlaybackCoordinator(auth: auth, bridge: bridge)
    }

    func onAppear() async {
        if auth.isAuthenticated {
            await bootstrapSession()
        }
    }

    func onAuthenticated() async {
        await bootstrapSession()
    }

    func bootstrapSession() async {
        await playback.startEngine()
        await loadHome()
        await loadLibrary()
    }

    func loadHome() async {
        do {
            recentlyPlayed = try await api.fetchRecentlyPlayed()
        } catch {
            bannerError = error.localizedDescription
        }
    }

    func loadLibrary() async {
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        do {
            async let tracks = api.fetchSavedTracks(limit: 50)
            async let lists = api.fetchPlaylists(limit: 50)
            let (saved, playlistPage) = try await (tracks, lists)
            savedTracks = saved.items
            playlists = playlistPage.items
            savedTrackIDs = Set(savedTracks.map(\.track.id))
        } catch {
            bannerError = error.localizedDescription
        }
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

    func updateSavedTrackID(_ id: String, saved: Bool) {
        if saved {
            savedTrackIDs.insert(id)
        } else {
            savedTrackIDs.remove(id)
        }
    }
}
