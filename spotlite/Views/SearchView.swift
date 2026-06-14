import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SpotliteTheme.textSecondary)
                TextField("Search tracks, albums, artists, playlists", text: Binding(
                    get: { model.searchQuery },
                    set: { model.searchQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { Task { await model.performSearch() } }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SpotliteTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Button("Search") {
                    Task { await model.performSearch() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SpotliteTheme.accent)
            }
            .padding(12)
            .background(SpotliteTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Picker("Category", selection: Binding(
                get: { model.searchCategory },
                set: { model.searchCategory = $0 }
            )) {
                ForEach(SearchCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            ScrollView {
                LazyVStack(spacing: 0) {
                    switch model.searchCategory {
                    case .tracks:
                        trackResults
                    case .albums:
                        albumResults
                    case .artists:
                        artistResults
                    case .playlists:
                        playlistResults
                    }
                }
                .background(SpotliteTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Search")
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var trackResults: some View {
        let tracks = model.searchResults.tracks?.items ?? []
        if tracks.isEmpty {
            searchEmptyState("No tracks found", icon: "music.note")
        } else {
            ForEach(tracks) { track in
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

    @ViewBuilder
    private var albumResults: some View {
        let albums = model.searchResults.albums?.items ?? []
        if albums.isEmpty {
            searchEmptyState("No albums found", icon: "square.stack")
        } else {
            ForEach(albums) { album in
                Button {
                    model.openAlbum(album)
                } label: {
                    MediaRowView(
                        title: album.name,
                        subtitle: album.artistNames,
                        imageURL: album.images?.first.flatMap { URL(string: $0.url) }
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(SpotliteTheme.divider)
            }
        }
    }

    @ViewBuilder
    private var artistResults: some View {
        let artists = model.searchResults.artists?.items ?? []
        if artists.isEmpty {
            searchEmptyState("No artists found", icon: "person.fill")
        } else {
            ForEach(artists) { artist in
                Button {
                    model.openArtist(artist)
                } label: {
                    MediaRowView(
                        title: artist.name,
                        subtitle: "Artist",
                        imageURL: artist.images?.first.flatMap { URL(string: $0.url) },
                        imageCornerRadius: 24
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(SpotliteTheme.divider)
            }
        }
    }

    @ViewBuilder
    private var playlistResults: some View {
        let playlists = model.searchResults.playlists?.items ?? []
        if playlists.isEmpty {
            searchEmptyState("No playlists found", icon: "music.note.list")
        } else {
            ForEach(playlists) { playlist in
                Button {
                    model.openPlaylistFromSearch(playlist)
                } label: {
                    MediaRowView(
                        title: playlist.name,
                        subtitle: playlistSubtitle(playlist),
                        imageURL: playlist.images?.first.flatMap { URL(string: $0.url) }
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(SpotliteTheme.divider)
            }
        }
    }

    private func playlistSubtitle(_ playlist: SpotifyPlaylist) -> String {
        if let description = playlist.description, !description.isEmpty {
            return description
        }
        if playlist.trackCount > 0 {
            return "\(playlist.trackCount) tracks"
        }
        return "Playlist"
    }

    @ViewBuilder
    private func searchEmptyState(_ message: String, icon: String) -> some View {
        ContentUnavailableView(
            message,
            systemImage: icon,
            description: Text("Try a different search term.")
        )
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
