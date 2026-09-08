import AppKit

@MainActor
enum AppWindowActivation {
    /**
     Immediately activates and brings the given window to the front.
     Use this for non-menu triggers (e.g. keyboard shortcuts, notifications, other windows).
    **/
    static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /**
     Brings the window to the front after the current menu tracking loop finishes.
     Use this when invoked from an NSMenu item to prevent AppKit's menu dismissal
     from reclaiming key focus back to the previous application.
     **/
    static func presentAfterMenuDismisses(_ window: NSWindow) {
        performAfterMenuDismisses {
            present(window)
        }
    }

    /// Schedules an action to execute after the menu tracking loop ends (or after a 120ms timeout fallback).
    static func performAfterMenuDismisses(_ action: @escaping @MainActor () -> Void) {
        final class CleanupToken {
            var observer: NSObjectProtocol?
            var didRun = false

            func cancel() {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
            }
        }

        let token = CleanupToken()
        let runOnce: @MainActor () -> Void = {
            guard !token.didRun else { return }
            token.didRun = true
            token.cancel()
            action()
        }

        token.observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                runOnce()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            runOnce()
        }
    }
}
