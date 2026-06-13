import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SpotifyAuthService {
    private(set) var isAuthenticated = false
    private(set) var profile: SpotifyUserProfile?
    private(set) var isLoading = false
    var lastError: String?

    private var codeVerifier: String?
    private var accessToken: String?
    private var refreshToken: String?
    private var expiryDate: Date?

    var clientID: String {
        get { KeychainStore.load(account: SpotifyConfig.KeychainAccount.clientID) ?? SpotifyConfig.defaultClientID }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(account: SpotifyConfig.KeychainAccount.clientID)
            } else {
                try? KeychainStore.save(newValue, account: SpotifyConfig.KeychainAccount.clientID)
            }
        }
    }

    init() {
        restoreSession()
    }

    func restoreSession() {
        accessToken = KeychainStore.load(account: SpotifyConfig.KeychainAccount.accessToken)
        refreshToken = KeychainStore.load(account: SpotifyConfig.KeychainAccount.refreshToken)
        if let expiryString = KeychainStore.load(account: SpotifyConfig.KeychainAccount.expiry),
           let interval = TimeInterval(expiryString) {
            expiryDate = Date(timeIntervalSince1970: interval)
        }
        isAuthenticated = accessToken != nil && refreshToken != nil
    }

    func validAccessToken() async throws -> String {
        if let accessToken, let expiryDate, expiryDate.timeIntervalSinceNow > 60 {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    func beginLogin() throws {
        guard !clientID.isEmpty else { throw SpotifyAPIError.missingClientID }
        lastError = nil
        let verifier = PKCE.generateVerifier()
        codeVerifier = verifier
        let challenge = PKCE.challenge(from: verifier)
        var components = URLComponents(url: SpotifyConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    func handleCallbackURL(_ url: URL) async {
        guard url.scheme == "spotlite", url.host == "callback" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            lastError = "Authorization failed — missing code."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await exchangeCode(code, verifier: verifier)
            profile = try await SpotifyAPIClient(auth: self).fetchProfile()
            isAuthenticated = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isAuthenticated = false
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiryDate = nil
        profile = nil
        isAuthenticated = false
        KeychainStore.delete(account: SpotifyConfig.KeychainAccount.accessToken)
        KeychainStore.delete(account: SpotifyConfig.KeychainAccount.refreshToken)
        KeychainStore.delete(account: SpotifyConfig.KeychainAccount.expiry)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        guard !clientID.isEmpty else { throw SpotifyAPIError.missingClientID }
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "redirect_uri=\(SpotifyConfig.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? SpotifyConfig.redirectURI)",
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "code_verifier=\(verifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verifier)",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let token = try await performTokenRequest(request)
        store(token)
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken else { throw SpotifyAPIError.missingRefreshToken }
        guard !clientID.isEmpty else { throw SpotifyAPIError.missingClientID }
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let token = try await performTokenRequest(request)
        store(token)
        guard let accessToken else { throw SpotifyAPIError.unauthorized }
        return accessToken
    }

    private func performTokenRequest(_ request: URLRequest) async throws -> SpotifyTokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, "Invalid response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAPIError.http(http.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    private func store(_ token: SpotifyTokenResponse) {
        accessToken = token.accessToken
        if let refresh = token.refreshToken {
            refreshToken = refresh
            try? KeychainStore.save(refresh, account: SpotifyConfig.KeychainAccount.refreshToken)
        }
        expiryDate = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        try? KeychainStore.save(token.accessToken, account: SpotifyConfig.KeychainAccount.accessToken)
        if let expiryDate {
            try? KeychainStore.save(String(expiryDate.timeIntervalSince1970), account: SpotifyConfig.KeychainAccount.expiry)
        }
    }
}
