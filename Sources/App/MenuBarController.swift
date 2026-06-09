import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var prefs: PreferencesWindowController?
    private var enabledItem: NSMenuItem?
    private var permissionItem: NSMenuItem?

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
        for (i, preset) in WindowResizeController.presets.enumerated() {
            let it = NSMenuItem(title: preset.label, action: #selector(armResize(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            resizeMenu.addItem(it)
        }
        resizeItem.submenu = resizeMenu
        menu.addItem(resizeItem)

        // 트랙패드용 안내(클릭 불가 정보 항목).
        let hotkeyHint = NSMenuItem(title: "트랙패드: ⌃⌥G 로 그리드 모드", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        addItem(to: menu, title: "설정…", action: #selector(openPreferences), key: ",")

        // Sparkle 업데이트 확인.
        let updateItem = NSMenuItem(title: "업데이트 확인…",
                                    action: #selector(UpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = UpdaterController.shared
        menu.addItem(updateItem)

        // 권한 미허용 시에만 보이는 안내 항목.
        let perm = addItem(to: menu, title: "손쉬운 사용 권한 허용…", action: #selector(openAccessibility))
        permissionItem = perm

        menu.addItem(.separator())
        addItem(to: menu, title: "\(Brand.name) 종료", action: #selector(quit), key: "q")
        statusItem.menu = menu
    }

    // 메뉴를 열 때마다 토글 체크/권한 항목 상태를 갱신.
    func menuWillOpen(_ menu: NSMenu) {
        enabledItem?.state = Settings.shared.enabled ? .on : .off
        permissionItem?.isHidden = AccessibilityPermission.isGranted
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

    @objc private func openAccessibility() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
