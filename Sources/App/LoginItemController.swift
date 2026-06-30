import Foundation
import ServiceManagement

enum LoginItemController {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var statusMessage: String {
        switch status {
        case .enabled:
            return "✅ 로그인 시 자동 실행이 켜져 있습니다."
        case .notRegistered:
            return "로그인 시 자동 실행이 꺼져 있습니다."
        case .requiresApproval:
            return "⚠️ macOS 설정에서 로그인 항목 승인이 필요합니다."
        case .notFound:
            return "⚠️ 로그인 항목 상태를 확인할 수 없습니다."
        @unknown default:
            return "⚠️ 로그인 항목 상태를 확인할 수 없습니다."
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
