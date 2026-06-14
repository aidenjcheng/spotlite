import AppKit
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.activeErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(error)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(error, forType: .string)
                        }
                        .font(.caption)
                        Button("Dismiss") { model.clearBanner() }
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
            }

            NavigationSplitView {
                SidebarView()
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)

            NowPlayingBar()
        }
        .spotliteScreenBackground()
        .sheet(isPresented: Binding(
            get: { model.showQueue },
            set: { model.showQueue = $0 }
        )) {
            QueueView()
                .environment(model)
                .frame(minWidth: 420, minHeight: 480)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var model = model
        NavigationStack(path: $model.detailPath) {
            switch model.selectedSection {
            case .home:
                HomeView()
            case .search:
                SearchView()
            case .liked:
                LikedSongsView()
            case .playlists:
                PlaylistsView()
            }
        }
        .navigationDestination(for: SpotifyPlaylist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
                .id(playlist.id)
        }
        .navigationDestination(for: SpotifyAlbum.self) { album in
            AlbumDetailView(album: album)
                .id(album.id)
        }
        .navigationDestination(for: SpotifyArtist.self) { artist in
            ArtistDetailView(artist: artist)
                .id(artist.id)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding(
            get: { model.selectedSection },
            set: { model.selectSection($0) }
        )) {
            Section("Browse") {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }

            if !model.playlists.isEmpty {
                Section("Your Playlists") {
                    ForEach(model.playlists.prefix(12)) { playlist in
                        Button {
                            model.openPlaylist(playlist)
                        } label: {
                            Text(playlist.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Spotlite")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gear")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await model.loadLibrary(forceRefresh: true); await model.loadHome() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}
