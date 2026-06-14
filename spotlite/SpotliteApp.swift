import SwiftUI

@main
struct SpotliteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    MediaControlsSetup.configure(model: model)
                    Task { await model.onAppear() }
                }
                .onOpenURL { url in
                    Task { await model.auth.handleCallbackURL(url) }
                }
                .onChange(of: model.auth.isAuthenticated) { _, authenticated in
                    if authenticated {
                        Task { await model.onAuthenticated() }
                    }
                }
                .onChange(of: model.bridge.stateRevision) { _, _ in
                    model.syncPlaybackFromBridge()
                }
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    Task { await model.playback.togglePlayPause() }
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Next") {
                    Task { await model.playback.next() }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") {
                    Task { await model.playback.previous() }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Like Track") {
                    Task { await model.playback.toggleSaveCurrentTrack() }
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            CommandMenu("Navigate") {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.offset) { index, section in
                    Button(section.rawValue) {
                        model.selectSection(section)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Button("Focus Search") {
                    model.selectSection(.search)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
