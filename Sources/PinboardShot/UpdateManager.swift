import AppKit
import Combine
import Sparkle

enum UpdateCheckFrequency: Int, CaseIterable, Identifiable {
    case hourly = 3_600
    case everySixHours = 21_600
    case everyTwelveHours = 43_200
    case daily = 86_400
    case everyThreeDays = 259_200
    case weekly = 604_800

    var id: Int { rawValue }
    var interval: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .hourly: L10n.text("preferences.updateFrequency.hourly")
        case .everySixHours: L10n.text("preferences.updateFrequency.everySixHours")
        case .everyTwelveHours: L10n.text("preferences.updateFrequency.everyTwelveHours")
        case .daily: L10n.text("preferences.updateFrequency.daily")
        case .everyThreeDays: L10n.text("preferences.updateFrequency.everyThreeDays")
        case .weekly: L10n.text("preferences.updateFrequency.weekly")
        }
    }

    static func closest(to interval: TimeInterval) -> UpdateCheckFrequency {
        allCases.min { abs($0.interval - interval) < abs($1.interval - interval) } ?? .daily
    }
}

/// 将更新网络访问收口到 Sparkle；截图、历史和偏好仍只在本机处理。
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    private static let dismissedUpdateNoticeVersionDefaultsKey = "dismissedUpdateNoticeVersion"

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var checkFrequency = UpdateCheckFrequency.daily
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var updateNotice: UpdateNotice?

    var onUpdateStateChanged: (() -> Void)?

    override init() {
        super.init()
        refreshSettings()
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    @objc func checkForUpdates(_ sender: Any?) {
        refreshLastUpdateCheckDate()
        updaterController.checkForUpdates(sender)
    }

    func dismissUpdateNotice() {
        guard let updateNotice else { return }
        UserDefaults.standard.set(
            updateNotice.version,
            forKey: Self.dismissedUpdateNoticeVersionDefaultsKey
        )
        self.updateNotice = nil
        onUpdateStateChanged?()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        refreshSettings()
    }

    func setCheckFrequency(_ frequency: UpdateCheckFrequency) {
        updaterController.updater.updateCheckInterval = frequency.interval
        refreshSettings()
    }

    func refreshSettings() {
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        checkFrequency = .closest(to: updaterController.updater.updateCheckInterval)
        refreshLastUpdateCheckDate()
    }

    private func showUpdateNotice(for item: SUAppcastItem) {
        refreshLastUpdateCheckDate()
        let version = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return }
        guard UserDefaults.standard.string(
            forKey: Self.dismissedUpdateNoticeVersionDefaultsKey
        ) != version else { return }

        let notice = UpdateNotice(version: version)
        guard updateNotice != notice else { return }
        updateNotice = notice
        onUpdateStateChanged?()
    }

    private func clearUpdateNotice() {
        refreshLastUpdateCheckDate()
        guard updateNotice != nil else { return }
        updateNotice = nil
        onUpdateStateChanged?()
    }

    private func refreshLastUpdateCheckDate() {
        lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate
    }
}

struct UpdateNotice: Equatable {
    let version: String
}

enum UpdateLastCheckDisplay {
    static func menuDetail(for date: Date?) -> String {
        guard let date else {
            return L10n.text("tray.update.lastChecked.never")
        }

        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return L10n.text("tray.update.lastChecked", formatter.string(from: date))
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        showUpdateNotice(for: item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        clearUpdateNotice()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        clearUpdateNotice()
    }
}
