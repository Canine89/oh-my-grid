import AppKit
import ApplicationServices

/// 전역 키보드 단축키로 맨 앞 앱의 포커스 창을 절반/사분면/최대화/가운데로 스냅한다.
/// 입력은 `MouseEventTap`의 keyDown 에서 넘어오고, 성공하면 이벤트를 소비한다.
@MainActor
final class KeyboardSnapController {
    static let shared = KeyboardSnapController()
    private init() {}

    private var request = WindowRequest()
    private var requestGeneration = 0
    private var flash: GridOverlayWindow?

    /// keyDown 이벤트가 스냅 단축키와 일치하면 실행하고 true(이벤트 소비).
    func handle(_ event: CGEvent) -> Bool {
        guard Settings.shared.keyboardSnapEnabled else { return false }
        let hotkeys = Settings.shared.snapHotkeys
        guard let action = SnapAction.allCases.first(where: { (hotkeys[$0] ?? $0.defaultHotkey).matches(event) }) else {
            return false
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { self.perform(action) }
        }
        return true   // 일치했으면 창을 못 찾아도 소비(다른 앱에 ⌃⌥← 가 흘러가지 않게)
    }

    /// 동작 실행(메뉴에서도 호출).
    func perform(_ action: SnapAction) {
        guard AccessibilityPermission.isGranted else {
            PermissionNotice.showDenied()
            return
        }
        guard !ShortcutRecorderView.isRecordingShortcut else { return }
        request.cancel()
        request = WindowRequest()
        requestGeneration &+= 1
        let generation = requestGeneration
        AXWindowController.shared.queryWindow(request: request) { [weak self] result in
            guard let self, self.requestGeneration == generation else { return }
            switch result {
            case .failure(let error): PermissionNotice.show(text: error.message)
            case .success(let snapshot): self.place(action, snapshot: snapshot, generation: generation)
            }
        }
    }

    private func place(_ action: SnapAction, snapshot: WindowSnapshot, generation: Int) {
        let frame = snapshot.frame
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
        AXWindowController.shared.setFrame(target, for: snapshot.element, request: request) { [weak self] result in
            guard let self, self.requestGeneration == generation else { return }
            switch result {
            case .success(let actual):
                self.showFlash(rect: actual.frame, action: action, screen: screen, displayBounds: display.bounds)
            case .failure(let error): PermissionNotice.show(text: error.message)
            }
        }
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
