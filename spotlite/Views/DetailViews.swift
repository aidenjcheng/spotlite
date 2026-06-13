import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if playableTracks.isEmpty {
                    ContentUnavailableView(
                        "No tracks to show",
                        systemImage: "music.note.list",
                        description: Text(loadError ?? "Spotify only returns playlist tracks for playlists you own or collaborate on.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(playableTracks, id: \.index) { entry in
                            TrackRowView(
                                track: entry.track,
                                isSaved: model.savedTrackIDs.contains(entry.track.id)
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
                                model.updateSavedTrackID(entry.track.id, saved: newValue)
                                return newValue
                            }
                            Divider().overlay(SpotliteTheme.divider)
                        }
                    }
                    .background(SpotliteTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var header: some View {
        HStack(spacing: 16) {
            ArtworkView(url: playlist.images?.first.flatMap { URL(string: $0.url) }, size: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.name)
                    .font(.title.bold())
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                        .lineLimit(3)
                }
                Text("\(playableTracks.isEmpty ? playlist.trackCount : playableTracks.count) tracks")
                    .font(.caption)
                    .foregroundStyle(SpotliteTheme.textSecondary)
                Button("Play") {
                    Task { await model.playback.playContext(uri: playlist.uri) }
                }
                .buttonStyle(.borderedProminent)
                .tint(SpotliteTheme.accent)
                .disabled(playableTracks.isEmpty && playlist.trackCount == 0)
            }
            Spacer()
        }
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            tracks = try await api.fetchAllPlaylistTracks(id: playlist.id)
        } catch {
            loadError = error.localizedDescription
            model.bannerError = error.localizedDescription
        }
    }
}

struct AlbumDetailView: View {
    @Environment(AppModel.self) private var model
    let album: SpotifyAlbum

    @State private var tracks: [SpotifyTrack] = []
    @State private var isLoading = true

    private var api: SpotifyAPIClient { SpotifyAPIClient(auth: model.auth) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ArtworkView(url: album.images?.first.flatMap { URL(string: $0.url) }, size: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.name)
                            .font(.title.bold())
                        Text(album.artistNames)
                            .foregroundStyle(SpotliteTheme.textSecondary)
                        if let uri = album.uri {
                            Button("Play album") {
                                Task { await model.playback.playContext(uri: uri) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SpotliteTheme.accent)
                        }
                    }
                    Spacer()
                }

                if isLoading {
                    ProgressView()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(
                                track: track,
                                isSaved: model.savedTrackIDs.contains(track.id)
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
                                model.updateSavedTrackID(track.id, saved: newValue)
                                return newValue
                            }
                            Divider().overlay(SpotliteTheme.divider)
                        }
                    }
                    .background(SpotliteTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .navigationTitle(album.name)
        .task(id: album.id) {
            tracks = []
            isLoading = true
            await loadTracks()
        }
    }

    private func loadTracks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.fetchAlbumTracks(id: album.id, limit: 50)
            tracks = page.items
        } catch {
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
                HStack(spacing: 16) {
                    ArtworkView(
                        url: artist.images?.first.flatMap { URL(string: $0.url) },
                        size: 120,
                        cornerRadius: 60
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name)
                            .font(.title.bold())
                        Text("Artist")
                            .foregroundStyle(SpotliteTheme.textSecondary)
                    }
                    Spacer()
                }

                if isLoading {
                    ProgressView()
                } else {
                    section(title: "Popular") {
                        ForEach(topTracks) { track in
                            TrackRowView(
                                track: track,
                                isSaved: model.savedTrackIDs.contains(track.id)
                            ) {
                                Task { await model.playback.playTrack(track) }
                            } onQueue: {
                                Task { await model.playback.addToQueue(track) }
                            } onToggleSave: { saved in
                                let newValue = await model.playback.toggleSave(track: track, isSaved: saved)
                                model.updateSavedTrackID(track.id, saved: newValue)
                                return newValue
                            }
                            Divider().overlay(SpotliteTheme.divider)
                        }
                    }

                    section(title: "Albums") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                            ForEach(albums) { album in
                                NavigationLink(value: album) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ArtworkView(url: album.images?.first.flatMap { URL(string: $0.url) }, size: 140)
                                        Text(album.name)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
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
            async let discography = api.fetchArtistAlbums(id: artist.id)
            topTracks = try await tracks
            albums = try await discography
        } catch {
            model.bannerError = error.localizedDescription
        }
    }
}
