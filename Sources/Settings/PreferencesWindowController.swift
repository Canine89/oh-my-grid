import AppKit
import SwiftUI

/// 설정 창 호스트. 본문은 SwiftUI(`SettingsView`), 상태는 `SettingsStore`.
/// 권한 상태 폴링과 외부 변경(메뉴 토글·온보딩) 반영, Sparkle/AX 연결만 여기서 맡는다.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var store: SettingsStore?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func showWindow() {
        if window == nil { build() }
        store?.reload()
        startObserving()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let store = SettingsStore()
        #if !MAS
        store.checkForUpdates = { UpdaterController.shared.checkForUpdates(nil) }
        #endif
        store.captureWindowSize = { [weak self] handler in
            // 설정 창이 클릭 대상을 가리지 않도록 잠시 뒤로 보낸 뒤 캡처 모드로.
            self?.window?.orderBack(nil)
            WindowResizeController.shared.armCapture { size in
                handler(size)
                self?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        store.openOnboarding = { OnboardingWindowController.shared.show() }
        self.store = store

        let host = NSHostingView(rootView: SettingsView(store: store))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = String(localized: "\(Brand.name) Settings")
        win.contentView = host
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.setContentSize(host.fittingSize)
        window = win
    }

    // MARK: 관찰

    private func startObserving() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .accessibilityPermissionChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store?.reload(); self?.refreshPermission() }
        })
        observers.append(nc.addObserver(forName: .gridSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            // 메뉴 토글·온보딩 등 외부 변경 반영(자기 자신이 보낸 것도 값이 같아 무해).
            MainActor.assumeIsolated { self?.store?.reload() }
        })
        if !AccessibilityPermission.isGranted { startPermissionPoll() }
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startPermissionPoll() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshPermission() {
        let granted = AccessibilityPermission.isGranted
        store?.permissionGranted = granted
        if granted {
            permissionTimer?.invalidate()
            permissionTimer = nil
            // 권한 watcher 타임아웃 이후 뒤늦게 허용된 경우에도 탭을 복구한다(이미 있으면 no-op).
            _ = MouseEventTap.shared.start()
        } else {
            startPermissionPoll()
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopObserving()
    }
}
