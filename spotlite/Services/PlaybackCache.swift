import Foundation

struct CachedPlaybackState: Codable {
    let track: SpotifyTrack
    let isPlaying: Bool
    let positionMs: Int
    let durationMs: Int
    let savedAt: Date
}

enum PlaybackCache {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spotlite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("playback.json")
    }

    static func load() -> CachedPlaybackState? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedPlaybackState.self, from: data) else {
            return nil
        }
        return cached
    }

    static func save(track: SpotifyTrack, isPlaying: Bool, positionMs: Int, durationMs: Int) {
        let cached = CachedPlaybackState(
            track: track,
            isPlaying: isPlaying,
            positionMs: positionMs,
            durationMs: durationMs,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
