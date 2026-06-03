import AppKit
import ApplicationServices

/// 그리드 스냅 세션의 수명주기를 관리한다:
/// 무장(arm) → 셀 추적(update) → 커밋(commit, 창 스냅) → 정리.
/// 입력 게이팅/소비는 `MouseEventTap`이 담당하고, 여기서는 상태와 시각/창 조작만 다룬다.
@MainActor
final class GridSessionController {
    static let shared = GridSessionController()
    private init() {}

    private(set) var isArmed = false
    /// 우클릭-업으로 선택이 잠긴 뒤(좌버튼 해제 대기 중)면 true.
    var hasPending: Bool { pendingWindow != nil }

    private var targetWindow: AXUIElement?
    private var displayBounds: CGRect = .zero
    private var anchor = ScreenGeometry.Cell(col: 0, row: 0)
    private var current = ScreenGeometry.Cell(col: 0, row: 0)
    private var overlay: GridOverlayWindow?

    // 좌버튼을 뗄 때 한 번에 스냅할 목표. 그 전까지는 창을 건드리지 않아(드래그를 그대로 둬서)
    // 번쩍임 없이 마지막에 딱 한 번만 이동한다.
    private var pendingWindow: AXUIElement?
    private var pendingFrame: CGRect?

    private var watchdog: Timer?
    private let watchdogTimeout: TimeInterval = 15

    /// 좌드래그 도중 우클릭 시점에 호출. 성공 시 true(이벤트 탭이 우클릭을 소비).
    /// 창은 **이동시키지 않고** 그리드만 띄운다(드래그는 OS가 계속 처리 → 창은 커서를 따라감).
    @discardableResult
    func arm(at point: CGPoint) -> Bool {
        guard !isArmed else { return false }
        guard Settings.shared.enabled else { glog("arm 실패: 그리드 비활성"); return false }
        guard AccessibilityPermission.isGranted else { glog("arm 실패: 접근성 권한 없음"); return false }
        guard let window = AXWindowController.shared.windowUnderCursor(cgPoint: point) else {
            glog("arm 실패: 커서 아래 창을 못 찾음 @\(Int(point.x)),\(Int(point.y))")
            return false
        }
        guard let display = ScreenGeometry.displayContaining(cgPoint: point),
              let screen = ScreenGeometry.screen(for: display.id) else {
            glog("arm 실패: 디스플레이 못 찾음 @\(Int(point.x)),\(Int(point.y))")
            return false
        }
        glog("arm 성공 display=\(display.id) bounds=\(rs(display.bounds))")

        targetWindow = window
        displayBounds = display.bounds
        pendingWindow = nil
        pendingFrame = nil

        let cols = Settings.shared.columns
        let rows = Settings.shared.rows
        anchor = ScreenGeometry.cell(at: point, bounds: displayBounds, cols: cols, rows: rows)
        current = anchor

        let win = GridOverlayWindow(screen: screen)
        win.gridView.cgOrigin = displayBounds.origin
        win.gridView.displayBounds = displayBounds
        win.gridView.columns = cols
        win.gridView.rows = rows
        win.gridView.selection = currentSelectionRect()
        win.orderFrontRegardless()
        overlay = win

        isArmed = true
        startWatchdog()
        return true
    }

    /// 무장 중 마우스 이동 시 호출 — 선택 셀 블록 갱신. (창은 건드리지 않음)
    func update(to point: CGPoint) {
        guard isArmed else { return }
        current = ScreenGeometry.cell(at: point,
                                      bounds: displayBounds,
                                      cols: Settings.shared.columns,
                                      rows: Settings.shared.rows)
        overlay?.gridView.selection = currentSelectionRect()
        startWatchdog()   // 입력이 있으면 워치독 리셋
    }

    /// 우클릭-업 시 호출 — 그리드를 닫고 목표를 확정만 한다. 실제 창 이동은 좌버튼 해제 때.
    func lockSelection() {
        guard isArmed else { return }
        if let window = targetWindow {
            pendingWindow = window
            pendingFrame = applyGaps(currentSelectionRect())
            glog("lockSelection 목표=\(rs(pendingFrame!))")
        }
        teardownOverlay()
        isArmed = false
    }

    /// 좌버튼 해제 시 호출 — 확정된 목표로 창을 **한 번** 스냅한다.
    /// 이 시점엔 창이 이미 커서 위치(드래그 끝)에 있어 OS의 마우스업 재배치가 사실상 무효라,
    /// 우리의 스냅만 보인다 → 번쩍임 없음. (지연 1회는 OS 처리 직후를 확실히 덮기 위함)
    func commitPending() {
        if isArmed { lockSelection() }
        guard let window = pendingWindow, let frame = pendingFrame else { return }
        pendingWindow = nil
        pendingFrame = nil
        targetWindow = nil
        // 즉시 적용하지 않는다(그러면 OS 드래그 종료가 창을 커서로 되돌려 번쩍임). 창이 커서에
        // 있는 동안 OS가 드래그를 끝내게 두고(제자리=무해), 그 직후에 한 번만 그리드로 스냅한다.
        for delay in [0.05, 0.18] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AXWindowController.shared.setFrame(frame, for: window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            let after = AXWindowController.shared.frame(of: window)
            glog("commitPending 목표=\(rs(frame)) 최종=\(after.map(rs) ?? "nil")")
        }
    }

    /// 취소 — 창 변경 없이 오버레이만 정리.
    func cancel() {
        teardownOverlay()
        targetWindow = nil
        pendingWindow = nil
        pendingFrame = nil
        isArmed = false
    }

    // MARK: - 내부

    private func currentSelectionRect() -> CGRect {
        ScreenGeometry.unionRect(anchor: anchor, current: current,
                                 bounds: displayBounds,
                                 cols: Settings.shared.columns,
                                 rows: Settings.shared.rows)
    }

    /// 바깥 여백/안쪽 간격 적용.
    private func applyGaps(_ rect: CGRect) -> CGRect {
        var r = rect.insetBy(dx: Settings.shared.innerGap, dy: Settings.shared.innerGap)
        let m = Settings.shared.outerMargin
        if m > 0 {
            if abs(rect.minX - displayBounds.minX) < 1 { r.origin.x += m; r.size.width -= m }
            if abs(rect.maxX - displayBounds.maxX) < 1 { r.size.width -= m }
            if abs(rect.minY - displayBounds.minY) < 1 { r.origin.y += m; r.size.height -= m }
            if abs(rect.maxY - displayBounds.maxY) < 1 { r.size.height -= m }
        }
        return r.integral
    }

    private func teardownOverlay() {
        watchdog?.invalidate()
        watchdog = nil
        overlay?.orderOut(nil)
        overlay = nil
        displayBounds = .zero
        targetWindow = nil
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: watchdogTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("Grid session watchdog fired — auto-cancelling to avoid lockout")
                self?.cancel()
            }
        }
    }
}
