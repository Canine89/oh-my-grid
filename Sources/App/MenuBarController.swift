import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var prefs: PreferencesWindowController?
    private var enabledItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var hotkeyHintItem: NSMenuItem?
    private var updateItem: NSMenuItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.3x3",
                                   accessibilityDescription: "\(Brand.name) 그리드")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "\(Brand.name) · \(Brand.tagline)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        enabledItem = addItem(to: menu, title: "그리드 켜기", action: #selector(toggleEnabled))

        // 창 크기 고정: 비율 선택 → 바꿀 창 클릭.
        let resizeItem = NSMenuItem(title: "창 크기 고정", action: nil, keyEquivalent: "")
        let resizeMenu = NSMenu()
        var tag = 0
        for (gi, group) in WindowResizeController.presetGroups.enumerated() {
            if gi > 0 { resizeMenu.addItem(.separator()) }
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            resizeMenu.addItem(header)
            for preset in group.presets {
                let it = NSMenuItem(title: preset.label, action: #selector(armResize(_:)), keyEquivalent: "")
                it.target = self
                it.tag = tag          // WindowResizeController.presets(평탄화) 인덱스
                it.indentationLevel = 1
                resizeMenu.addItem(it)
                tag += 1
            }
        }
        resizeItem.submenu = resizeMenu
        menu.addItem(resizeItem)

        // 트랙패드용 안내(클릭 불가 정보 항목). 제목은 menuWillOpen에서 현재 단축키로 갱신.
        let hotkeyHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)
        hotkeyHintItem = hotkeyHint

        addItem(to: menu, title: "설정…", action: #selector(openPreferences), key: ",")
        addItem(to: menu, title: "시작 가이드…", action: #selector(openOnboarding))

        // Sparkle 업데이트 확인.
        let updateItem = NSMenuItem(title: "업데이트 확인…",
                                    action: #selector(UpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = UpdaterController.shared
        menu.addItem(updateItem)
        self.updateItem = updateItem

        // 권한 미허용 시에만 보이는 안내 항목.
        let perm = addItem(to: menu, title: "손쉬운 사용 권한 다시 요청…", action: #selector(openAccessibility))
        permissionItem = perm

        menu.addItem(.separator())
        addItem(to: menu, title: "\(Brand.name) 종료", action: #selector(quit), key: "q")
        statusItem.menu = menu
    }

    // 메뉴를 열 때마다 토글 체크/권한 항목 상태를 갱신.
    func menuWillOpen(_ menu: NSMenu) {
        enabledItem?.state = Settings.shared.enabled ? .on : .off
        let granted = AccessibilityPermission.isGranted
        permissionItem?.isHidden = granted
        // 권한 watcher 타임아웃 이후 뒤늦게 허용된 경우: 메뉴만 열어도 탭을 복구한다(이미 있으면 no-op).
        if granted { _ = MouseEventTap.shared.start() }
        hotkeyHintItem?.title = "트랙패드: 드래그 중 \(Settings.shared.gridHotkey.displayString)"
        let updater = UpdaterController.shared
        updateItem?.title = updater.lastFailure == nil ? "업데이트 확인…" : "업데이트 다시 시도…"
        updateItem?.isEnabled = updater.lastFailure != nil || updater.canCheckForUpdates
        updateItem?.toolTip = updater.lastFailure?.localizedDescription
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
        NotificationCenter.default.post(name: .gridSettingsChanged, object: nil)
    }

    @objc private func armResize(_ sender: NSMenuItem) {
        let preset = WindowResizeController.presets[sender.tag]
        WindowResizeController.shared.arm(size: preset.size, label: preset.label)
    }

    @objc private func openPreferences() {
        if prefs == nil { prefs = PreferencesWindowController() }
        prefs?.showWindow()
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.shared.show()
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.requestAndOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
