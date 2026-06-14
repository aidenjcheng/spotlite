import Foundation
import os

/// Signposts for Instruments profiling (SwiftUI template + Points of Interest).
enum PerformanceSignposts {
    private static let signposter = OSSignposter(subsystem: "com.spotlite.app", category: "Performance")

    static func beginBridgeSync() -> OSSignpostIntervalState {
        signposter.beginInterval("BridgeSync")
    }

    static func endBridgeSync(_ state: OSSignpostIntervalState) {
        signposter.endInterval("BridgeSync", state)
    }

    static func beginLibraryRefresh() -> OSSignpostIntervalState {
        signposter.beginInterval("LibraryRefresh")
    }

    static func endLibraryRefresh(_ state: OSSignpostIntervalState) {
        signposter.endInterval("LibraryRefresh", state)
    }

    static func beginArtworkLoad() -> OSSignpostIntervalState {
        signposter.beginInterval("ArtworkLoad")
    }

    static func endArtworkLoad(_ state: OSSignpostIntervalState) {
        signposter.endInterval("ArtworkLoad", state)
    }

    static func emitBridgeStatePublished() {
        signposter.emitEvent("BridgeStatePublished")
    }
}
