import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.recentlyPlayed.isEmpty {
                    ContentUnavailableView(
                        "Nothing recent yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Play something in Spotlite and it will show up here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.recentlyPlayed) { item in
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
                                    return newValue
                                }
                                Divider().overlay(SpotliteTheme.divider)
                            }
                        }
                    }
                    .background(SpotliteTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task { await model.loadHome() }
        .refreshable { await model.loadHome() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recently played")
                .font(.title2.bold())
                .foregroundStyle(SpotliteTheme.textPrimary)
            Text("Pick up where you left off.")
                .foregroundStyle(SpotliteTheme.textSecondary)
        }
    }
}
