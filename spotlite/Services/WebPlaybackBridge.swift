import Foundation
import Observation
import os
import WebKit

private let logger = Logger(subsystem: "com.spotlite.app", category: "WebPlayback")

@MainActor
@Observable
final class WebPlaybackBridge: NSObject {
    private(set) var deviceID: String?
    private(set) var isReady = false
    private(set) var playbackState: WebPlaybackState?
    private(set) var stateRevision = 0
    var lastError: String?

    let webView: WKWebView

    private var pendingToken: String?
    private var tokenProvider: (() async throws -> String)?
    private var pageLoaded = false
    private var playerStarted = false

    func clearError() {
        lastError = nil
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0
        super.init()
        controller.add(self, name: "spotlite")
        webView.navigationDelegate = self
        loadHTML()
    }

    func setTokenProvider(_ provider: @escaping () async throws -> String) {
        tokenProvider = provider
    }

    func loadHTML() {
        guard let fileURL = Bundle.main.url(forResource: "WebPlayback", withExtension: "html"),
              let html = try? String(contentsOf: fileURL, encoding: .utf8) else {
            lastError = "WebPlayback.html missing from bundle."
            logger.error("WebPlayback.html missing from bundle")
            return
        }
        // HTTPS base URL so the SDK script loads reliably (file:// origins often break this).
        let baseURL = URL(string: "https://spotlite.local/")!
        webView.loadHTMLString(html, baseURL: baseURL)
        logger.info("Loading Web Playback HTML")
    }

    func initialize(with token: String) async {
        pendingToken = token
        logger.info("initialize(with:) token length \(token.count)")
        await startPlayerIfPossible()
    }

    func updateToken(_ token: String) async {
        pendingToken = token
        await evaluate("setToken('\(escaped(token))')")
    }

    func togglePlay() async { await evaluate("togglePlay()") }
    func resume() async { await evaluate("resume()") }
    func pause() async { await evaluate("pause()") }
    func nextTrack() async { await evaluate("nextTrack()") }
    func previousTrack() async { await evaluate("previousTrack()") }

    func seek(to ms: Int) async {
        await evaluate("seek(\(ms))")
    }

    func setVolume(_ value: Double) async {
        await evaluate("setVolume(\(value))")
    }

    func waitForDevice(timeoutSeconds: TimeInterval = 15) async -> String? {
        if let deviceID, isReady { return deviceID }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let deviceID, isReady { return deviceID }
            if let token = pendingToken {
                await startPlayerIfPossible()
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.error("Timed out waiting for playback device")
        return nil
    }

    func retryConnection() async {
        playerStarted = false
        deviceID = nil
        isReady = false
        await evaluate("disconnectPlayer()")
        if let token = pendingToken {
            await startPlayerIfPossible()
        }
    }

    private func startPlayerIfPossible() async {
        guard let token = pendingToken else { return }
        guard pageLoaded else {
            logger.info("HTML not loaded yet; token queued")
            return
        }
        guard !playerStarted else { return }
        playerStarted = true
        await evaluate("initPlayer('\(escaped(token))')")
    }

    private func deliverFreshToken() async {
        guard let tokenProvider else { return }
        do {
            let token = try await tokenProvider()
            pendingToken = token
            await evaluate("deliverToken('\(escaped(token))')")
        } catch {
            lastError = error.localizedDescription
            logger.error("Token refresh failed: \(error.localizedDescription)")
        }
    }

    private func evaluate(_ script: String) async {
        do {
            let result = try await webView.evaluateJavaScript(script)
            if let result {
                logger.debug("JS: \(String(describing: result))")
            }
        } catch {
            logger.error("JS evaluate failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    private func escaped(_ token: String) -> String {
        token.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private static func isIgnorablePlaybackError(_ message: String) -> Bool {
        message.contains("no list was loaded")
    }

    private func decodePlaybackState(from dict: [String: Any]) -> WebPlaybackState? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(WebPlaybackState.self, from: data)
    }

    private func publishStateRevision() {
        stateRevision += 1
        PerformanceSignposts.emitBridgeStatePublished()
    }
}

extension WebPlaybackBridge: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "log":
                if let msg = body["message"] as? String {
                    logger.info("JS: \(msg)")
                }
            case "sdk_ready":
                pageLoaded = true
                logger.info("SDK ready message received")
                await startPlayerIfPossible()
            case "get_token":
                await deliverFreshToken()
            case "ready":
                deviceID = body["deviceId"] as? String
                isReady = deviceID != nil
                publishStateRevision()
                clearError()
                logger.info("Device ready: \(self.deviceID ?? "nil")")
            case "not_ready":
                isReady = false
                logger.warning("Device not ready")
            case "state":
                let previous = playbackState
                if let stateDict = body["state"] as? [String: Any] {
                    playbackState = WebPlaybackStateParser.parse(stateDict)
                        ?? decodePlaybackState(from: stateDict)
                } else {
                    playbackState = nil
                }
                if playbackState?.shouldPublishRevision(comparedTo: previous) != false {
                    publishStateRevision()
                }
            case "error":
                let message = body["message"] as? String ?? "unknown"
                logger.error("JS error: \(message)")
                if Self.isIgnorablePlaybackError(message) { return }
                lastError = message
            default:
                break
            }
        }
    }
}

extension WebPlaybackBridge: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            pageLoaded = true
            logger.info("WebPlayback page finished loading")
            await startPlayerIfPossible()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            logger.error("Navigation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            logger.error("Provisional navigation failed: \(error.localizedDescription)")
        }
    }
}
