import AppKit
import SwiftUI

/// 스토어 스크린샷 촬영용 모드. `-OMGScreenshot settings|onboarding|overlay` 런치 인자가
/// 있으면 메뉴바·이벤트 탭·권한 요청 등 평소 기동을 전부 생략하고 해당 창만 띄운다.
/// (UserDefaults는 `-키 값` 런치 인자를 argument domain으로 읽는다.) 언어는 `-appLanguage ko`.
@MainActor
enum ScreenshotMode {
    private static var window: NSWindow?
    private static var store: SettingsStore?
    private static var overlay: GridOverlayWindow?

    /// 스크린샷 모드였으면 true — 호출부(AppDelegate)는 즉시 반환해야 한다.
    static func activateIfRequested() -> Bool {
        guard let mode = UserDefaults.standard.string(forKey: "OMGScreenshot") else { return false }
        // LSUIElement 앱은 활성화가 거부돼 타이틀바 탭이 '>>'로 접힌다 → 촬영 중엔 일반 앱으로.
        NSApp.setActivationPolicy(.regular)
        switch mode {
        case "settings":
            showSettings()
        case "onboarding":
            OnboardingWindowController.shared.show()
        case "overlay":
            showOverlay()
        default:
            return false
        }
        return true
    }

    /// 설정 창을 자체 윈도우로 띄운다. `-OMGScreenshotTab general|grid|hotkey|presets|exclusion|about`
    /// 으로 탭을 고른다. (기본 창 폭 560은 6개 탭이 접히므로 여유 있게 잡는다.)
    private static func showSettings() {
        let tab: SettingsView.Tab
        switch UserDefaults.standard.string(forKey: "OMGScreenshotTab") {
        case "grid": tab = .grid
        case "hotkey": tab = .hotkey
        case "presets": tab = .presets
        case "exclusion": tab = .exclusion
        case "about": tab = .about
        default: tab = .general
        }
        let s = SettingsStore()
        s.tab = tab
        store = s
        let host = NSHostingView(rootView: LocalizedRoot { SettingsView(store: s) })
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = String(localized: "\(Brand.name) Settings")
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.setContentSize(host.fittingSize)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        // 비활성 앱에서는 TabView 타이틀바 탭이 '>>'로 접혀 찍힌다 — 탭은 런치 인자로 이미
        // 골랐으니 툴바 자체를 제거한다(SwiftUI가 늦게 붙이므로 잠시 후, 몇 번 반복).
        for delay in [0.3, 0.8, 1.5, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { win.toolbar = nil }
        }
    }

    /// 그리드 오버레이를 대표 선택 상태(6×4 중 3×2 블록)로 띄운다.
    private static func showOverlay() {
        guard let screen = NSScreen.main else { return }
        let usable = ScreenGeometry.cgVisibleBounds(for: screen)
        let cols = 6, rows = 4
        let anchor = ScreenGeometry.Cell(col: 1, row: 1)
        let current = ScreenGeometry.Cell(col: 3, row: 2)
        let sel = ScreenGeometry.unionRect(anchor: anchor, current: current,
                                           bounds: usable, cols: cols, rows: rows)
        let win = GridOverlayWindow(screen: screen)
        win.gridView.cgOrigin = CGDisplayBounds(screen.displayID).origin
        win.gridView.displayBounds = usable
        win.gridView.columns = cols
        win.gridView.rows = rows
        win.gridView.rebuildGrid()
        win.gridView.selection = sel
        win.gridView.label = "3 × 2  ·  \(Int(sel.width)) × \(Int(sel.height))"
        win.fadeIn()
        overlay = win
    }
}
