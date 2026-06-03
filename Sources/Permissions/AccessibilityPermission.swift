import AppKit
import ApplicationServices

/// 손쉬운 사용(접근성) 권한은 entitlement가 아니라 사용자 동의로만 부여된다.
/// 다른 앱의 창을 이동/리사이즈(AX)하고 글로벌 마우스 이벤트 탭(CGEventTap)을 설치하려면 필수다.
enum AccessibilityPermission {
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

    /// 시스템 설정의 "손쉬운 사용(접근성)" 패널을 연다.
    static func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
enum PermissionAlert {
    static func show() {
        let alert = NSAlert()
        alert.messageText = "손쉬운 사용(접근성) 권한이 필요합니다"
        alert.informativeText = """
        \(Brand.name)가 다른 앱의 창을 그리드에 맞춰 옮기려면 시스템 설정에서 권한을 허용해야 합니다.
        '개인정보 보호 및 보안 → 손쉬운 사용' 목록에서 \(Brand.name)을 켠 뒤 앱을 다시 실행해 주세요.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSystemSettings()
        }
    }
}
