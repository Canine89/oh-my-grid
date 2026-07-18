import AppKit

/// 권한이 없을 때 짧게 보여주는 안내 HUD.
@MainActor
enum PermissionNotice {
    private static var hud: ResizeHUDWindow?
    private static var hideWork: DispatchWorkItem?

    /// 손쉬운 사용 권한이 없어 동작을 못 할 때 안내. 몇 초 뒤 자동으로 사라진다.
    static func showDenied() {
        show(text: "손쉬운 사용 권한이 필요합니다 — 메뉴에서 「권한 다시 요청」을 눌러 주세요")
    }

    static func show(text: String) {
        hideWork?.cancel()
        hud?.orderOut(nil)
        let win = ResizeHUDWindow(text: text)
        win.orderFrontRegardless()
        hud = win

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                hud?.orderOut(nil)
                hud = nil
                hideWork = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
}
