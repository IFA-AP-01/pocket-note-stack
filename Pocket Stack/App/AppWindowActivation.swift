import AppKit

@MainActor
enum AppWindowActivation {
    /**
     Activates the application using modern macOS APIs.
     **/
    static func activateApplication() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()
    }

    /**
     Immediately activates and brings the given window to the front.
     Use this for non-menu triggers (e.g. keyboard shortcuts, notifications, other windows).
    **/
    static func present(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        activateApplication()
    }

    /**
     Brings the window to the front and re-asserts focus through AppKit's menu dismissal cycle.
     Use this when invoked from an NSMenu item to prevent AppKit's menu dismissal
     from reclaiming key focus back to the previously active application.
     **/
    static func presentAfterMenuDismisses(_ window: NSWindow) {
        // Immediate presentation for instantaneous user feedback
        present(window)

        // Re-assert when the menu tracking loop finishes
        performAfterMenuDismisses {
            present(window)
        }

        // Secondary re-assertion to guarantee victory over AppKit's delayed
        // reactivation of the previous application during menu teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(140)) {
            guard window.isVisible else { return }
            present(window)
        }
    }

    /// Schedules an action to execute after the menu tracking loop ends (or after an 80ms timeout fallback).
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

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            runOnce()
        }
    }
}
