import AppKit
import Combine

/// 온보딩 4화면의 상태. 뷰(SwiftUI)와 윈도우 컨트롤러가 공유한다.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Page: Int, CaseIterable {
        case language, permission, practice, finish
    }

    /// 마무리 화면의 그리드 크기 선택지.
    enum GridPreset: Hashable, CaseIterable, Identifiable {
        case twoByTwo, fourByTwo, sixByFour, eightByFour
        var id: Self { self }
        var columns: Int {
            switch self { case .twoByTwo: 2; case .fourByTwo: 4; case .sixByFour: 6; case .eightByFour: 8 }
        }
        var rows: Int {
            switch self { case .twoByTwo: 2; case .fourByTwo: 2; case .sixByFour: 4; case .eightByFour: 4 }
        }
        var label: String { "\(columns) × \(rows)" }
        static func matching(columns: Int, rows: Int) -> GridPreset? {
            allCases.first { $0.columns == columns && $0.rows == rows }
        }
    }

    @Published var page: Page = .language
    /// 표시 언어. 고르는 즉시 앱 전체(이 가이드 포함)가 바뀐다.
    @Published var language: AppLanguage = LanguageManager.shared.language {
        didSet { LanguageManager.shared.set(language) }
    }
    @Published var permissionGranted: Bool = AccessibilityPermission.isGranted
    @Published var snapSucceeded = false
    @Published var launchAtLogin: Bool = LoginItemController.isEnabled
    @Published var launchAtLoginError: String?
    @Published var edgeSnap: Bool = Settings.shared.edgeSnapEnabled
    /// nil 이면 "현재 설정 유지"(프리셋과 일치하지 않는 사용자 지정 크기).
    @Published var gridPreset: GridPreset? =
        GridPreset.matching(columns: Settings.shared.columns, rows: Settings.shared.rows)

    var hotkeyDisplay: String { Settings.shared.gridHotkey.displayString }
    var currentGridLabel: String { "\(Settings.shared.columns) × \(Settings.shared.rows)" }

    /// 윈도우 컨트롤러가 채운다.
    var onFinish: (() -> Void)?
    var onOpenPermission: (() -> Void)?

    var isLastPage: Bool { page == .finish }

    func next() {
        guard let n = Page(rawValue: page.rawValue + 1) else { return }
        page = n
    }

    func back() {
        guard let p = Page(rawValue: page.rawValue - 1) else { return }
        page = p
    }

    /// 마무리 화면 선택값을 실제 설정에 반영한다.
    func applyFinishChoices() -> Bool {
        launchAtLoginError = nil
        Settings.shared.edgeSnapEnabled = edgeSnap
        if let preset = gridPreset {
            Settings.shared.columns = preset.columns
            Settings.shared.rows = preset.rows
        }
        if launchAtLogin != LoginItemController.isEnabled {
            do {
                try LoginItemController.setEnabled(launchAtLogin)
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = LoginItemController.isEnabled
                return false
            }
        }
        NotificationCenter.default.post(name: .gridSettingsChanged, object: nil)
        return true
    }
}
