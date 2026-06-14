import Foundation

enum WebPlaybackStateParser {
    static func parse(_ dict: [String: Any]) -> WebPlaybackState? {
        guard let paused = dict["paused"] as? Bool else { return nil }

        let position = intValue(dict["position"])
        let duration = intValue(dict["duration"])
        let trackWindow = parseTrackWindow(dict["track_window"] as? [String: Any])

        return WebPlaybackState(
            paused: paused,
            position: position,
            duration: duration,
            trackWindow: trackWindow
        )
    }

    private static func parseTrackWindow(_ dict: [String: Any]?) -> WebPlaybackState.TrackWindow? {
        guard let dict else { return nil }
        return WebPlaybackState.TrackWindow(
            currentTrack: parseTrack(dict["current_track"] as? [String: Any]),
            nextTracks: nil,
            previousTracks: nil
        )
    }

    private static func parseTrack(_ dict: [String: Any]?) -> WebPlaybackState.PlaybackTrack? {
        guard let dict else { return nil }
        let artists = (dict["artists"] as? [[String: Any]])?.compactMap(parseArtist)
        return WebPlaybackState.PlaybackTrack(
            id: dict["id"] as? String ?? spotifyID(from: dict["uri"] as? String, prefix: "spotify:track:"),
            name: dict["name"] as? String,
            uri: dict["uri"] as? String,
            durationMs: intValue(dict["duration_ms"]),
            album: parseAlbum(dict["album"] as? [String: Any]),
            artists: artists
        )
    }

    private static func parseArtist(_ dict: [String: Any]) -> SpotifyArtist? {
        guard let name = dict["name"] as? String else { return nil }
        let uri = dict["uri"] as? String
        let id = (dict["id"] as? String) ?? spotifyID(from: uri, prefix: "spotify:artist:") ?? name
        return SpotifyArtist(id: id, name: name, images: nil, uri: uri)
    }

    private static func parseAlbum(_ dict: [String: Any]?) -> SpotifyAlbum? {
        guard let dict,
              let name = dict["name"] as? String else { return nil }
        let uri = dict["uri"] as? String
        let id = (dict["id"] as? String) ?? spotifyID(from: uri, prefix: "spotify:album:") ?? name
        let images = (dict["images"] as? [[String: Any]])?.compactMap { imageDict -> SpotifyImage? in
            guard let url = imageDict["url"] as? String else { return nil }
            return SpotifyImage(
                url: url,
                width: intValue(imageDict["width"]),
                height: intValue(imageDict["height"])
            )
        }
        return SpotifyAlbum(
            id: id,
            name: name,
            images: images,
            artists: nil,
            uri: uri,
            releaseDate: dict["release_date"] as? String
        )
    }

    private static func spotifyID(from uri: String?, prefix: String) -> String? {
        guard let uri, uri.hasPrefix(prefix) else { return nil }
        let id = String(uri.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let int as Int:
            int
        case let double as Double:
            Int(double)
        default:
            0
        }
    }
}

extension WebPlaybackState.PlaybackTrack {
    func asSpotifyTrack(fallbackDurationMs: Int) -> SpotifyTrack {
        SpotifyTrack(
            id: id ?? uri?.replacingOccurrences(of: "spotify:track:", with: "") ?? UUID().uuidString,
            name: name ?? "Unknown",
            uri: uri ?? "",
            durationMs: durationMs ?? fallbackDurationMs,
            artists: artists ?? [],
            album: album,
            isLocal: nil
        )
    }
}
