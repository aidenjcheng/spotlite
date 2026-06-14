import Foundation

actor SpotifyRequestThrottler {
    static let shared = SpotifyRequestThrottler()

    private var lastRequest = Date.distantPast
    private let minGap: TimeInterval = 0.25

    func waitTurn() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minGap {
            try? await Task.sleep(for: .seconds(minGap - elapsed))
        }
        lastRequest = Date()
    }
}
