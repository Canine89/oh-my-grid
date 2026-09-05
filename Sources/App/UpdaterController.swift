import AppKit
import Sparkle

/// Sparkle 자동 업데이트 래퍼.
/// - 앱 시작 시 백그라운드로 새 버전을 확인하고(Info.plist의 SUEnableAutomaticChecks/Interval),
/// - 메뉴의 "업데이트 확인…"으로 즉시 확인할 수 있게 한다.
/// 비공증(자체서명) 앱이라도 Sparkle이 EdDSA 서명으로 무결성을 검증하고,
/// 업데이트 설치 시 quarantine 을 제거하므로 첫 설치 이후엔 경고 없이 갱신된다.
@MainActor
final class UpdaterController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterController()

    private var controller: SPUStandardUpdaterController!
    private(set) var lastFailure: Error?

    private override init() {
        super.init()
        controller = makeController()
    }

    private func makeController() -> SPUStandardUpdaterController {
        SPUStandardUpdaterController(startingUpdater: true,
                                     updaterDelegate: self,
                                     userDriverDelegate: nil)
    }

    /// 메뉴 "업데이트 확인…" 액션에 연결.
    @objc func checkForUpdates(_ sender: Any?) {
        // 설치/다운로드 오류가 난 세션 객체를 그대로 재사용하지 않고 새 컨트롤러로
        // 교체한다. Sparkle 외부 프로세스가 중단된 경우에도 다음 수동 확인이 이전
        // 인메모리 상태에 묶이지 않고 처음부터 시작된다.
        if lastFailure != nil {
            controller = makeController()
            lastFailure = nil

            // 새 업데이터의 start가 끝난 다음 사용자 요청을 전달한다.
            DispatchQueue.main.async { [weak self] in
                self?.controller.checkForUpdates(sender)
            }
        } else {
            controller.checkForUpdates(sender)
        }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Sparkle의 표준 오류창이 닫힌 뒤 실패 상태를 보존한다. 다음 메뉴 실행은 위의
    /// 새 컨트롤러 경로를 사용하므로 앱을 재설치하지 않고 다시 시도할 수 있다.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        lastFailure = error
    }
}
