import AppKit
import ApplicationServices

/// 전역 키보드 단축키로 맨 앞 앱의 포커스 창을 절반/사분면/최대화/가운데로 스냅한다.
/// 입력은 `MouseEventTap`의 keyDown 에서 넘어오고, 성공하면 이벤트를 소비한다.
@MainActor
final class KeyboardSnapController {
    static let shared = KeyboardSnapController()
    private init() {}

    private var flash: GridOverlayWindow?

    /// keyDown 이벤트가 스냅 단축키와 일치하면 실행하고 true(이벤트 소비).
    func handle(_ event: CGEvent) -> Bool {
        guard Settings.shared.keyboardSnapEnabled else { return false }
        let hotkeys = Settings.shared.snapHotkeys
        guard let action = SnapAction.allCases.first(where: { (hotkeys[$0] ?? $0.defaultHotkey).matches(event) }) else {
            return false
        }
        perform(action)
        return true   // 일치했으면 창을 못 찾아도 소비(다른 앱에 ⌃⌥← 가 흘러가지 않게)
    }

    /// 동작 실행(메뉴에서도 호출).
    func perform(_ action: SnapAction) {
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            return
        }
        guard let window = AXWindowController.shared.frontmostFocusedWindow(),
              let frame = AXWindowController.shared.frame(of: window) else {
            glog("keyboard snap: no focused window")
            return
        }
        // 우리 앱 창(설정·온보딩)도 스냅 대상이 되어도 무해하다.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let display = ScreenGeometry.displayContaining(cgPoint: center),
              let screen = ScreenGeometry.screen(for: display.id) else { return }
        let usable = ScreenGeometry.cgVisibleBounds(for: screen)
        var target = action.targetRect(usable: usable, current: frame)
        if action != .center {
            target = ScreenGeometry.applyGaps(target, within: usable,
                                              outerMargin: Settings.shared.outerMargin,
                                              innerGap: Settings.shared.innerGap)
        }
        AXWindowController.shared.setFrame(target, for: window)
        glog("keyboard snap \(action.rawValue) → \(rs(target))")
        showFlash(rect: target, action: action, screen: screen, displayBounds: display.bounds)
    }

    /// 목표 영역을 짧게 비춰 어디로 갔는지 보여준다(가장자리 미리보기와 같은 룩).
    private func showFlash(rect: CGRect, action: SnapAction, screen: NSScreen, displayBounds: CGRect) {
        flash?.fadeOut()
        let win = GridOverlayWindow(screen: screen)
        win.gridView.previewOnly = true
        win.gridView.cgOrigin = displayBounds.origin
        win.gridView.displayBounds = displayBounds
        win.gridView.rebuildGrid()
        win.gridView.selection = rect
        win.gridView.label = "\(action.title)  ·  \(Int(rect.width)) × \(Int(rect.height))"
        win.fadeIn()
        flash = win
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.flash === win else { return }
                win.fadeOut()
                self?.flash = nil
            }
        }
    }
}
