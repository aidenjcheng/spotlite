import Foundation

/// Skips `null` entries Spotify sometimes returns in paging arrays (notably search playlists).
struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else {
            value = try? container.decode(Value.self)
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let string = try? decode(String.self, forKey: key), let value = Int(string) {
            return value
        }
        return 0
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        return try decodeFlexibleInt(forKey: key)
    }
}

extension SavedTrackItem {
    init(addedAt: String?, track: SpotifyTrack) {
        self.addedAt = addedAt
        self.track = track
        self.item = nil
    }
}
