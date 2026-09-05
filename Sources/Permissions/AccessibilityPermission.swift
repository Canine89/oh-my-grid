import AppKit
import ApplicationServices

/// 손쉬운 사용(접근성) 권한은 entitlement가 아니라 사용자 동의로만 부여된다.
/// 다른 앱의 창을 이동/리사이즈(AX)하고 글로벌 마우스 이벤트 탭(CGEventTap)을 설치하려면 필수다.
enum AccessibilityPermission {
    private static let requestRecordedKey = "accessibilityPermissionRequestRecorded"

    /// 이미 허용되었는지 확인 (prompt 없음).
    static var isGranted: Bool {
        return AXIsProcessTrusted()
    }

    /// 이전 실행에서 자동 prompt를 이미 요청했는지 (requestOnce가 다시 뜨지 않는 상태인지).
    static var hasRequestedBefore: Bool {
        UserDefaults.standard.bool(forKey: requestRecordedKey)
    }

    /// 시스템 권한 prompt를 띄운다. 사용자가 결정하기 전이면 false를 반환할 수 있다.
    @discardableResult
    static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 자동 권한 요청은 최초 실행에서만 한다.
    ///
    /// macOS가 아직 TCC 변경을 반영하지 못했거나 사용자가 요청을 거절한 상태에서
    /// 매 실행마다 prompt 옵션을 넘기면 같은 안내가 계속 나타날 수 있다. 이후에는
    /// 메뉴와 설정 창의 명시적인 버튼으로 다시 열 수 있으므로 요청 여부를 저장한다.
    @discardableResult
    static func requestOnce() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: requestRecordedKey) == false else {
            return isGranted
        }

        // 시스템 창이 열린 뒤 앱이 종료되더라도 다음 실행에서 중복 요청하지 않도록
        // API 호출 전에 기록한다.
        defaults.set(true, forKey: requestRecordedKey)
        return request()
    }

    /// 사용자가 메뉴/설정에서 복구할 때: 시스템 prompt를 다시 띄운 뒤 설정 패널을 연다.
    /// 앱이 손쉬운 사용 목록에 안 보이는 경우에도 prompt가 등록을 유도한다.
    @discardableResult
    static func requestAndOpenSettings() -> Bool {
        let granted = request()
        openSystemSettings()
        NotificationCenter.default.post(name: .accessibilityPermissionWatchRequested, object: nil)
        notifyStatusChanged()
        return granted
    }

    /// 시스템 설정의 "손쉬운 사용(접근성)" 패널을 연다.
    /// Tahoe의 System Settings URL을 먼저 시도하고, 실패 시 레거시 System Preferences URL로 폴백한다.
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in candidates {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    static func notifyStatusChanged() {
        NotificationCenter.default.post(name: .accessibilityPermissionChanged, object: nil)
    }
}

extension Notification.Name {
    /// 손쉬운 사용 권한 상태가 바뀌었거나 UI가 다시 확인해야 할 때.
    static let accessibilityPermissionChanged =
        Notification.Name("com.goldenrabbit.ohmygrid.accessibilityPermissionChanged")
    /// 사용자가 권한을 다시 요청함 → 허용 감지 watcher를 (재)시작해야 함.
    static let accessibilityPermissionWatchRequested =
        Notification.Name("com.goldenrabbit.ohmygrid.accessibilityPermissionWatchRequested")
}
