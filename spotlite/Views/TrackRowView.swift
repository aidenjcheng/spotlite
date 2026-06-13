import SwiftUI

struct TrackRowView: View {
    let track: SpotifyTrack
    let isSaved: Bool
    let onPlay: () -> Void
    let onQueue: () -> Void
    let onToggleSave: (Bool) async -> Bool

    @State private var saved: Bool

    init(
        track: SpotifyTrack,
        isSaved: Bool,
        onPlay: @escaping () -> Void,
        onQueue: @escaping () -> Void,
        onToggleSave: @escaping (Bool) async -> Bool
    ) {
        self.track = track
        self.isSaved = isSaved
        self.onPlay = onPlay
        self.onQueue = onQueue
        self.onToggleSave = onToggleSave
        _saved = State(initialValue: isSaved)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkView(url: track.artworkURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SpotliteTheme.textPrimary)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundStyle(SpotliteTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            Spacer()

            Text(formatDuration(ms: track.durationMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(SpotliteTheme.textSecondary)

            Button {
                Task { saved = await onToggleSave(saved) }
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .foregroundStyle(saved ? SpotliteTheme.accent : SpotliteTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(saved ? "Remove from Liked Songs" : "Save to Liked Songs")

            Button(action: onQueue) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Add to queue")

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Play")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { saved = isSaved }
        .onChange(of: isSaved) { _, newValue in saved = newValue }
    }
}

struct MediaRowView: View {
    let title: String
    let subtitle: String
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: imageURL, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SpotliteTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SpotliteTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            SpotliteTheme.elevated
            Image(systemName: "music.note")
                .foregroundStyle(SpotliteTheme.textSecondary)
        }
    }
}
