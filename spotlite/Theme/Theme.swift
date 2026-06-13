import SwiftUI

enum SpotliteTheme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let elevated = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let accent = Color(red: 0.12, green: 0.84, blue: 0.38)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let divider = Color.white.opacity(0.08)
}

extension View {
    func spotliteScreenBackground() -> some View {
        background(SpotliteTheme.background)
    }
}

func formatDuration(ms: Int) -> String {
    let totalSeconds = max(ms, 0) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
