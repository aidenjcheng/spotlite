import Foundation

enum SpotifyConfig {
    /// Fallback when nothing is saved in Keychain. Spotify Client IDs are public (PKCE); not a secret.
    static let defaultClientID = "e0f1acfa5b2a4ee28f8a54792c094d08"

    static let redirectURI = "spotlite://callback"
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBaseURL = URL(string: "https://api.spotify.com/v1")!

    static let scopes = [
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-library-read",
        "user-library-modify",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-recently-played",
    ].joined(separator: " ")

    enum KeychainAccount {
        static let clientID = "spotify_client_id"
        static let accessToken = "spotify_access_token"
        static let refreshToken = "spotify_refresh_token"
        static let expiry = "spotify_token_expiry"
    }
}
