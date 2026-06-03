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

    // MARK: 가장자리 절반 스냅 (일반 드래그) 상태
    /// 드래그 중인 후보 창(leftMouseDown 시점에 캡처).
    private var dragCandidate: AXUIElement?
    /// 후보 창의 초기 origin(CG 전역). 가장자리 진입 시 이동 여부 판별에 사용.
    private var dragInitialOrigin: CGPoint?
    /// 후보 창이 실제로 이동해 "창 드래그"로 확정되었는지(텍스트 선택/리사이즈 오작동 방지).
    private var dragConfirmed = false
    /// 미리보기가 떠 있는 존. nil이면 가장자리 밖.
    private var currentZone: ScreenGeometry.EdgeZone?
    /// 현재 존의 사용 영역(메뉴바/Dock 제외, CG 전역)과 디스플레이.
    private var edgeUsable: CGRect = .zero
    private var edgeScreen: NSScreen?
    private var edgeDisplayBounds: CGRect = .zero
    /// 가장자리 밴드 폭(px)과 창 드래그 확정 최소 이동거리(px).
    private let edgeThreshold: CGFloat = 12
    private let dragConfirmDistance: CGFloat = 8

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

        // 가장자리 미리보기가 떠 있었다면 정리(그리드와 상호 배타).
        hideEdgePreview()
        clearEdgeDrag()

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
        clearEdgeDrag()
        targetWindow = nil
        pendingWindow = nil
        pendingFrame = nil
        isArmed = false
    }

    // MARK: - 가장자리 절반 스냅

    /// leftMouseDown 시 호출 — 후보 창과 초기 origin을 캡처해 드래그 추적을 시작한다.
    /// 엣지 스냅이 꺼져 있거나 권한이 없으면 아무것도 하지 않는다.
    func beginDrag(at point: CGPoint) {
        clearEdgeDrag()
        guard Settings.shared.edgeSnapEnabled, AccessibilityPermission.isGranted else { return }
        guard let window = AXWindowController.shared.windowUnderCursor(cgPoint: point) else { return }
        dragCandidate = window
        dragInitialOrigin = AXWindowController.shared.frame(of: window)?.origin
    }

    /// leftMouseDragged(그리드 비무장 시) 호출 — 가장자리 존을 판정하고 미리보기를 갱신한다.
    func updateEdgeDrag(to point: CGPoint) {
        guard !isArmed, Settings.shared.edgeSnapEnabled, dragCandidate != nil else { return }
        guard let display = ScreenGeometry.displayContaining(cgPoint: point),
              let screen = ScreenGeometry.screen(for: display.id) else { return }

        let zone = ScreenGeometry.edgeZone(at: point, bounds: display.bounds, threshold: edgeThreshold)
        guard let zone else {
            if currentZone != nil { hideEdgePreview() }
            return
        }

        // 실제 창 드래그인지 확정(초기 origin 대비 이동). 아직이면 미리보기 보류.
        if !dragConfirmed {
            guard let initial = dragInitialOrigin,
                  let now = AXWindowController.shared.frame(of: dragCandidate!)?.origin else { return }
            if hypot(now.x - initial.x, now.y - initial.y) >= dragConfirmDistance {
                dragConfirmed = true
            } else {
                return
            }
        }

        edgeScreen = screen
        edgeDisplayBounds = display.bounds
        edgeUsable = ScreenGeometry.cgVisibleBounds(for: screen)
        let target = applyGaps(ScreenGeometry.rect(for: zone, usable: edgeUsable), within: edgeUsable)
        showEdgePreview(rect: target, screen: screen, displayBounds: display.bounds)
        currentZone = zone
    }

    /// leftMouseUp 시 호출 — 확정된 존이 있으면 pending 목표로 설정한다(실제 스냅은 `commitPending`).
    func endEdgeDrag() {
        if dragConfirmed, let zone = currentZone, let window = dragCandidate {
            pendingWindow = window
            pendingFrame = applyGaps(ScreenGeometry.rect(for: zone, usable: edgeUsable), within: edgeUsable)
            glog("엣지 스냅 목표 zone=\(zone) frame=\(rs(pendingFrame!))")
            hideEdgePreview()
        }
        clearEdgeDrag()
    }

    private func showEdgePreview(rect: CGRect, screen: NSScreen, displayBounds: CGRect) {
        // 디스플레이가 바뀌었으면(원점 불일치) 기존 오버레이를 버리고 새로 만든다.
        if let win = overlay, win.gridView.cgOrigin != displayBounds.origin { teardownOverlay() }
        if overlay == nil {
            let win = GridOverlayWindow(screen: screen)
            win.gridView.previewOnly = true
            win.gridView.cgOrigin = displayBounds.origin
            win.gridView.displayBounds = displayBounds
            win.orderFrontRegardless()
            overlay = win
        }
        overlay?.gridView.selection = rect
    }

    private func hideEdgePreview() {
        teardownOverlay()
        currentZone = nil
    }

    /// 엣지 드래그 추적 상태 초기화(미리보기 오버레이는 건드리지 않음 — 호출부에서 별도 정리).
    private func clearEdgeDrag() {
        dragCandidate = nil
        dragInitialOrigin = nil
        dragConfirmed = false
        currentZone = nil
        edgeScreen = nil
        edgeUsable = .zero
        edgeDisplayBounds = .zero
    }

    // MARK: - 내부

    private func currentSelectionRect() -> CGRect {
        ScreenGeometry.unionRect(anchor: anchor, current: current,
                                 bounds: displayBounds,
                                 cols: Settings.shared.columns,
                                 rows: Settings.shared.rows)
    }

    /// 바깥 여백/안쪽 간격 적용. (그리드 셀은 displayBounds 기준)
    private func applyGaps(_ rect: CGRect) -> CGRect {
        applyGaps(rect, within: displayBounds)
    }

    /// `bounds`의 가장자리에 닿는 변에만 바깥 여백을, 모든 변에 안쪽 간격을 적용한다.
    private func applyGaps(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var r = rect.insetBy(dx: Settings.shared.innerGap, dy: Settings.shared.innerGap)
        let m = Settings.shared.outerMargin
        if m > 0 {
            if abs(rect.minX - bounds.minX) < 1 { r.origin.x += m; r.size.width -= m }
            if abs(rect.maxX - bounds.maxX) < 1 { r.size.width -= m }
            if abs(rect.minY - bounds.minY) < 1 { r.origin.y += m; r.size.height -= m }
            if abs(rect.maxY - bounds.maxY) < 1 { r.size.height -= m }
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
