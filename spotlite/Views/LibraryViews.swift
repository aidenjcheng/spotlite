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
                        let uris = model.savedTracks.map(\.track.uri)
                        Task { await model.playback.playTracks(uris) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SpotliteTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                LazyVStack(spacing: 0) {
                    ForEach(model.savedTracks) { item in
                        TrackRowView(
                            track: item.track,
                            isSaved: true
                        ) {
                            Task { await model.playback.playTrack(item.track) }
                        } onQueue: {
                            Task { await model.playback.addToQueue(item.track) }
                        } onToggleSave: { _ in
                            let newValue = await model.playback.toggleSave(track: item.track, isSaved: true)
                            if !newValue { model.updateSavedTrackID(item.track.id, saved: false) }
                            await model.loadLibrary()
                            return newValue
                        }
                        Divider().overlay(SpotliteTheme.divider)
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
            }
        }
        .refreshable { await model.loadLibrary() }
    }
}

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model

    let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .navigationTitle("Playlists")
        .refreshable { await model.loadLibrary() }
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
