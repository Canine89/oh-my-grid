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
    /// 메뉴에 섹션으로 나뉘어 표시되는 프리셋 그룹. `title`은 비활성 헤더 항목으로 보인다.
    struct PresetGroup {
        let title: String
        let presets: [Preset]
    }
    /// 제목이 로컬라이즈되므로 캐시하지 않는다(표시 언어가 바뀔 수 있다).
    static var builtinGroups: [PresetGroup] { [
        PresetGroup(title: String(localized: "Video"), presets: [
            Preset(label: "4:3 · 640 × 480",    size: CGSize(width: 640,  height: 480)),
            Preset(label: "16:9 · 1280 × 720",  size: CGSize(width: 1280, height: 720)),
            Preset(label: "16:9 · 1920 × 1080", size: CGSize(width: 1920, height: 1080)),
        ]),
    ] }
    /// 기본 그룹 + 사용자 지정 그룹(설정에서 편집, 비어 있으면 생략). 메뉴는 열 때마다 이걸로 다시 만든다.
    static var presetGroups: [PresetGroup] {
        let custom = Settings.shared.customPresets.filter(\.isValid)
        guard !custom.isEmpty else { return builtinGroups }
        let group = PresetGroup(title: String(localized: "Custom"), presets: custom.map {
            Preset(label: $0.label, size: CGSize(width: $0.width, height: $0.height))
        })
        return builtinGroups + [group]
    }
    /// 그룹을 평탄화한 목록. 메뉴 항목 `tag`가 이 배열의 인덱스다.
    static var presets: [Preset] { presetGroups.flatMap(\.presets) }

    private(set) var pendingSize: CGSize?
    /// 크기 가져오기 모드: 다음 클릭한 창의 크기를 이 핸들러로 넘긴다(리사이즈는 하지 않음).
    private var captureHandler: ((CGSize) -> Void)?
    var isArmed: Bool { pendingSize != nil || captureHandler != nil }
    private var hud: ResizeHUDWindow?

    // 호버 강조 상태.
    private var highlight: ResizeHighlightWindow?
    /// 호버 중 잡아둔 대상 창. 클릭 시 이 창을 재사용해 강조 오버레이를 다시 조회하지 않는다.
    private var hoverPoint: CGPoint?
    private var hoverInFlight = false
    private var request = WindowRequest()
    private var actionGeneration = 0
    /// 비동기 호버 조회 무효화 토큰(이동이 빠르면 마지막 1건만 실제 조회).
    private var hoverToken = 0

    /// 메뉴에서 프리셋 선택 → 다음 창 클릭을 기다린다.
    func arm(size: CGSize, label: String) {
        cancel()
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, size.width <= 16384, size.height <= 16384 else {
            PermissionNotice.show(text: WindowFailure.invalidGeometry.message)
            return
        }
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            AccessibilityPermission.requestAndOpenSettings()
            return
        }
        pendingSize = size
        hoverPoint = nil
        MouseEventTap.shared.setTracksMouseMoved(true)
        showHUD(text: String(localized: "Click the window to resize — \(label)   (Esc to cancel)"))
        glog("창 크기 고정 무장 \(Int(size.width))x\(Int(size.height))")
    }

    /// 크기 가져오기 무장 — 다음 클릭한 창의 현재 크기를 `handler`로 전달한다(설정의 프리셋 추가용).
    func armCapture(_ handler: @escaping (CGSize) -> Void) {
        cancel()
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            AccessibilityPermission.requestAndOpenSettings()
            return
        }
        pendingSize = nil
        captureHandler = handler
        hoverPoint = nil
        MouseEventTap.shared.setTracksMouseMoved(true)
        showHUD(text: String(localized: "Click a window to capture its size   (Esc to cancel)"))
        glog("창 크기 가져오기 무장")
    }

    /// 무장 해제(성공/취소 공통).
    func cancel() {
        request.cancel()
        request = WindowRequest()
        actionGeneration &+= 1
        hoverInFlight = false
        pendingSize = nil
        captureHandler = nil
        hoverPoint = nil
        hoverToken &+= 1
        MouseEventTap.shared.setTracksMouseMoved(false)
        hideHUD()
        hideHighlight()
    }

    /// 무장 중 마우스 이동 시 호출 — 커서 아래 창을 비동기로 찾아 강조한다.
    /// 탭 콜백을 막지 않도록(전역 입력 지연 방지) main 큐로 넘겨 조회한다.
    func updateHover(at point: CGPoint) {
        guard isArmed else { return }
        hoverPoint = point
        guard !hoverInFlight else { return }
        hoverInFlight = true
        let token = hoverToken
        AXWindowController.shared.queryWindow(at: point, request: request) { [weak self] result in
            guard let self, self.isArmed, self.hoverToken == token else { return }
            self.hoverInFlight = false
            if let latest = self.hoverPoint, latest != point {
                self.updateHover(at: latest)
                return
            }
            guard case .success(let snapshot) = result, snapshot.pid != getpid() else {
                self.hideHighlight()
                return
            }
            self.showHighlight(cgFrame: snapshot.frame)
        }
    }

    /// Capture the click's point and finish the input mode before asynchronous AX work starts.
    func applyAt(point: CGPoint) {
        guard isArmed else { return }
        let size = pendingSize
        let handler = captureHandler
        cancel()
        let generation = actionGeneration
        AXWindowController.shared.queryWindow(at: point, request: request) { [weak self] result in
            guard let self, self.actionGeneration == generation else { return }
            switch result {
            case .failure(let error): PermissionNotice.show(text: error.message)
            case .success(let snapshot):
                guard snapshot.pid != getpid() else {
                    PermissionNotice.show(text: WindowFailure.noWindow.message)
                    return
                }
                if let handler {
                    handler(snapshot.frame.size)
                    return
                }
                guard let size else { return }
                var rect = CGRect(origin: snapshot.frame.origin, size: size)
                if let display = ScreenGeometry.displayContaining(cgPoint: point),
                   let screen = ScreenGeometry.screen(for: display.id) {
                    let usable = ScreenGeometry.cgVisibleBounds(for: screen)
                    rect = self.clamp(rect, within: usable)
                }
                AXWindowController.shared.setFrame(rect, for: snapshot.element, request: self.request) { result in
                    guard self.actionGeneration == generation else { return }
                    if case .failure(let error) = result { PermissionNotice.show(text: error.message) }
                }
            }
        }
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

    private func showHighlight(cgFrame: CGRect) {
        if highlight == nil {
            let win = ResizeHighlightWindow()
            win.orderFrontRegardless()
            highlight = win
        }
        highlight?.place(cgFrame: cgFrame)
    }

    private func hideHighlight() {
        highlight?.orderOut(nil)
        highlight = nil
    }
}
