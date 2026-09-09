import Sparkle
import UserNotifications
import Combine

@MainActor
final class UpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
    nonisolated private static let updateNotificationIdentifier = "PocketStackUpdateAvailable"

    private var updaterController: SPUStandardUpdaterController!
    private var notificationCenter: UNUserNotificationCenter { .current() }
    private var hasStarted = false

    @Published var canCheckForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var automaticallyChecksForUpdates = false

    override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        notificationCenter.delegate = self

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func checkForUpdates() {
        guard hasStarted else { return }
        updaterController.checkForUpdates(nil)
    }

    func start() {
        guard !hasStarted, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        hasStarted = true
        updaterController.startUpdater()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
        latestVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailable = false
        latestVersion = ""
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        updateAvailable = true
        latestVersion = update.displayVersionString

        guard !state.userInitiated else { return }

        let content = UNMutableNotificationContent()
        content.title = "A Pocket Stack update is available"
        content.body = "Version \(update.displayVersionString) is ready to install."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.updateNotificationIdentifier,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == Self.updateNotificationIdentifier,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        Task { @MainActor [weak self] in
            self?.checkForUpdates()
            completionHandler()
        }
    }
}
