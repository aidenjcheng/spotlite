import AppKit
import SwiftUI

struct TrackRowView: View {
    @Environment(AppModel.self) private var model

    let track: SpotifyTrack
    let onPlay: () -> Void
    let onQueue: () -> Void
    let onToggleSave: (Bool) async -> Bool

    private var saveStatus: TrackSaveStatus {
        model.saveStatus(for: track.id)
    }

    private let durationLabel: String

    init(
        track: SpotifyTrack,
        onPlay: @escaping () -> Void,
        onQueue: @escaping () -> Void,
        onToggleSave: @escaping (Bool) async -> Bool
    ) {
        self.track = track
        self.onPlay = onPlay
        self.onQueue = onQueue
        self.onToggleSave = onToggleSave
        durationLabel = formatDuration(ms: track.durationMs)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onPlay) {
                    ArtworkView(url: track.artworkURL, size: 44)
                }
                .buttonStyle(.plain)
                .help("Play")

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onPlay) {
                        Text(track.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SpotliteTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Play")

                    ArtistNamesView(
                        artists: track.artists,
                        fallback: track.artistNames,
                        onOpenArtist: { model.openArtist($0) }
                    )
                }
            }

            Spacer()

            Text(durationLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(SpotliteTheme.textSecondary)

            Button {
                Task {
                    let saved = saveStatus.isSaved
                    saveStatus.isSaved = await onToggleSave(saved)
                }
            } label: {
                Image(systemName: saveStatus.isSaved ? "heart.fill" : "heart")
                    .foregroundStyle(saveStatus.isSaved ? SpotliteTheme.accent : SpotliteTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(saveStatus.isSaved ? "Remove from Liked Songs" : "Save to Liked Songs")

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
    }
}

struct ArtistNamesView: View {
    let artists: [SpotifyArtist]
    var fallback: String = ""
    let onOpenArtist: (SpotifyArtist) -> Void

    var body: some View {
        if artists.isEmpty {
            Text(fallback.isEmpty ? "Unknown Artist" : fallback)
                .font(.caption)
                .foregroundStyle(SpotliteTheme.textSecondary)
                .lineLimit(1)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                    if index > 0 {
                        Text(", ")
                            .font(.caption)
                            .foregroundStyle(SpotliteTheme.textSecondary)
                    }
                    ArtistNameButton(artist: artist, onOpenArtist: onOpenArtist)
                }
            }
            .lineLimit(1)
        }
    }
}

private struct ArtistNameButton: View {
    let artist: SpotifyArtist
    let onOpenArtist: (SpotifyArtist) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpenArtist(artist)
        } label: {
            Text(artist.name)
                .font(.caption)
                .foregroundStyle(SpotliteTheme.textSecondary)
                .underline(isHovered, color: SpotliteTheme.textSecondary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .help("View \(artist.name)")
    }
}

struct MediaRowView: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    var imageCornerRadius: CGFloat = 8
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: imageURL, size: 48, cornerRadius: imageCornerRadius)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SpotliteTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SpotliteTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpotliteTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ArtworkCache.shared.image(for: url)
        }
    }

    private var placeholder: some View {
        ZStack {
            SpotliteTheme.elevated
            Image(systemName: "music.note")
                .foregroundStyle(SpotliteTheme.textSecondary)
        }
    }
}
