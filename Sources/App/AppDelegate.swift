import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var permissionTimer: Timer?
    private var permissionWatchDeadline: Date?
    /// 거부/미허용 상태에서 무한정 폴링하지 않도록 상한(초).
    private let permissionWatchMaxDuration: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBar = MenuBarController()

        // 맨 앞 앱 추적 시작(예외 목록 판정용).
        ActiveAppMonitor.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePermissionWatchRequested),
            name: .accessibilityPermissionWatchRequested,
            object: nil
        )

        // 손쉬운 사용(접근성) 권한 확인 → 이벤트 탭 시작.
        // 권한이 없으면 최초 실행에서만 prompt를 띄우고, 허용되는 즉시 이벤트 탭
        // 설치를 재시도한다. 매 실행마다 prompt를 요청하면 macOS의 TCC 반영이 늦을
        // 때 같은 안내가 반복될 수 있다.
        if AccessibilityPermission.isGranted {
            if !MouseEventTap.shared.start() {
                // AXIsProcessTrusted는 true인데 탭 생성이 실패하는 TCC 반영 지연
                // (업데이트/재서명 직후)에서는 watcher가 성공할 때까지 재시도한다.
                glog("권한 허용 상태에서 이벤트 탭 설치 실패 → watcher로 재시도")
                startPermissionWatcher()
            }
        } else {
            let isFirstRequest = !AccessibilityPermission.hasRequestedBefore
            AccessibilityPermission.requestOnce()
            if !isFirstRequest {
                // 재실행인데 여전히 권한이 없으면 시스템 prompt는 다시 뜨지 않는다.
                // 메뉴바 앱이라 조용히 죽은 것처럼 보이지 않도록 복구 방법을 안내한다.
                PermissionNotice.showDenied()
            }
            startPermissionWatcher()
        }

        #if !MAS
        // Sparkle 업데이터 기동. MAS 판은 App Store가 업데이트를 맡는다.
        _ = UpdaterController.shared
        #endif

        // 첫 실행(또는 아직 가이드를 끝내지 않음) → 온보딩. 메뉴바 전용 앱이라 이게 없으면
        // 사용자는 앱이 켜졌는지도, 어떻게 쓰는지도 알 수 없다.
        if !Settings.shared.onboardingCompleted {
            OnboardingWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        MouseEventTap.shared.stop()
        ActiveAppMonitor.shared.stop()
    }

    @objc private func handlePermissionWatchRequested() {
        MainActor.assumeIsolated {
            // 권한이 있어도 탭 설치가 실패할 수 있다(TCC 반영 지연) → 실패 시에도 watcher로 재시도.
            if AccessibilityPermission.isGranted, MouseEventTap.shared.start() { return }
            startPermissionWatcher()
        }
    }

    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        permissionWatchDeadline = Date().addingTimeInterval(permissionWatchMaxDuration)
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if let deadline = self.permissionWatchDeadline, Date() >= deadline {
                    glog("권한 대기 watcher 타임아웃 — 폴링 중지(메뉴에서 다시 요청 가능)")
                    timer.invalidate()
                    self.permissionTimer = nil
                    self.permissionWatchDeadline = nil
                    return
                }
                guard AccessibilityPermission.isGranted else { return }
                if MouseEventTap.shared.start() {
                    glog("손쉬운 사용 권한 허용 감지 → 이벤트 탭 시작")
                    timer.invalidate()
                    self.permissionTimer = nil
                    self.permissionWatchDeadline = nil
                    AccessibilityPermission.notifyStatusChanged()
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
        appMenu.addItem(withTitle: String(localized: "Quit \(Brand.name)"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // 메뉴바 앱이므로 마지막 윈도우가 닫혀도 종료하지 않는다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
