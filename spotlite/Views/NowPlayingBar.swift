import SwiftUI

struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0

    var body: some View {
        VStack(spacing: 8) {
            if model.playback.durationMs > 0 {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : Double(model.playback.positionMs) },
                        set: { scrubPosition = $0; isScrubbing = true }
                    ),
                    in: 0 ... Double(max(model.playback.durationMs, 1)),
                    onEditingChanged: { editing in
                        if !editing {
                            isScrubbing = false
                            Task { await model.playback.seek(to: Int(scrubPosition)) }
                        }
                    }
                )
                .tint(SpotliteTheme.accent)
            }

            HStack(spacing: 16) {
                ArtworkView(url: model.playback.currentTrack?.artworkURL, size: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.playback.currentTrack?.name ?? "Not playing")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.playback.currentTrack?.artistNames ?? "Select a track to start")
                        .font(.caption)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 180, alignment: .leading)

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        Task { await model.playback.toggleSaveCurrentTrack() }
                    } label: {
                        Image(systemName: model.playback.isCurrentTrackSaved ? "heart.fill" : "heart")
                            .foregroundStyle(model.playback.isCurrentTrackSaved ? SpotliteTheme.accent : SpotliteTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Button { Task { await model.playback.previous() } } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.plain)

                    Button { Task { await model.playback.togglePlayPause() } } label: {
                        Image(systemName: model.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)

                    Button { Task { await model.playback.next() } } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            try? await model.playback.refreshQueue()
                            model.showQueue = true
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                    Slider(
                        value: Binding(
                            get: { model.playback.volume },
                            set: { value in Task { await model.playback.setVolume(value) } }
                        ),
                        in: 0 ... 1
                    )
                    .frame(width: 100)
                    .tint(SpotliteTheme.accent)
                }

                Text("\(formatDuration(ms: model.playback.positionMs)) / \(formatDuration(ms: model.playback.durationMs))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SpotliteTheme.textSecondary)
                    .frame(width: 88, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SpotliteTheme.elevated)
        .onAppear {
            Task { await model.playback.refreshPlaybackStateFromAPI() }
        }
    }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh") {
                    Task { try? await model.playback.refreshQueue() }
                }
                Button("Done") { dismiss() }
            }
            .padding(16)

            if model.playback.queue.isEmpty {
                ContentUnavailableView("Queue is empty", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.playback.queue) { track in
                    HStack {
                        ArtworkView(url: track.artworkURL, size: 40)
                        VStack(alignment: .leading) {
                            Text(track.name).lineLimit(1)
                            Text(track.artistNames)
                                .font(.caption)
                                .foregroundStyle(SpotliteTheme.textSecondary)
                        }
                        Spacer()
                        Button("Play") {
                            Task { await model.playback.playTrack(track) }
                        }
                    }
                }
            }
        }
        .spotliteScreenBackground()
        .task { try? await model.playback.refreshQueue() }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var clientID = ""

    var body: some View {
        Form {
            Section("Spotify Developer") {
                TextField("Client ID", text: $clientID)
                Button("Save Client ID") {
                    model.auth.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                Text("Redirect URI: \(SpotifyConfig.redirectURI)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                if let name = model.auth.profile?.displayName {
                    LabeledContent("Signed in as", value: name)
                }
                Button("Sign out", role: .destructive) {
                    model.playback.stopTimers()
                    model.auth.logout()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                Text("Spotlite uses the Spotify Web API and Web Playback SDK. Spotify Premium is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { clientID = model.auth.clientID }
    }
}
