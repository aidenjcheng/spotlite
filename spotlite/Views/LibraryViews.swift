import SwiftUI

struct LikedSongsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Liked Songs")
                            .font(.title.bold())
                        Text("\(model.savedTracks.count) tracks")
                            .foregroundStyle(SpotliteTheme.textSecondary)
                    }
                    Spacer()
                    Button("Play all") {
                        let uris = model.savedTracks.compactMap { $0.resolvedTrack?.uri }
                        Task { await model.playback.playTracks(uris) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SpotliteTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                LazyVStack(spacing: 0) {
                    ForEach(model.savedTracks) { item in
                        if let track = item.resolvedTrack {
                            TrackRowView(
                                track: track
                            ) {
                                Task { await model.playback.playTrack(track) }
                            } onQueue: {
                                Task { await model.playback.addToQueue(track) }
                            } onToggleSave: { saved in
                                let newValue = await model.playback.toggleSave(track: track, isSaved: saved)
                                model.setTrackSaved(track.id, saved: newValue)
                                if !newValue { await model.loadLibrary() }
                                return newValue
                            }
                            Divider().overlay(SpotliteTheme.divider)
                        }
                    }
                }
                .background(SpotliteTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Liked Songs")
        .overlay {
            if model.isLoadingLibrary && model.savedTracks.isEmpty {
                ProgressView()
            } else if model.savedTracks.isEmpty && !model.isLoadingLibrary {
                ContentUnavailableView(
                    "No liked songs loaded",
                    systemImage: "heart",
                    description: Text(model.activeErrorMessage ?? "Pull to refresh or use the ↻ button in the sidebar.")
                )
            }
        }
        .refreshable { await model.loadLibrary(forceRefresh: true) }
    }
}

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model

    let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        ScrollView {
            if model.playlists.isEmpty && !model.isLoadingLibrary {
                ContentUnavailableView(
                    "No playlists loaded",
                    systemImage: "music.note.list",
                    description: Text(model.activeErrorMessage ?? "Pull to refresh or use the ↻ button in the sidebar.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding(24)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.playlists) { playlist in
                        Button {
                            model.openPlaylist(playlist)
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Playlists")
        .overlay {
            if model.isLoadingLibrary && model.playlists.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await model.loadLibrary(forceRefresh: true) }
    }
}

struct PlaylistCard: View {
    let playlist: SpotifyPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: playlist.images?.first.flatMap { URL(string: $0.url) }, size: 160)
            Text(playlist.name)
                .font(.headline)
                .foregroundStyle(SpotliteTheme.textPrimary)
                .lineLimit(2)
            Text("\(playlist.trackCount) tracks")
                .font(.caption)
                .foregroundStyle(SpotliteTheme.textSecondary)
        }
    }
}
