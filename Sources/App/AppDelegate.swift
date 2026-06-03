import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBar = MenuBarController()

        // 손쉬운 사용(접근성) 권한 확인 → 이벤트 탭 시작.
        // 권한이 없으면 prompt를 띄우고 안내한다. 권한 부여 후 앱 재실행이 필요하다.
        if AccessibilityPermission.isGranted {
            MouseEventTap.shared.start()
        } else {
            AccessibilityPermission.request()   // 시스템 prompt 유도
            if MouseEventTap.shared.start() == false {
                PermissionAlert.show()
            }
        }

        // Sparkle 업데이터 기동.
        _ = UpdaterController.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        MouseEventTap.shared.stop()
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
