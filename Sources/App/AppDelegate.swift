import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBar = MenuBarController()

        // 맨 앞 앱 추적 시작(예외 목록 판정용).
        ActiveAppMonitor.shared.start()

        // 손쉬운 사용(접근성) 권한 확인 → 이벤트 탭 시작.
        // 권한이 없으면 prompt를 띄우고, 허용되는 즉시 이벤트 탭 설치를 재시도한다.
        if AccessibilityPermission.isGranted {
            MouseEventTap.shared.start()
        } else {
            AccessibilityPermission.request()   // 시스템 prompt 유도
            startPermissionWatcher()
            if MouseEventTap.shared.start() == false {
                PermissionAlert.show()
            }
        }

        // Sparkle 업데이터 기동.
        _ = UpdaterController.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        MouseEventTap.shared.stop()
        ActiveAppMonitor.shared.stop()
    }

    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AccessibilityPermission.isGranted else { return }
                if MouseEventTap.shared.start() {
                    glog("손쉬운 사용 권한 허용 감지 → 이벤트 탭 시작")
                    timer.invalidate()
                    self?.permissionTimer = nil
                }
            }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 표준 Edit 메뉴(⌘C 등)를 둔다.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "\(Brand.name) 종료",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "복사", action: Selector(("copy:")), keyEquivalent: "c")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // 메뉴바 앱이므로 마지막 윈도우가 닫혀도 종료하지 않는다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
