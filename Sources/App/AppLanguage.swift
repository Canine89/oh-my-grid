import AppKit
import SwiftUI
import Combine
import ObjectiveC

/// 앱 표시 언어. 시스템 언어와 무관하게 **영어가 기본**이고(주 시장이 영어권), 한국어는 설정·온보딩에서 고른다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case korean = "ko"

    var id: String { rawValue }

    /// 언어 선택 UI에 쓰는 원어 표기(로컬라이즈하지 않는다 — 사용자가 자기 언어를 바로 알아봐야 한다).
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .korean:  return "한국어"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

extension Notification.Name {
    /// 표시 언어가 바뀜. 메뉴·창 제목처럼 SwiftUI 밖에서 만든 문자열은 이걸 받아 다시 만든다.
    static let appLanguageChanged = Notification.Name("OMGAppLanguageChanged")
}

/// 표시 언어 전환. `Bundle.main`의 클래스를 바꿔치기해 `localizedString(forKey:)`가 시스템 언어 대신
/// 선택한 언어의 `.lproj`를 보게 한다 — `String(localized:)`와 SwiftUI `Text` 모두 이 경로를 타므로
/// 재시작 없이 바로 바뀐다. 영어는 소스 언어라 별도 `.lproj`가 없고 키 자체가 영어 문장이다.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var language: AppLanguage

    /// nil 이면 영어(소스 언어) — 키를 그대로 돌려준다.
    nonisolated(unsafe) fileprivate static var overrideBundle: Bundle?

    private init() {
        language = Settings.shared.language
    }

    /// 앱 기동 최초(UI를 만들기 전)에 한 번 호출한다.
    static func install() {
        object_setClass(Bundle.main, LocalizedBundle.self)
        overrideBundle = bundle(for: shared.language)
    }

    func set(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        Settings.shared.language = newLanguage
        Self.overrideBundle = Self.bundle(for: newLanguage)
        language = newLanguage
        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard language != .english,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = LanguageManager.overrideBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        // 영어: 시스템 언어(super)를 타면 한국어 시스템에서 한국어가 나오므로 키(영어 원문)를 그대로.
        if let value, !value.isEmpty { return value }
        return key
    }
}

/// SwiftUI 루트를 감싸 언어가 바뀌면 트리를 다시 만든다(`id`)— 이미 그려진 `Text`는 스스로 갱신하지 않는다.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var manager = LanguageManager.shared
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .id(manager.language)
            .environment(\.locale, manager.language.locale)
    }
}
