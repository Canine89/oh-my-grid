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
            Preset(label: "4:3 · 720 × 480",    size: CGSize(width: 720,  height: 480)),
            Preset(label: "16:9 · 1280 × 720",  size: CGSize(width: 1280, height: 720)),
            Preset(label: "16:9 · 1920 × 1080", size: CGSize(width: 1920, height: 1080)),
        ]),
        // Mac App Store 스크린샷 요구 해상도(16:10, 픽셀 기준).
        // 창 크기는 포인트라서 Retina(2x) 디스플레이에서는 1280×800 창이 2560×1600 픽셀로 캡처된다.
        PresetGroup(title: String(localized: "App Store Screenshots (Mac · 16:10)"), presets: [
            Preset(label: String(localized: "1280 × 800  (Retina capture → 2560 × 1600)"), size: CGSize(width: 1280, height: 800)),
            Preset(label: String(localized: "1440 × 900  (Retina capture → 2880 × 1800)"), size: CGSize(width: 1440, height: 900)),
            Preset(label: "2560 × 1600", size: CGSize(width: 2560, height: 1600)),
            Preset(label: "2880 × 1800", size: CGSize(width: 2880, height: 1800)),
        ]),
    ] }
    /// 기본 그룹 + 사용자 지정 그룹(설정에서 편집, 비어 있으면 생략). 메뉴는 열 때마다 이걸로 다시 만든다.
    static var presetGroups: [PresetGroup] {
        let custom = Settings.shared.customPresets
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
    private var hoveredWindow: AXUIElement?
    /// 비동기 호버 조회 무효화 토큰(이동이 빠르면 마지막 1건만 실제 조회).
    private var hoverToken = 0

    /// 메뉴에서 프리셋 선택 → 다음 창 클릭을 기다린다.
    func arm(size: CGSize, label: String) {
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            AccessibilityPermission.requestAndOpenSettings()
            return
        }
        pendingSize = size
        hoveredWindow = nil
        MouseEventTap.shared.setTracksMouseMoved(true)
        showHUD(text: String(localized: "Click the window to resize — \(label)   (Esc to cancel)"))
        glog("창 크기 고정 무장 \(Int(size.width))x\(Int(size.height))")
    }

    /// 크기 가져오기 무장 — 다음 클릭한 창의 현재 크기를 `handler`로 전달한다(설정의 프리셋 추가용).
    func armCapture(_ handler: @escaping (CGSize) -> Void) {
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            AccessibilityPermission.requestAndOpenSettings()
            return
        }
        pendingSize = nil
        captureHandler = handler
        hoveredWindow = nil
        MouseEventTap.shared.setTracksMouseMoved(true)
        showHUD(text: String(localized: "Click a window to capture its size   (Esc to cancel)"))
        glog("창 크기 가져오기 무장")
    }

    /// 무장 해제(성공/취소 공통).
    func cancel() {
        pendingSize = nil
        captureHandler = nil
        hoveredWindow = nil
        hoverToken &+= 1
        MouseEventTap.shared.setTracksMouseMoved(false)
        hideHUD()
        hideHighlight()
    }

    /// 무장 중 마우스 이동 시 호출 — 커서 아래 창을 비동기로 찾아 강조한다.
    /// 탭 콜백을 막지 않도록(전역 입력 지연 방지) main 큐로 넘겨 조회한다.
    func updateHover(at point: CGPoint) {
        guard isArmed else { return }
        hoverToken &+= 1
        let token = hoverToken
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isArmed, self.hoverToken == token else { return }
                guard let window = AXWindowController.shared.windowUnderCursor(cgPoint: point) else {
                    self.hoveredWindow = nil
                    self.hideHighlight()
                    return
                }
                // 우리 앱 창(강조/HUD)을 집었으면 현재 강조를 그대로 유지(깜빡임 방지).
                var pid: pid_t = 0
                if AXUIElementGetPid(window, &pid) == .success, pid == getpid() { return }
                guard let frame = AXWindowController.shared.frame(of: window) else { return }
                self.hoveredWindow = window
                self.showHighlight(cgFrame: frame)
            }
        }
    }

    /// 좌클릭 지점의 창을 고정 크기로 리사이즈. 호출 후엔 항상 무장 해제된다.
    func applyAt(point: CGPoint) {
        let target = hoveredWindow
        defer { cancel() }
        guard isArmed, AccessibilityPermission.isGranted else { return }
        hideHighlight()   // 강조 오버레이가 AX 조회를 가리지 않도록 먼저 내림.
        // 호버로 잡아둔 창을 우선 사용(강조 오버레이 간섭 회피), 없으면 위치로 조회.
        guard let window = target ?? AXWindowController.shared.windowUnderCursor(cgPoint: point) else {
            glog("창 크기 고정: 클릭 위치에 창 없음")
            return
        }
        // 우리 앱 자신의 창(HUD·설정 등)은 건드리지 않는다.
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success, pid == getpid() { return }

        // 크기 가져오기 모드: 리사이즈 대신 현재 크기를 넘기고 끝.
        if let handler = captureHandler {
            if let frame = AXWindowController.shared.frame(of: window) {
                glog("창 크기 가져오기 \(Int(frame.width))x\(Int(frame.height))")
                handler(frame.size)
            }
            return
        }
        guard let size = pendingSize else { return }

        // 현재 좌상단(origin) 유지 + 가시 영역 안으로 클램프.
        let origin = AXWindowController.shared.frame(of: window)?.origin ?? point
        var rect = CGRect(origin: origin, size: size)
        if let display = ScreenGeometry.displayContaining(cgPoint: point),
           let screen = ScreenGeometry.screen(for: display.id) {
            let usable = ScreenGeometry.cgVisibleBounds(for: screen)
            rect = clamp(rect, within: usable)
            // 화면 사용 영역보다 큰 프리셋(App Store 2560×1600 등)은 앱이 창을 그 크기로 못 늘린다 → 안내.
            if size.width > usable.width || size.height > usable.height {
                PermissionNotice.show(text: String(localized: "\(Int(size.width)) × \(Int(size.height)) is larger than this screen’s usable area (\(Int(usable.width)) × \(Int(usable.height))) and may not fit"))
            }
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
