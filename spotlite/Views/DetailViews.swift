import SwiftUI

struct DetailHeaderView: View {
    let title: String
    var subtitle: String?
    var detail: String?
    let imageURL: URL?
    var imageCornerRadius: CGFloat = 8
    var imageSize: CGFloat = 120
    var primaryActionTitle: String?
    var primaryAction: (() -> Void)?
    var primaryDisabled = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(url: imageURL, size: imageSize, cornerRadius: imageCornerRadius)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title.bold())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                        .lineLimit(3)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                }
                if let primaryActionTitle, let primaryAction {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(SpotliteTheme.accent)
                        .disabled(primaryDisabled)
                }
            }
            Spacer()
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlist: SpotifyPlaylist

    @State private var tracks: [PlaylistTrackItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: model.auth) }

    private var playableTracks: [(index: Int, track: SpotifyTrack)] {
        tracks.enumerated().compactMap { index, item in
            guard let track = item.resolvedTrack else { return nil }
            return (index, track)
        }
    }

    private var trackCountLabel: String {
        let count = playableTracks.isEmpty ? playlist.trackCount : playableTracks.count
        return count == 1 ? "1 track" : "\(count) tracks"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeaderView(
                    title: playlist.name,
                    subtitle: playlist.description,
                    detail: trackCountLabel,
                    imageURL: playlist.images?.first.flatMap { URL(string: $0.url) },
                    primaryActionTitle: "Play",
                    primaryAction: {
                        Task { await model.playback.playContext(uri: playlist.uri) }
                    },
                    primaryDisabled: playableTracks.isEmpty && playlist.trackCount == 0
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if playableTracks.isEmpty {
                    ContentUnavailableView(
                        "No tracks to show",
                        systemImage: "music.note.list",
                        description: Text(loadError ?? "Spotify only returns playlist tracks for playlists you own or collaborate on. You can still press Play to start the playlist.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    trackList
                }
            }
            .padding(24)
        }
        .navigationTitle(playlist.name)
        .task(id: playlist.id) {
            tracks = []
            loadError = nil
            isLoading = true
            await loadTracks()
        }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(playableTracks, id: \.index) { entry in
                TrackRowView(
                    track: entry.track
                ) {
                    Task {
                        await model.playback.playContext(
                            uri: playlist.uri,
                            offset: entry.index,
                            nowPlaying: entry.track
                        )
                    }
                } onQueue: {
                    Task { await model.playback.addToQueue(entry.track) }
                } onToggleSave: { saved in
                    let newValue = await model.playback.toggleSave(track: entry.track, isSaved: saved)
                    model.setTrackSaved(entry.track.id, saved: newValue)
                    return newValue
                }
                Divider().overlay(SpotliteTheme.divider)
            }
        }
        .background(SpotliteTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        if let cached = LibraryCache.loadPlaylistTracksAllowingStale(id: playlist.id), !cached.isEmpty {
            tracks = cached
            isLoading = false
            Task { await fetchTracksFromNetwork() }
            return
        }

        await fetchTracksFromNetwork()
    }

    private func fetchTracksFromNetwork() async {
        do {
            let fetched = try await api.fetchAllPlaylistTracks(id: playlist.id)
            tracks = fetched
            LibraryCache.savePlaylistTracks(id: playlist.id, tracks: fetched)
            loadError = nil
        } catch {
            if tracks.isEmpty {
                loadError = error.localizedDescription
                model.bannerError = error.localizedDescription
            }
        }
    }
}

struct AlbumDetailView: View {
    @Environment(AppModel.self) private var model
    let album: SpotifyAlbum

    @State private var tracks: [SpotifyTrack] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: model.auth) }

    private var albumDetail: String? {
        var parts: [String] = []
        if let releaseDate = album.releaseDate, !releaseDate.isEmpty {
            parts.append(releaseDate)
        }
        if !tracks.isEmpty {
            parts.append(tracks.count == 1 ? "1 track" : "\(tracks.count) tracks")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeaderView(
                    title: album.name,
                    subtitle: album.artistNames,
                    detail: albumDetail,
                    imageURL: album.images?.first.flatMap { URL(string: $0.url) },
                    primaryActionTitle: album.uri == nil ? nil : "Play album",
                    primaryAction: album.uri.map { uri in
                        { Task { await model.playback.playContext(uri: uri) } }
                    },
                    primaryDisabled: tracks.isEmpty && !isLoading
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if tracks.isEmpty {
                    ContentUnavailableView(
                        "No tracks found",
                        systemImage: "music.note",
                        description: Text(loadError ?? "This album has no playable tracks.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    trackList
                }
            }
            .padding(24)
        }
        .navigationTitle(album.name)
        .task(id: album.id) {
            tracks = []
            loadError = nil
            isLoading = true
            await loadTracks()
        }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRowView(
                    track: track
                ) {
                    if let uri = album.uri {
                        Task {
                            await model.playback.playContext(uri: uri, offset: index, nowPlaying: track)
                        }
                    } else {
                        Task { await model.playback.playTrack(track) }
                    }
                } onQueue: {
                    Task { await model.playback.addToQueue(track) }
                } onToggleSave: { saved in
                    let newValue = await model.playback.toggleSave(track: track, isSaved: saved)
                    model.setTrackSaved(track.id, saved: newValue)
                    return newValue
                }
                Divider().overlay(SpotliteTheme.divider)
            }
        }
        .background(SpotliteTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await api.fetchAlbumTracks(id: album.id, limit: 50)
            tracks = page.items
        } catch {
            loadError = error.localizedDescription
            model.bannerError = error.localizedDescription
        }
    }
}

struct ArtistDetailView: View {
    @Environment(AppModel.self) private var model
    let artist: SpotifyArtist

    @State private var topTracks: [SpotifyTrack] = []
    @State private var albums: [SpotifyAlbum] = []
    @State private var isLoading = true

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: model.auth) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHeaderView(
                    title: artist.name,
                    subtitle: "Artist",
                    imageURL: artist.images?.first.flatMap { URL(string: $0.url) },
                    imageCornerRadius: 60
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if topTracks.isEmpty && albums.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show yet",
                        systemImage: "person.fill",
                        description: Text("Popular tracks and albums couldn't be loaded for this artist.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if !topTracks.isEmpty {
                        section(title: "Popular") {
                            ForEach(topTracks) { track in
                                TrackRowView(
                                    track: track
                                ) {
                                    Task { await model.playback.playTrack(track) }
                                } onQueue: {
                                    Task { await model.playback.addToQueue(track) }
                                } onToggleSave: { saved in
                                    let newValue = await model.playback.toggleSave(track: track, isSaved: saved)
                                    model.setTrackSaved(track.id, saved: newValue)
                                    return newValue
                                }
                                Divider().overlay(SpotliteTheme.divider)
                            }
                        }
                    }

                    if !albums.isEmpty {
                        section(title: "Albums") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                                ForEach(albums) { album in
                                    Button {
                                        model.openAlbum(album)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ArtworkView(
                                                url: album.images?.first.flatMap { URL(string: $0.url) },
                                                size: 140
                                            )
                                            Text(album.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(SpotliteTheme.textPrimary)
                                                .lineLimit(2)
                                            if let releaseDate = album.releaseDate, !releaseDate.isEmpty {
                                                Text(releaseDate)
                                                    .font(.caption)
                                                    .foregroundStyle(SpotliteTheme.textSecondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(artist.name)
        .task(id: artist.id) {
            topTracks = []
            albums = []
            isLoading = true
            await load()
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            content()
                .background(SpotliteTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let tracks = api.fetchArtistTopTracks(id: artist.id)
            async let discography = api.fetchAllArtistAlbums(id: artist.id)
            topTracks = try await tracks
            albums = try await discography
        } catch {
            model.bannerError = error.localizedDescription
        }
    }
}
