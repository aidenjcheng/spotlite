import Foundation

enum SpotifyRequestPriority {
    case userInteractive
    case background
}

enum SpotifyNetworkSession {
    static let shared: URLSession = {
        let cache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    static func apply(_ priority: SpotifyRequestPriority, to request: inout URLRequest) {
        switch priority {
        case .userInteractive:
            request.networkServiceType = .default
            request.cachePolicy = .useProtocolCachePolicy
        case .background:
            request.networkServiceType = .background
            request.cachePolicy = .returnCacheDataElseLoad
        }
    }
}
