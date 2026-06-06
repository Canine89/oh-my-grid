import Foundation

/// UserDefaults 기반 환경설정.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private init() {}

    private enum Keys {
        static let columns = "gridColumns"
        static let rows = "gridRows"
        static let enabled = "gridEnabled"
        static let edgeSnap = "edgeSnapEnabled"
        static let outerMargin = "outerMargin"
        static let innerGap = "innerGap"
        static let excludedApps = "excludedApps"
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
        get { CGFloat(defaults.double(forKey: Keys.outerMargin)) }
        set { defaults.set(Double(newValue), forKey: Keys.outerMargin) }
    }

    /// 셀 블록 안쪽 여백(px). 창과 셀 경계 사이 간격. 기본 0.
    var innerGap: CGFloat {
        get { CGFloat(defaults.double(forKey: Keys.innerGap)) }
        set { defaults.set(Double(newValue), forKey: Keys.innerGap) }
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
}

extension Notification.Name {
    /// 그리드 설정(열/행/활성)이 바뀌었을 때.
    static let gridSettingsChanged = Notification.Name("com.goldenrabbit.ohmygrid.settingsChanged")
}
