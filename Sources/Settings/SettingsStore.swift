import AppKit
import Combine

/// 설정 창의 관찰 가능한 상태. `Settings`(UserDefaults)를 읽어 초기화하고, 값이 바뀌면 즉시 써서
/// "적용" 버튼 없이 반영된다. 외부(메뉴 토글 등)에서 바뀐 값은 `reload()`로 다시 읽는다.
@MainActor
final class SettingsStore: ObservableObject {
    // 일반
    @Published var language: AppLanguage { didSet { guard !loading else { return }; LanguageManager.shared.set(language) } }
    /// 현재 탭. 언어 전환으로 뷰 트리가 다시 만들어져도 유지되도록 뷰가 아니라 여기 둔다.
    @Published var tab: SettingsView.Tab = .general
    @Published var enabled: Bool { didSet { guard !loading else { return }; settings.enabled = enabled; notify() } }
    @Published var edgeSnap: Bool { didSet { guard !loading else { return }; settings.edgeSnapEnabled = edgeSnap; notify() } }
    @Published var launchAtLogin: Bool
    @Published var launchAtLoginMessage: String = ""
    @Published var permissionGranted: Bool = AccessibilityPermission.isGranted

    // 그리드
    @Published var columns: Int { didSet { guard !loading else { return }; settings.columns = columns; notify() } }
    @Published var rows: Int { didSet { guard !loading else { return }; settings.rows = rows; notify() } }
    @Published var outerMargin: Double { didSet { guard !loading else { return }; settings.outerMargin = outerMargin; notify() } }
    @Published var innerGap: Double { didSet { guard !loading else { return }; settings.innerGap = innerGap; notify() } }

    // 단축키
    @Published var hotkey: Hotkey { didSet { guard !loading else { return }; settings.gridHotkey = hotkey; hotkeyError = ""; notify() } }
    @Published var hotkeyError: String = ""
    @Published var keyboardSnapEnabled: Bool { didSet { guard !loading else { return }; settings.keyboardSnapEnabled = keyboardSnapEnabled } }
    @Published var snapHotkeys: [SnapAction: Hotkey] { didSet { guard !loading else { return }; settings.snapHotkeys = snapHotkeys } }
    @Published var snapHotkeyError: String = ""

    // 창 크기 프리셋
    @Published var customPresets: [CustomPreset] { didSet { guard !loading, customPresets.allSatisfy(\.isValid) else { return }; settings.customPresets = customPresets } }

    // 예외 앱
    @Published var excludedApps: [String] { didSet { guard !loading else { return }; settings.excludedApps = excludedApps } }

    /// 호스트(윈도우 컨트롤러)가 연결하는 동작. 뷰가 Sparkle·AX 계층을 직접 알지 않게 한다.
    var checkForUpdates: (() -> Void)?
    var captureWindowSize: ((@escaping (CGSize) -> Void) -> Void)?
    var openOnboarding: (() -> Void)?

    private let settings: Settings
    private var loading = false

    init(settings: Settings = .shared) {
        self.settings = settings
        let s = settings
        language = s.language
        enabled = s.enabled
        edgeSnap = s.edgeSnapEnabled
        launchAtLogin = LoginItemController.isEnabled
        columns = s.columns
        rows = s.rows
        outerMargin = Double(s.outerMargin)
        innerGap = Double(s.innerGap)
        hotkey = s.gridHotkey
        keyboardSnapEnabled = s.keyboardSnapEnabled
        snapHotkeys = s.snapHotkeys
        customPresets = s.customPresets
        excludedApps = s.excludedApps
        launchAtLoginMessage = LoginItemController.statusMessage
    }

    /// 외부 변경(메뉴 토글, 온보딩, 권한 허용)을 다시 읽는다. didSet 쓰기는 건너뛴다.
    func reload() {
        loading = true
        defer { loading = false }
        let s = settings
        language = s.language
        enabled = s.enabled
        edgeSnap = s.edgeSnapEnabled
        columns = s.columns
        rows = s.rows
        outerMargin = Double(s.outerMargin)
        innerGap = Double(s.innerGap)
        hotkey = s.gridHotkey
        keyboardSnapEnabled = s.keyboardSnapEnabled
        snapHotkeys = s.snapHotkeys
        customPresets = s.customPresets
        excludedApps = s.excludedApps
        launchAtLogin = LoginItemController.isEnabled
        launchAtLoginMessage = LoginItemController.statusMessage
        permissionGranted = AccessibilityPermission.isGranted
    }

    // MARK: 동작

    func setLaunchAtLogin(_ on: Bool) {
        var failed = false
        do {
            try LoginItemController.setEnabled(on)
        } catch {
            failed = true
            launchAtLoginMessage = String(localized: "⚠️ Couldn’t change login item: \(error.localizedDescription)")
            LoginItemController.openLoginItemsSettings()
        }
        launchAtLogin = LoginItemController.isEnabled
        if !failed { launchAtLoginMessage = LoginItemController.statusMessage }
    }

    func setGridHotkey(_ hk: Hotkey) {
        if let error = hk.validationError { hotkeyError = error; return }
        if let other = SnapAction.allCases.first(where: { snapHotkey(for: $0) == hk }) {
            hotkeyError = String(localized: "Already used by “\(other.title)”.")
            return
        }
        hotkey = hk
    }

    func resetHotkey() { setGridHotkey(.default) }

    func snapHotkey(for action: SnapAction) -> Hotkey {
        snapHotkeys[action] ?? action.defaultHotkey
    }

    /// 스냅 단축키 변경. 다른 동작·그리드 단축키와 겹치면 거부하고 오류를 표시한다.
    func setSnapHotkey(_ hk: Hotkey, for action: SnapAction) {
        if let error = hk.validationError { snapHotkeyError = error; return }
        if hk == hotkey {
            snapHotkeyError = String(localized: "Already used by the grid shortcut.")
            return
        }
        if let other = SnapAction.allCases.first(where: { $0 != action && snapHotkey(for: $0) == hk }) {
            snapHotkeyError = String(localized: "Already used by “\(other.title)”.")
            return
        }
        snapHotkeyError = ""
        if hk == action.defaultHotkey { snapHotkeys.removeValue(forKey: action) } else { snapHotkeys[action] = hk }
    }

    func resetSnapHotkeys() {
        if SnapAction.allCases.contains(where: { $0.defaultHotkey == hotkey }) {
            snapHotkeyError = String(localized: "Already used by the grid shortcut.")
            return
        }
        snapHotkeys = [:]
        snapHotkeyError = ""
    }

    func addPreset(width: Int = 1280, height: Int = 800, name: String = "") {
        customPresets.append(CustomPreset(name: name, width: width, height: height))
    }

    func removePresets(ids: Set<UUID>) {
        customPresets.removeAll { ids.contains($0.id) }
    }

    /// 창 클릭으로 크기를 가져와 프리셋에 추가한다(호스트가 `captureWindowSize`를 연결해야 동작).
    func capturePresetFromWindow() {
        captureWindowSize? { [weak self] size in
            MainActor.assumeIsolated {
                self?.addPreset(width: Int(size.width), height: Int(size.height))
            }
        }
    }

    func addExcludedApps(urls: [URL]) {
        for url in urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty, !excludedApps.contains(id) {
                excludedApps.append(id)
            }
        }
    }

    func addExcludedApp(bundleID: String) {
        guard !bundleID.isEmpty, !excludedApps.contains(bundleID) else { return }
        excludedApps.append(bundleID)
    }

    func removeExcludedApps(_ ids: Set<String>) {
        excludedApps.removeAll { ids.contains($0) }
    }

    private func notify() {
        NotificationCenter.default.post(name: .gridSettingsChanged, object: nil)
    }

    // MARK: 표시 도우미

    static func appName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return url.deletingPathExtension().lastPathComponent
    }

    static func appIcon(forBundleID id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    /// 예외 앱 후보: 현재 실행 중인 일반 앱(자기 자신 제외), 이름순.
    static func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
