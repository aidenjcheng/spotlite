import Foundation

// MARK: - Auth

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct SpotifyUserProfile: Decodable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
    let images: [SpotifyImage]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case images
    }
}

// MARK: - Shared

struct SpotifyImage: Decodable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyArtist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let uri: String?
}

struct SpotifyAlbum: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let artists: [SpotifyArtist]?
    let uri: String?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images, artists, uri
        case releaseDate = "release_date"
    }

    var artistNames: String {
        artists?.map(\.name).joined(separator: ", ") ?? ""
    }
}

struct SpotifyTrack: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let durationMs: Int
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let isLocal: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, album
        case durationMs = "duration_ms"
        case isLocal = "is_local"
    }

    init(
        id: String,
        name: String,
        uri: String,
        durationMs: Int,
        artists: [SpotifyArtist],
        album: SpotifyAlbum?,
        isLocal: Bool?
    ) {
        self.id = id
        self.name = name
        self.uri = uri
        self.durationMs = durationMs
        self.artists = artists
        self.album = album
        self.isLocal = isLocal
    }

    var artistNames: String {
        artists.map(\.name).joined(separator: ", ")
    }

    var artworkURL: URL? {
        guard let url = album?.images?.first?.url else { return nil }
        return URL(string: url)
    }
}

struct SavedTrackItem: Decodable, Identifiable {
    let addedAt: String
    let track: SpotifyTrack

    var id: String { track.id }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track
    }
}

struct SpotifyPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let uri: String
    let tracks: PlaylistTrackRef?
    let items: PlaylistTrackRef?

    struct PlaylistTrackRef: Decodable, Hashable {
        let total: Int
    }

    var trackCount: Int {
        (items ?? tracks)?.total ?? 0
    }
}

struct PlaylistTrackItem: Decodable, Identifiable {
    let addedAt: String?
    let track: SpotifyTrack?
    let item: SpotifyTrack?

    /// February 2026 API renamed `track` → `item`.
    var resolvedTrack: SpotifyTrack? { item ?? track }

    var id: String { resolvedTrack?.id ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track, item
    }
}

struct RecentlyPlayedItem: Decodable, Identifiable {
    let track: SpotifyTrack
    let playedAt: String

    var id: String { "\(track.id)-\(playedAt)" }

    enum CodingKeys: String, CodingKey {
        case track
        case playedAt = "played_at"
    }
}

struct SpotifyPaging<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?
    let next: String?
}

struct SpotifySearchResults: Decodable {
    let tracks: SpotifyPaging<SpotifyTrack>?
    let albums: SpotifyPaging<SpotifyAlbum>?
    let artists: SpotifyPaging<SpotifyArtist>?
    let playlists: SpotifyPaging<SpotifyPlaylist>?
}

struct SpotifyQueueResponse: Decodable {
    let currentlyPlaying: SpotifyTrack?
    let queue: [SpotifyTrack]

    enum CodingKeys: String, CodingKey {
        case currentlyPlaying = "currently_playing"
        case queue
    }
}

struct PlayerPlaybackState: Decodable {
    let isPlaying: Bool
    let progressMs: Int?
    let item: SpotifyTrack?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case item
    }
}

// MARK: - Web Playback SDK state (from JS bridge)

struct WebPlaybackState: Decodable {
    let paused: Bool
    let position: Int
    let duration: Int
    let trackWindow: TrackWindow?
    let disallows: Disallows?

    struct TrackWindow: Decodable {
        let currentTrack: PlaybackTrack?
        let nextTracks: [PlaybackTrack]?
        let previousTracks: [PlaybackTrack]?

        enum CodingKeys: String, CodingKey {
            case currentTrack = "current_track"
            case nextTracks = "next_tracks"
            case previousTracks = "previous_tracks"
        }
    }

    struct PlaybackTrack: Decodable {
        let id: String?
        let name: String?
        let uri: String?
        let durationMs: Int?
        let album: SpotifyAlbum?
        let artists: [SpotifyArtist]?

        enum CodingKeys: String, CodingKey {
            case id, name, uri, album, artists
            case durationMs = "duration_ms"
        }
    }

    struct Disallows: Decodable {
        let pausing: Bool?
        let skippingPrev: Bool?

        enum CodingKeys: String, CodingKey {
            case pausing
            case skippingPrev = "skipping_prev"
        }
    }
}

enum SpotifyAPIError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case decoding(Error)
    case missingClientID
    case missingRefreshToken
    case playbackNotReady

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Spotify session expired. Sign in again."
        case .http(let code, let body):
            "Spotify API error (\(code)): \(body)"
        case .decoding(let error):
            "Failed to decode Spotify response: \(error.localizedDescription)"
        case .missingClientID:
            "Add your Spotify Client ID in Settings."
        case .missingRefreshToken:
            "No refresh token. Sign in again."
        case .playbackNotReady:
            "Playback engine is still starting. Try again in a moment."
        }
    }
}
