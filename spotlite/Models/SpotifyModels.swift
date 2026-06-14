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

struct SpotifyImage: Codable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyArtist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let uri: String?

    static func == (lhs: SpotifyArtist, rhs: SpotifyArtist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SpotifyAlbum: Codable, Identifiable, Hashable {
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

    static func == (lhs: SpotifyAlbum, rhs: SpotifyAlbum) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SpotifyTrack: Codable, Identifiable, Hashable {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? "spotify:track:\(id)"
        durationMs = try container.decodeFlexibleInt(forKey: .durationMs)
        artists = try container.decodeIfPresent([SpotifyArtist].self, forKey: .artists) ?? []
        album = try container.decodeIfPresent(SpotifyAlbum.self, forKey: .album)
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(uri, forKey: .uri)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(artists, forKey: .artists)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(isLocal, forKey: .isLocal)
    }

    var artistNames: String {
        artists.map(\.name).joined(separator: ", ")
    }

    var artworkURL: URL? {
        guard let url = album?.images?.first?.url else { return nil }
        return URL(string: url)
    }

    var hasArtwork: Bool { artworkURL != nil }

    func mergingMetadata(from other: SpotifyTrack) -> SpotifyTrack {
        SpotifyTrack(
            id: id,
            name: (!name.isEmpty && name != "Unknown") ? name : other.name,
            uri: uri.isEmpty ? other.uri : uri,
            durationMs: durationMs > 0 ? durationMs : other.durationMs,
            artists: artists.isEmpty ? other.artists : artists,
            album: Self.preferredAlbum(album, other.album),
            isLocal: isLocal ?? other.isLocal
        )
    }

    private static func preferredAlbum(_ current: SpotifyAlbum?, _ other: SpotifyAlbum?) -> SpotifyAlbum? {
        let currentHasImages = current?.images?.isEmpty == false
        let otherHasImages = other?.images?.isEmpty == false
        if currentHasImages { return current }
        if otherHasImages { return other }
        return current ?? other
    }
}

struct SavedTrackItem: Codable, Identifiable {
    let addedAt: String?
    let track: SpotifyTrack?
    let item: SpotifyTrack?

    var resolvedTrack: SpotifyTrack? { item ?? track }

    var id: String { resolvedTrack?.id ?? addedAt ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track, item
    }
}

struct SpotifyPlaylist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let uri: String
    let tracks: PlaylistTrackRef?
    let items: PlaylistTrackRef?

    struct PlaylistTrackRef: Codable, Hashable {
        let total: Int
    }

    var trackCount: Int {
        (items ?? tracks)?.total ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, images, uri, tracks, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = Self.decodeFlexibleString(from: container, forKey: .description)
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images)
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? "spotify:playlist:\(id)"
        tracks = try container.decodeIfPresent(PlaylistTrackRef.self, forKey: .tracks)
        items = try container.decodeIfPresent(PlaylistTrackRef.self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encode(uri, forKey: .uri)
        if let items {
            try container.encode(items, forKey: .items)
        } else if let tracks {
            try container.encode(tracks, forKey: .tracks)
        }
    }

    static func == (lhs: SpotifyPlaylist, rhs: SpotifyPlaylist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        return nil
    }
}

struct PlaylistTrackItem: Codable, Identifiable {
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

struct RecentlyPlayedItem: Codable, Identifiable {
    let track: SpotifyTrack?
    let item: SpotifyTrack?
    let playedAt: String

    var resolvedTrack: SpotifyTrack? { item ?? track }

    var id: String { "\(resolvedTrack?.id ?? playedAt)-\(playedAt)" }

    init(track: SpotifyTrack, playedAt: String) {
        self.track = track
        self.item = nil
        self.playedAt = playedAt
    }

    enum CodingKeys: String, CodingKey {
        case track, item
        case playedAt = "played_at"
    }
}

struct SpotifyPaging<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?
    let next: String?

    enum CodingKeys: String, CodingKey {
        case items, total, next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wrapped = try container.decodeIfPresent([FailableDecodable<T>].self, forKey: .items) ?? []
        items = wrapped.compactMap(\.value)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
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
    let track: SpotifyTrack?

    var resolvedTrack: SpotifyTrack? { item ?? track }

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case item, track
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        progressMs = try container.decodeFlexibleIntIfPresent(forKey: .progressMs)
        item = try container.decodeIfPresent(SpotifyTrack.self, forKey: .item)
        track = try container.decodeIfPresent(SpotifyTrack.self, forKey: .track)
    }
}

// MARK: - Web Playback SDK state (from JS bridge)

struct WebPlaybackState: Decodable {
    let paused: Bool
    let position: Int
    let duration: Int
    let trackWindow: TrackWindow?

    init(paused: Bool, position: Int, duration: Int, trackWindow: TrackWindow?) {
        self.paused = paused
        self.position = position
        self.duration = duration
        self.trackWindow = trackWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paused = try container.decode(Bool.self, forKey: .paused)
        position = try container.decodeFlexibleInt(forKey: .position)
        duration = try container.decodeFlexibleInt(forKey: .duration)
        trackWindow = try container.decodeIfPresent(TrackWindow.self, forKey: .trackWindow)
    }

    enum CodingKeys: String, CodingKey {
        case paused, position, duration
        case trackWindow = "track_window"
    }

    var currentTrackIdentity: String? {
        trackWindow?.currentTrack?.id ?? trackWindow?.currentTrack?.uri
    }

    /// Whether this state change should trigger SwiftUI / coordinator sync (skip position-only ticks while playing).
    func shouldPublishRevision(comparedTo previous: WebPlaybackState?) -> Bool {
        guard let previous else { return true }
        if paused != previous.paused { return true }
        if duration != previous.duration { return true }
        if currentTrackIdentity != previous.currentTrackIdentity { return true }
        if paused, abs(position - previous.position) > 250 { return true }
        return false
    }

    struct TrackWindow: Decodable {
        let currentTrack: PlaybackTrack?
        let nextTracks: [PlaybackTrack]?
        let previousTracks: [PlaybackTrack]?

        init(currentTrack: PlaybackTrack?, nextTracks: [PlaybackTrack]?, previousTracks: [PlaybackTrack]?) {
            self.currentTrack = currentTrack
            self.nextTracks = nextTracks
            self.previousTracks = previousTracks
        }

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

        init(
            id: String?,
            name: String?,
            uri: String?,
            durationMs: Int?,
            album: SpotifyAlbum?,
            artists: [SpotifyArtist]?
        ) {
            self.id = id
            self.name = name
            self.uri = uri
            self.durationMs = durationMs
            self.album = album
            self.artists = artists
        }

        enum CodingKeys: String, CodingKey {
            case id, name, uri, album, artists
            case durationMs = "duration_ms"
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
        case .http(429, _):
            "Spotify rate limit reached. Wait a moment and try again."
        case .http(let code, let body):
            "Spotify API error (\(code)): \(body)"
        case .decoding(let error):
            if let decoding = error as? DecodingError {
                "Failed to decode Spotify response: \(Self.describe(decoding))"
            } else {
                "Failed to decode Spotify response: \(error.localizedDescription)"
            }
        case .missingClientID:
            "Add your Spotify Client ID in Settings."
        case .missingRefreshToken:
            "No refresh token. Sign in again."
        case .playbackNotReady:
            "Playback engine is still starting. Try again in a moment."
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "Missing '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            context.debugDescription
        @unknown default:
            error.localizedDescription
        }
    }
}
