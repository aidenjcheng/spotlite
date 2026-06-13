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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Search")
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var trackResults: some View {
        ForEach(model.searchResults.tracks?.items ?? []) { track in
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

    @ViewBuilder
    private var albumResults: some View {
        ForEach(model.searchResults.albums?.items ?? []) { album in
            NavigationLink(value: album) {
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

    @ViewBuilder
    private var artistResults: some View {
        ForEach(model.searchResults.artists?.items ?? []) { artist in
            NavigationLink(value: artist) {
                MediaRowView(
                    title: artist.name,
                    subtitle: "Artist",
                    imageURL: artist.images?.first.flatMap { URL(string: $0.url) }
                )
            }
            .buttonStyle(.plain)
            Divider().overlay(SpotliteTheme.divider)
        }
    }

    @ViewBuilder
    private var playlistResults: some View {
        ForEach(model.searchResults.playlists?.items ?? []) { playlist in
            NavigationLink(value: playlist) {
                MediaRowView(
                    title: playlist.name,
                    subtitle: playlist.description ?? "Playlist",
                    imageURL: playlist.images?.first.flatMap { URL(string: $0.url) }
                )
            }
            .buttonStyle(.plain)
            Divider().overlay(SpotliteTheme.divider)
        }
    }
}
