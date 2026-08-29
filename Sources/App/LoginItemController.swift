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
            return String(localized: "Launch at login is on.")
        case .notRegistered:
            return String(localized: "Launch at login is off.")
        case .requiresApproval:
            return String(localized: "⚠️ Approval is required in System Settings › Login Items.")
        case .notFound:
            return String(localized: "⚠️ Login item status is unavailable.")
        @unknown default:
            return String(localized: "⚠️ Login item status is unavailable.")
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
