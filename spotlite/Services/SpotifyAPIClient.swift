import Foundation

struct SpotifyAPIClient {
    let auth: SpotifyAuthService

    func fetchProfile() async throws -> SpotifyUserProfile {
        try await get("me")
    }

    func fetchRecentlyPlayed(limit: Int = 20) async throws -> [RecentlyPlayedItem] {
        let response: SpotifyPaging<RecentlyPlayedItem> = try await get("me/player/recently-played", query: ["limit": "\(limit)"])
        return response.items
    }

    func fetchSavedTracks(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPaging<SavedTrackItem> {
        try await get("me/tracks", query: ["limit": "\(limit)", "offset": "\(offset)"])
    }

    func fetchPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPaging<SpotifyPlaylist> {
        try await get("me/playlists", query: ["limit": "\(limit)", "offset": "\(offset)"])
    }

    func fetchPlaylistTracks(id: String, limit: Int = 100, offset: Int = 0) async throws -> SpotifyPaging<PlaylistTrackItem> {
        try await get("playlists/\(id)/items", query: ["limit": "\(limit)", "offset": "\(offset)"])
    }

    func fetchAllPlaylistTracks(id: String) async throws -> [PlaylistTrackItem] {
        var all: [PlaylistTrackItem] = []
        var offset = 0
        let pageSize = 100
        while true {
            let page = try await fetchPlaylistTracks(id: id, limit: pageSize, offset: offset)
            all.append(contentsOf: page.items)
            guard page.next != nil, !page.items.isEmpty else { break }
            offset += page.items.count
        }
        return all
    }

    func fetchPlayerState() async throws -> PlayerPlaybackState? {
        let request = try await authorizedRequest(path: "me/player", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 || data.isEmpty { return nil }
        if http.statusCode == 401 { throw SpotifyAPIError.unauthorized }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAPIError.http(http.statusCode, body)
        }
        return try JSONDecoder().decode(PlayerPlaybackState.self, from: data)
    }

    func fetchAlbum(id: String) async throws -> SpotifyAlbum {
        try await get("albums/\(id)")
    }

    func fetchAlbumTracks(id: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifyPaging<SpotifyTrack> {
        try await get("albums/\(id)/tracks", query: ["limit": "\(limit)", "offset": "\(offset)"])
    }

    func fetchArtist(id: String) async throws -> SpotifyArtist {
        try await get("artists/\(id)")
    }

    func fetchArtistTopTracks(id: String) async throws -> [SpotifyTrack] {
        struct Response: Decodable { let tracks: [SpotifyTrack] }
        let response: Response = try await get("artists/\(id)/top-tracks", query: ["market": "US"])
        return response.tracks
    }

    func fetchArtistAlbums(id: String) async throws -> [SpotifyAlbum] {
        let response: SpotifyPaging<SpotifyAlbum> = try await get("artists/\(id)/albums", query: ["include_groups": "album,single", "limit": "50"])
        return response.items
    }

    func search(query: String, types: [String], limit: Int = 20) async throws -> SpotifySearchResults {
        try await get("search", query: [
            "q": query,
            "type": types.joined(separator: ","),
            "limit": "\(limit)",
        ])
    }

    func fetchQueue() async throws -> SpotifyQueueResponse {
        try await get("me/player/queue")
    }

    func addToQueue(uri: String) async throws {
        _ = try await post("me/player/queue", query: ["uri": uri])
    }

    func saveTrack(id: String) async throws {
        _ = try await put("me/tracks", query: ["ids": id])
    }

    func removeTrack(id: String) async throws {
        _ = try await delete("me/tracks", query: ["ids": id])
    }

    func isTrackSaved(id: String) async throws -> Bool {
        let result: [Bool] = try await get("me/tracks/contains", query: ["ids": id])
        return result.first ?? false
    }

    func play(deviceID: String, contextURI: String? = nil, uris: [String]? = nil, offset: Int? = nil) async throws {
        if let contextURI {
            struct ContextBody: Encodable {
                let contextUri: String
                let offset: Offset?

                struct Offset: Encodable { let position: Int }

                enum CodingKeys: String, CodingKey {
                    case contextUri = "context_uri"
                    case offset
                }
            }
            let body = ContextBody(
                contextUri: contextURI,
                offset: offset.map { ContextBody.Offset(position: $0) }
            )
            _ = try await put("me/player/play", query: ["device_id": deviceID], body: body)
        } else if let uris, !uris.isEmpty {
            struct URIsBody: Encodable { let uris: [String] }
            _ = try await put("me/player/play", query: ["device_id": deviceID], body: URIsBody(uris: uris))
        } else {
            _ = try await put("me/player/play", query: ["device_id": deviceID])
        }
    }

    func pause(deviceID: String) async throws {
        _ = try await put("me/player/pause", query: ["device_id": deviceID])
    }

    func skipToNext(deviceID: String) async throws {
        _ = try await post("me/player/next", query: ["device_id": deviceID])
    }

    func skipToPrevious(deviceID: String) async throws {
        _ = try await post("me/player/previous", query: ["device_id": deviceID])
    }

    func seek(deviceID: String, positionMs: Int) async throws {
        _ = try await put("me/player/seek", query: [
            "device_id": deviceID,
            "position_ms": "\(max(positionMs, 0))",
        ])
    }

    func transferPlayback(deviceID: String) async throws {
        struct Body: Encodable {
            let deviceIds: [String]
            let play: Bool

            enum CodingKeys: String, CodingKey {
                case deviceIds = "device_ids"
                case play
            }
        }
        _ = try await put("me/player", body: Body(deviceIds: [deviceID], play: false))
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try await authorizedRequest(path: path, method: "GET", query: query)
        return try await decode(request)
    }

    @discardableResult
    private func put(_ path: String, query: [String: String] = [:]) async throws -> Data {
        let request = try await authorizedRequest(path: path, method: "PUT", query: query)
        return try await raw(request)
    }

    @discardableResult
    private func put<T: Encodable>(_ path: String, query: [String: String] = [:], body: T) async throws -> Data {
        let request = try await authorizedRequest(path: path, method: "PUT", query: query, body: body)
        return try await raw(request)
    }

    @discardableResult
    private func post(_ path: String, query: [String: String] = [:]) async throws -> Data {
        let request = try await authorizedRequest(path: path, method: "POST", query: query)
        return try await raw(request)
    }

    @discardableResult
    private func delete(_ path: String, query: [String: String] = [:]) async throws -> Data {
        let request = try await authorizedRequest(path: path, method: "DELETE", query: query)
        return try await raw(request)
    }

    private func authorizedRequest(
        path: String,
        method: String,
        query: [String: String] = [:]
    ) async throws -> URLRequest {
        let token = try await auth.validAccessToken()
        var components = URLComponents(url: SpotifyConfig.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw SpotifyAPIError.http(-1, "Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func authorizedRequest<T: Encodable>(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: T
    ) async throws -> URLRequest {
        var request = try await authorizedRequest(path: path, method: method, query: query)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await raw(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    private func raw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, "Invalid response")
        }
        if http.statusCode == 401 { throw SpotifyAPIError.unauthorized }
        guard (200 ... 299).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAPIError.http(http.statusCode, body)
        }
        return data
    }
}
