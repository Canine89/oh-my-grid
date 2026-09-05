import Foundation

/// UserDefaults 기반 환경설정.
final class Settings {
    static let shared = Settings()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Keys {
        static let columns = "gridColumns"
        static let rows = "gridRows"
        static let enabled = "gridEnabled"
        static let edgeSnap = "edgeSnapEnabled"
        static let outerMargin = "outerMargin"
        static let innerGap = "innerGap"
        static let excludedApps = "excludedApps"
        static let hotkeyKeyCode = "gridHotkeyKeyCode"
        static let hotkeyMods = "gridHotkeyMods"
        static let onboardingCompleted = "onboardingCompleted"
        static let customPresets = "customResizePresets"
        static let keyboardSnapEnabled = "keyboardSnapEnabled"
        static let snapHotkeys = "snapHotkeys"
        static let language = "appLanguage"
    }

    /// 표시 언어. 기본 영어(시스템 언어와 무관).
    var language: AppLanguage {
        get { defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Keys.language) }
    }

    /// 키보드 스냅 단축키 활성 여부. 기본 true.
    var keyboardSnapEnabled: Bool {
        get { defaults.object(forKey: Keys.keyboardSnapEnabled) == nil ? true : defaults.bool(forKey: Keys.keyboardSnapEnabled) }
        set { defaults.set(newValue, forKey: Keys.keyboardSnapEnabled) }
    }

    /// 동작별 사용자 지정 단축키. 없는 동작은 `SnapAction.defaultHotkey`.
    var snapHotkeys: [SnapAction: Hotkey] {
        get {
            guard let data = defaults.data(forKey: Keys.snapHotkeys),
                  let raw = try? JSONDecoder().decode([String: Hotkey].self, from: data) else { return [:] }
            var out: [SnapAction: Hotkey] = [:]
            for (k, v) in raw { if let a = SnapAction(rawValue: k) { out[a] = v } }
            return out
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(raw) { defaults.set(data, forKey: Keys.snapHotkeys) }
        }
    }

    func snapHotkey(for action: SnapAction) -> Hotkey {
        snapHotkeys[action] ?? action.defaultHotkey
    }

    /// 사용자 지정 창 크기 프리셋(창 크기 고정 메뉴의 "사용자 지정" 섹션). JSON 으로 저장.
    var customPresets: [CustomPreset] {
        get {
            guard let data = defaults.data(forKey: Keys.customPresets),
                  let list = try? JSONDecoder().decode([CustomPreset].self, from: data) else { return [] }
            return list.filter(\.isValid)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.filter(\.isValid)) { defaults.set(data, forKey: Keys.customPresets) }
        }
    }

    /// 첫 실행 온보딩을 끝냈거나 닫았는지. 기본 false.
    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Keys.onboardingCompleted) }
        set { defaults.set(newValue, forKey: Keys.onboardingCompleted) }
    }

    /// 그리드 열 수. 기본 6.
    var columns: Int {
        get {
            let v = defaults.object(forKey: Keys.columns) as? Int ?? 6
            return max(1, min(24, v))
        }
        set { defaults.set(max(1, min(24, newValue)), forKey: Keys.columns) }
    }

    /// 그리드 행 수. 기본 4.
    var rows: Int {
        get {
            let v = defaults.object(forKey: Keys.rows) as? Int ?? 4
            return max(1, min(24, v))
        }
        set { defaults.set(max(1, min(24, newValue)), forKey: Keys.rows) }
    }

    /// 제스처 활성 여부. 기본 true.
    var enabled: Bool {
        get { defaults.object(forKey: Keys.enabled) == nil ? true : defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// 가장자리 절반 스냅(일반 드래그로 화면 끝에 대면 절반/최대화) 활성 여부. 기본 true.
    var edgeSnapEnabled: Bool {
        get { defaults.object(forKey: Keys.edgeSnap) == nil ? true : defaults.bool(forKey: Keys.edgeSnap) }
        set { defaults.set(newValue, forKey: Keys.edgeSnap) }
    }

    /// 화면 가장자리 바깥 여백(px). 스냅된 창과 화면 가장자리 사이 간격. 기본 0.
    var outerMargin: CGFloat {
        get { ScreenGeometry.bounded(CGFloat(defaults.double(forKey: Keys.outerMargin)), maximum: 48) }
        set { defaults.set(Double(ScreenGeometry.bounded(newValue, maximum: 48)), forKey: Keys.outerMargin) }
    }

    /// 셀 블록 안쪽 여백(px). 창과 셀 경계 사이 간격. 기본 0.
    var innerGap: CGFloat {
        get { ScreenGeometry.bounded(CGFloat(defaults.double(forKey: Keys.innerGap)), maximum: 32) }
        set { defaults.set(Double(ScreenGeometry.bounded(newValue, maximum: 32)), forKey: Keys.innerGap) }
    }

    /// 제스처를 끌 앱들의 bundle ID 목록. 이 앱들이 맨 앞이면 이벤트 탭이 입력에 개입하지 않는다.
    /// (드래그를 강제하는 게임 등에서 우클릭·드래그가 가로채이는 문제를 피하기 위함.)
    var excludedApps: [String] {
        get { defaults.stringArray(forKey: Keys.excludedApps) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedApps) }
    }

    /// 해당 bundle ID가 예외 목록에 있는지.
    func isExcluded(bundleID: String) -> Bool {
        excludedApps.contains(bundleID)
    }

    /// 예외 목록에 추가(빈 값·중복은 무시).
    func addExcludedApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !excludedApps.contains(bundleID) else { return }
        excludedApps.append(bundleID)
    }

    /// 예외 목록에서 제거.
    func removeExcludedApp(_ bundleID: String) {
        excludedApps.removeAll { $0 == bundleID }
    }

    /// 그리드 발동 단축키(창 드래그 중 입력). 기본 ⌃⌥G.
    var gridHotkey: Hotkey {
        get {
            guard let code = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int,
                  let mods = defaults.object(forKey: Keys.hotkeyMods) as? Int else {
                return .default
            }
            return Hotkey(keyCode: code, mods: HotkeyModifiers(rawValue: mods))
        }
        set {
            defaults.set(newValue.keyCode, forKey: Keys.hotkeyKeyCode)
            defaults.set(newValue.mods.rawValue, forKey: Keys.hotkeyMods)
        }
    }
}

extension Notification.Name {
    /// 그리드 설정(열/행/활성)이 바뀌었을 때.
    static let gridSettingsChanged = Notification.Name("com.goldenrabbit.ohmygrid.settingsChanged")
}

/// 사용자 지정 창 크기 프리셋.
struct CustomPreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var width: Int
    var height: Int

    static let dimensionRange = 1...16384
    var isValid: Bool { Self.dimensionRange.contains(width) && Self.dimensionRange.contains(height) }

    /// 메뉴 표시용 라벨. 이름이 비어 있으면 크기만.
    var label: String {
        let size = "\(width) × \(height)"
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty || n == size ? size : "\(n) · \(size)"
    }
}
