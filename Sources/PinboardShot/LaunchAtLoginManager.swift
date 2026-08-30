import Combine
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }
}

@MainActor
/// 以 ServiceManagement 的实时状态驱动开关，避免 UserDefaults 显示“已开启”但系统并未注册。
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    @Published private(set) var message: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        state = LaunchAtLoginState(status: service.status)
    }

    var isEnabled: Bool { state == .enabled }

    func refresh() {
        state = LaunchAtLoginState(status: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        // 每次操作前后都重新读取系统状态，兼容用户在系统设置中手动撤销或批准。
        message = nil
        refresh()

        do {
            if enabled {
                switch state {
                case .enabled:
                    return
                case .requiresApproval:
                    message = L10n.text("launch.requiresApproval")
                    SMAppService.openSystemSettingsLoginItems()
                    return
                case .disabled, .unavailable:
                    try service.register()
                }
            } else if state != .disabled {
                try service.unregister()
            }

            refresh()
            if state == .requiresApproval {
                message = L10n.text("launch.registeredNeedsApproval")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refresh()
            message = L10n.text("launch.updateFailed", error.localizedDescription)
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
