import Sparkle
import UserNotifications

@MainActor
final class UpdateCoordinator: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var notificationCenter: UNUserNotificationCenter { .current() }

    @Published var canCheckForUpdates = false
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var automaticallyChecksForUpdates = false

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        super.init()

        // Subscribe to updater state changes
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)

        // Configure default settings
        UserDefaults.standard.set(86400, forKey: "SUScheduledCheckInterval")
        UserDefaults.standard.set(false, forKey: "SUAllowsAutomaticUpdates")
        UserDefaults.standard.set(false, forKey: "SUAutomaticallyUpdate")
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func start() {
        // Updater starts automatically in init
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            // Permission result handled if needed
        }
    }

    var updater: SPUUpdater {
        updaterController.updater
    }
}
