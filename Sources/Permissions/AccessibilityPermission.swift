import AppKit
import ApplicationServices

/// 손쉬운 사용(접근성) 권한은 entitlement가 아니라 사용자 동의로만 부여된다.
/// 다른 앱의 창을 이동/리사이즈(AX)하고 글로벌 마우스 이벤트 탭(CGEventTap)을 설치하려면 필수다.
enum AccessibilityPermission {
    private static let requestRecordedKey = "accessibilityPermissionRequestRecorded"

    /// 이미 허용되었는지 확인 (prompt 없음).
    static var isGranted: Bool {
        AXIsProcessTrusted()
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

    /// 시스템 설정의 "손쉬운 사용(접근성)" 패널을 연다.
    static func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
