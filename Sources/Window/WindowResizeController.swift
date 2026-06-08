import AppKit
import ApplicationServices

/// "비율 선택 → 바꿀 창 클릭" 흐름으로 창을 고정 크기로 리사이즈한다.
/// 메뉴에서 프리셋을 고르면 무장(arm)되고, 다음 좌클릭 지점의 창을 그 크기로 맞춘다.
/// 입력 소비/게이팅은 `MouseEventTap`이 담당한다.
@MainActor
final class WindowResizeController {
    static let shared = WindowResizeController()
    private init() {}

    /// 고정 크기 프리셋. 필요하면 여기만 늘리면 메뉴에 자동 반영된다.
    struct Preset {
        let label: String
        let size: CGSize
    }
    static let presets: [Preset] = [
        Preset(label: "4:3 · 720 × 480",    size: CGSize(width: 720,  height: 480)),
        Preset(label: "16:9 · 1280 × 720",  size: CGSize(width: 1280, height: 720)),
        Preset(label: "16:9 · 1920 × 1080", size: CGSize(width: 1920, height: 1080)),
    ]

    private(set) var pendingSize: CGSize?
    var isArmed: Bool { pendingSize != nil }
    private var hud: ResizeHUDWindow?

    /// 메뉴에서 프리셋 선택 → 다음 창 클릭을 기다린다.
    func arm(size: CGSize, label: String) {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.openSystemSettings()
            return
        }
        pendingSize = size
        showHUD(text: "크기 바꿀 창을 클릭하세요 — \(label)   (Esc 취소)")
        glog("창 크기 고정 무장 \(Int(size.width))x\(Int(size.height))")
    }

    /// 무장 해제(성공/취소 공통).
    func cancel() {
        pendingSize = nil
        hideHUD()
    }

    /// 좌클릭 지점의 창을 고정 크기로 리사이즈. 호출 후엔 항상 무장 해제된다.
    func applyAt(point: CGPoint) {
        defer { cancel() }
        guard let size = pendingSize, AccessibilityPermission.isGranted else { return }
        guard let window = AXWindowController.shared.windowUnderCursor(cgPoint: point) else {
            glog("창 크기 고정: 클릭 위치에 창 없음")
            return
        }
        // 우리 앱 자신의 창(HUD 등)은 건드리지 않는다.
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success, pid == getpid() { return }

        // 현재 좌상단(origin) 유지 + 가시 영역 안으로 클램프.
        let origin = AXWindowController.shared.frame(of: window)?.origin ?? point
        var rect = CGRect(origin: origin, size: size)
        if let display = ScreenGeometry.displayContaining(cgPoint: point),
           let screen = ScreenGeometry.screen(for: display.id) {
            rect = clamp(rect, within: ScreenGeometry.cgVisibleBounds(for: screen))
        }
        AXWindowController.shared.setFrame(rect, for: window)
        glog("창 크기 고정 적용 \(Int(size.width))x\(Int(size.height)) → \(rs(rect))")
    }

    /// 크기는 유지하고 origin만 가시 영역 안으로 민다(창이 화면보다 크면 좌상단 정렬).
    private func clamp(_ r: CGRect, within b: CGRect) -> CGRect {
        var o = r.origin
        o.x = r.width  <= b.width  ? min(max(o.x, b.minX), b.maxX - r.width)  : b.minX
        o.y = r.height <= b.height ? min(max(o.y, b.minY), b.maxY - r.height) : b.minY
        return CGRect(origin: o, size: r.size)
    }

    private func showHUD(text: String) {
        hideHUD()
        let win = ResizeHUDWindow(text: text)
        win.orderFrontRegardless()
        hud = win
    }

    private func hideHUD() {
        hud?.orderOut(nil)
        hud = nil
    }
}
