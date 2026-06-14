import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.auth.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
            WebPlaybackHost()
                .frame(width: 320, height: 240)
                .offset(x: -10_000, y: -10_000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .spotliteScreenBackground()
    }
}

struct WebPlaybackHost: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        container.wantsLayer = true
        container.layer?.opacity = 0
        container.alphaValue = 0
        let webView = model.bridge.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
