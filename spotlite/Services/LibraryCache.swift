import Foundation

struct CachedLibrarySnapshot: Codable {
    let savedTracks: [SavedTrackItem]
    let playlists: [SpotifyPlaylist]
    let recentlyPlayed: [RecentlyPlayedItem]
    let fetchedAt: Date
}

enum LibraryCache {
    private static let ttl: TimeInterval = 10 * 60

    private static var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spotlite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadSnapshot(maxAge: TimeInterval? = ttl) -> CachedLibrarySnapshot? {
        let url = baseURL.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(CachedLibrarySnapshot.self, from: data) else {
            return nil
        }
        if let maxAge, Date().timeIntervalSince(snapshot.fetchedAt) >= maxAge {
            return nil
        }
        return snapshot
    }

    static func loadSnapshotAllowingStale() -> CachedLibrarySnapshot? {
        loadSnapshot(maxAge: nil)
    }

    static func saveSnapshot(_ snapshot: CachedLibrarySnapshot) {
        let url = baseURL.appendingPathComponent("library.json")
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadPlaylistTracks(id: String, maxAge: TimeInterval? = ttl) -> [PlaylistTrackItem]? {
        let url = baseURL.appendingPathComponent("playlist-\(id).json")
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedPlaylistTracks.self, from: data) else {
            return nil
        }
        if let maxAge, Date().timeIntervalSince(cached.fetchedAt) >= maxAge {
            return nil
        }
        return cached.tracks
    }

    static func loadPlaylistTracksAllowingStale(id: String) -> [PlaylistTrackItem]? {
        loadPlaylistTracks(id: id, maxAge: nil)
    }

    static func savePlaylistTracks(id: String, tracks: [PlaylistTrackItem]) {
        let url = baseURL.appendingPathComponent("playlist-\(id).json")
        let cached = CachedPlaylistTracks(tracks: tracks, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct CachedPlaylistTracks: Codable {
    let tracks: [PlaylistTrackItem]
    let fetchedAt: Date
}
