import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var prefs: PreferencesWindowController?
    private var enabledItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var hotkeyHintItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var resizeItem: NSMenuItem?
    private var snapItem: NSMenuItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.3x3",
                                   accessibilityDescription: String(localized: "\(Brand.name) grid"))
            button.image?.isTemplate = true
        }
        buildMenu()
        // 표시 언어가 바뀌면 제목을 전부 다시 만든다.
        NotificationCenter.default.addObserver(forName: .appLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.buildMenu() }
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "\(Brand.name) · \(Brand.tagline)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        enabledItem = addItem(to: menu, title: String(localized: "Enable Grid"), action: #selector(toggleEnabled))

        // 창 스냅(키보드 단축키와 같은 동작을 메뉴에서도). 단축키가 바뀔 수 있어 열 때마다 다시 만든다.
        let snapItem = NSMenuItem(title: String(localized: "Snap Window"), action: nil, keyEquivalent: "")
        snapItem.submenu = makeSnapMenu()
        menu.addItem(snapItem)
        self.snapItem = snapItem

        // 창 크기 고정: 비율 선택 → 바꿀 창 클릭. 사용자 지정 프리셋이 바뀔 수 있어 열 때마다 다시 만든다.
        let resizeItem = NSMenuItem(title: String(localized: "Resize Window"), action: nil, keyEquivalent: "")
        resizeItem.submenu = makeResizeMenu()
        menu.addItem(resizeItem)
        self.resizeItem = resizeItem

        // 트랙패드용 안내(클릭 불가 정보 항목). 제목은 menuWillOpen에서 현재 단축키로 갱신.
        let hotkeyHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)
        hotkeyHintItem = hotkeyHint

        addItem(to: menu, title: String(localized: "Settings…"), action: #selector(openPreferences), key: ",")
        addItem(to: menu, title: String(localized: "Getting Started…"), action: #selector(openOnboarding))

        #if !MAS
        // Sparkle 업데이트 확인. MAS 판은 App Store가 업데이트를 맡는다.
        let updateItem = NSMenuItem(title: String(localized: "Check for Updates…"),
                                    action: #selector(UpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = UpdaterController.shared
        menu.addItem(updateItem)
        self.updateItem = updateItem
        #endif

        // 권한 미허용 시에만 보이는 안내 항목.
        let perm = addItem(to: menu, title: String(localized: "Request Accessibility Permission…"), action: #selector(openAccessibility))
        permissionItem = perm

        menu.addItem(.separator())
        addItem(to: menu, title: String(localized: "Quit \(Brand.name)"), action: #selector(quit), key: "q")
        statusItem.menu = menu
    }

    /// 키보드 스냅 동작 목록. 단축키는 표시용(실제 처리는 이벤트 탭).
    private func makeSnapMenu() -> NSMenu {
        let m = NSMenu()
        let groups: [[SnapAction]] = [[.leftHalf, .rightHalf, .topHalf, .bottomHalf],
                                      [.maximize, .center],
                                      [.topLeft, .topRight, .bottomLeft, .bottomRight]]
        for (gi, group) in groups.enumerated() {
            if gi > 0 { m.addItem(.separator()) }
            for action in group {
                let it = NSMenuItem(title: action.title, action: #selector(performSnap(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = action.rawValue
                if Settings.shared.keyboardSnapEnabled, let ke = Settings.shared.snapHotkey(for: action).menuKeyEquivalent {
                    it.keyEquivalent = ke.key
                    it.keyEquivalentModifierMask = ke.flags
                }
                m.addItem(it)
            }
        }
        return m
    }

    @objc private func performSnap(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = SnapAction(rawValue: raw) else { return }
        // 메뉴가 닫히고 원래 앱이 다시 맨 앞이 된 뒤 실행(메뉴바 앱은 activate 되지 않으므로 보통 즉시 OK).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { KeyboardSnapController.shared.perform(action) }
        }
    }

    /// 프리셋 그룹(기본 + 사용자 지정)을 섹션으로 나눈 서브메뉴.
    private func makeResizeMenu() -> NSMenu {
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
        return resizeMenu
    }

    // 메뉴를 열 때마다 토글 체크/권한 항목 상태를 갱신.
    func menuWillOpen(_ menu: NSMenu) {
        enabledItem?.state = Settings.shared.enabled ? .on : .off
        resizeItem?.submenu = makeResizeMenu()
        snapItem?.submenu = makeSnapMenu()
        let granted = AccessibilityPermission.isGranted
        permissionItem?.isHidden = granted
        // 권한 watcher 타임아웃 이후 뒤늦게 허용된 경우: 메뉴만 열어도 탭을 복구한다(이미 있으면 no-op).
        if granted { _ = MouseEventTap.shared.start() }
        hotkeyHintItem?.title = String(localized: "Trackpad: press \(Settings.shared.gridHotkey.displayString) while dragging")
        #if !MAS
        let updater = UpdaterController.shared
        updateItem?.title = updater.lastFailure == nil ? String(localized: "Check for Updates…") : String(localized: "Retry Update…")
        updateItem?.isEnabled = updater.lastFailure != nil || updater.canCheckForUpdates
        updateItem?.toolTip = updater.lastFailure?.localizedDescription
        #endif
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
        let presets = WindowResizeController.presets
        guard sender.tag < presets.count else { return }
        let preset = presets[sender.tag]
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
