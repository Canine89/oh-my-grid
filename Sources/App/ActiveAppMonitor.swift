import AppKit

/// 현재 맨 앞(frontmost) 앱의 bundle ID를 NSWorkspace 알림으로 캐싱한다.
/// 이벤트 탭이 매 마우스 이벤트마다 워크스페이스를 조회하지 않도록(비용·노이즈 방지) 캐시만 읽게 한다.
@MainActor
final class ActiveAppMonitor {
    static let shared = ActiveAppMonitor()
    private init() {}

    private(set) var frontmostBundleID: String?
    private var observer: NSObjectProtocol?

    /// 앱 시작 시 1회 호출 — 초기값 캡처 + 앱 전환 알림 구독.
    func start() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.frontmostBundleID = app?.bundleIdentifier
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    /// 현재 맨 앞 앱이 사용자가 지정한 예외 목록에 들어 있으면 true.
    var isFrontmostExcluded: Bool {
        guard let id = frontmostBundleID else { return false }
        return Settings.shared.isExcluded(bundleID: id)
    }
}
