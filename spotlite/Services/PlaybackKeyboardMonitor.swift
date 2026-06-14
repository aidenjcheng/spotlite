import AppKit

@MainActor
enum PlaybackKeyboardMonitor {
    private static var monitor: Any?

    static func install(model: AppModel) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return event
            }
            guard let window = event.window, window.isKeyWindow else { return event }
            guard !isTextInputFocused(in: window) else { return event }

            Task { @MainActor in
                guard model.auth.isAuthenticated else { return }
                await model.playback.togglePlayPause()
            }
            return nil
        }
    }

    private static func isTextInputFocused(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField { return true }
        let className = NSStringFromClass(type(of: responder))
        return className.contains("FieldEditor") || className.contains("SearchField")
    }
}
