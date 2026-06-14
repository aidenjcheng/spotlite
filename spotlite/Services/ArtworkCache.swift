import AppKit
import CryptoKit
import Foundation

actor ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession
    private let diskDirectory: URL
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskDirectory = base.appendingPathComponent("SpotliteArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)

        memory.countLimit = 300
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        if let diskImage = loadFromDisk(url: url) {
            storeInMemory(diskImage, for: url)
            return diskImage
        }
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task { await loadImage(for: url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            guard memory.object(forKey: url as NSURL) == nil,
                  loadFromDisk(url: url) == nil,
                  inFlight[url] == nil else { continue }
            let capturedURL = url
            inFlight[url] = Task { await loadImage(for: capturedURL) }
        }
    }

    private func loadImage(for url: URL) async -> NSImage? {
        let interval = PerformanceSignposts.beginArtworkLoad()
        defer { PerformanceSignposts.endArtworkLoad(interval) }

        var request = URLRequest(url: url)
        SpotifyNetworkSession.apply(.background, to: &request)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              let image = NSImage(data: data) else {
            return nil
        }

        storeInMemory(image, for: url, cost: data.count)
        saveToDisk(data, for: url)
        return image
    }

    private func storeInMemory(_ image: NSImage, for url: URL, cost: Int = 0) {
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private func diskURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(name, isDirectory: false)
    }

    private func loadFromDisk(url: URL) -> NSImage? {
        let fileURL = diskURL(for: url)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }

    private func saveToDisk(_ data: Data, for url: URL) {
        try? data.write(to: diskURL(for: url), options: .atomic)
    }
}
