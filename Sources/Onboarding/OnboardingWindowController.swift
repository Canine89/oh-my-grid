import AppKit
import SwiftUI

/// 첫 실행 온보딩 창. 언어 선택 → 권한 → 연습 → 마무리. 권한 상태를 실시간 반영하고,
/// 연습 화면에서는 이 창 자체가 그리드 스냅 대상이 된다.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private override init() { super.init() }

    private var window: NSWindow?
    private var model: OnboardingModel?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// 연습 화면 진입 시의 창 프레임. 스냅 성공 뒤 이 크기로 되돌린다.
    private var practiceFrame: NSRect?
    private var pageCancellable: Any?

    func show() {
        if window == nil { build() }
        model?.permissionGranted = AccessibilityPermission.isGranted
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startObserving()
    }

    private func build() {
        let model = OnboardingModel()
        model.onFinish = { [weak self] in self?.finish() }
        model.onOpenPermission = { [weak self] in
            AccessibilityPermission.requestAndOpenSettings()
            self?.startPermissionPoll()
        }
        self.model = model

        let host = NSHostingView(rootView: LocalizedRoot { OnboardingView(model: model) })
        // 연습 화면에서 그리드로 크기가 바뀌어야 하므로 resizable 이어야 한다(AX 리사이즈 허용).
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = String(localized: "Getting Started with \(Brand.name)")
        win.contentView = host
        win.minSize = NSSize(width: 520, height: 440)
        win.delegate = self
        win.isReleasedWhenClosed = false
        window = win

        // 페이지 전환 감시: 연습 화면 진입 시 프레임 저장.
        pageCancellable = model.$page.sink { [weak self] page in
            guard let self else { return }
            if page == .practice { self.practiceFrame = self.window?.frame }
        }
    }

    // MARK: 관찰

    private func startObserving() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .accessibilityPermissionChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        })
        observers.append(nc.addObserver(forName: .gridSnapCommitted, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleSnap(note) }
        })
        observers.append(nc.addObserver(forName: .appLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            // 본문은 LocalizedRoot 가 다시 그린다. 창 제목만 여기서.
            MainActor.assumeIsolated { self?.window?.title = String(localized: "Getting Started with \(Brand.name)") }
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
        guard permissionTimer == nil, !AccessibilityPermission.isGranted else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshPermission() {
        guard let model else { return }
        let granted = AccessibilityPermission.isGranted
        let wasGranted = model.permissionGranted
        model.permissionGranted = granted
        if granted {
            permissionTimer?.invalidate()
            permissionTimer = nil
            _ = MouseEventTap.shared.start()   // 이미 있으면 no-op
            // 권한 화면에서 방금 허용됐으면 잠시 뒤 자동으로 연습 화면으로.
            if !wasGranted, model.page == .permission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let m = self?.model, m.page == .permission, m.permissionGranted else { return }
                        m.next()
                        self?.window?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
    }

    /// 그리드 스냅이 우리 프로세스의 창(=이 온보딩 창)에 적용되면 연습 성공.
    private func handleSnap(_ note: Notification) {
        guard let model, model.page == .practice, !model.snapSucceeded else { return }
        guard let pid = note.userInfo?["pid"] as? pid_t, pid == getpid() else { return }
        model.snapSucceeded = true
        // 스냅이 실제로 반영된 뒤(commitPending 지연 0.18s) 원래 크기로 부드럽게 복귀.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let win = self.window, let frame = self.practiceFrame else { return }
                var target = frame
                if let screen = win.screen ?? NSScreen.main {
                    let vf = screen.visibleFrame
                    target.origin.x = min(max(target.minX, vf.minX), vf.maxX - target.width)
                    target.origin.y = min(max(target.minY, vf.minY), vf.maxY - target.height)
                }
                win.setFrame(target, display: true, animate: true)
            }
        }
    }

    private func finish() {
        model?.applyFinishChoices()
        Settings.shared.onboardingCompleted = true
        window?.close()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 도중에 닫아도 다시 나오지 않게 한다(메뉴 → 시작 가이드… 로 재진입 가능).
        Settings.shared.onboardingCompleted = true
        stopObserving()
        // 다음에 열 때 처음부터 시작.
        window = nil
        model = nil
        pageCancellable = nil
        practiceFrame = nil
    }
}
