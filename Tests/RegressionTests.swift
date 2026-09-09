import AppKit
import ApplicationServices

@main
struct RegressionTests {
    @MainActor static func main() async {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError("Regression: \(message)") }
        }
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        expect(AccessibilityPermission.resolvedPaneURL(handler: nil, application: settingsApp) == nil,
               "unknown URL handler falls back to the application")
        expect(AccessibilityPermission.resolvedPaneURL(handler: URL(fileURLWithPath: "/Applications/Other.app"), application: settingsApp) == nil,
               "a different URL handler cannot receive the settings request")
        expect(AccessibilityPermission.resolvedPaneURL(handler: settingsApp, application: settingsApp) == AccessibilityPermission.settingsPaneURL,
               "registered Settings handler receives the accessibility pane")
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: -1080)] {
            let screen = CGRect(origin: origin, size: bounds.size)
            for columns in 1...24 {
                for rows in 1...24 {
                    for cell in [ScreenGeometry.Cell(col: 0, row: 0), .init(col: columns - 1, row: rows - 1)] {
                        let rect = ScreenGeometry.unionRect(anchor: cell, current: cell, bounds: screen, cols: columns, rows: rows)
                        let target = ScreenGeometry.applyGaps(rect, within: screen, outerMargin: 48, innerGap: 32)
                        expect(ScreenGeometry.isValidWindowRect(target), "finite positive frame at \(columns)x\(rows)")
                        expect(target.minX >= rect.minX && target.maxX <= rect.maxX + 0.001 &&
                               target.minY >= rect.minY && target.maxY <= rect.maxY + 0.001, "gaps stay inside cell")
                        expect(!rs(target).contains("invalid"), "safe frame logging")
                    }
                }
            }
        }
        let left = ScreenGeometry.applyGaps(CGRect(x: 0, y: 0, width: 720, height: 900), within: bounds, outerMargin: 12, innerGap: 10)
        let right = ScreenGeometry.applyGaps(CGRect(x: 720, y: 0, width: 720, height: 900), within: bounds, outerMargin: 12, innerGap: 10)
        expect(right.minX - left.maxX == 10, "requested window gap equals actual gap")
        expect(left.minX == 12 && right.maxX == bounds.maxX - 12, "outer margin applied once")
        for invalid in [CGRect.null, .infinite, .zero, CGRect(x: 0, y: 0, width: -1, height: 100)] {
            expect(!ScreenGeometry.isValidWindowRect(invalid), "invalid frame rejected")
            expect(rs(invalid).contains("invalid"), "invalid logging never traps")
        }
        expect(ScreenGeometry.matches(bounds, target: bounds.offsetBy(dx: 1, dy: 1)), "rounding tolerance")
        expect(!ScreenGeometry.matches(bounds, target: CGRect(x: 0, y: 0, width: 800, height: 600)), "clamped size is not success")
        expect(!ScreenGeometry.matches(.null, target: .null), "invalid frames never match")
        expect(ScreenGeometry.rect(for: .top, usable: bounds) == bounds, "top edge maximizes")

        func windowInfo(pid: Int32, layer: Int, alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: bounds.dictionaryRepresentation]
        }
        expect(AXWindowController.candidateOwnerPID(in: [windowInfo(pid: 1, layer: 1000), windowInfo(pid: 2, layer: 0)],
                                                   at: CGPoint(x: 100, y: 100)) == 2,
               "utility overlays do not shadow normal windows")
        expect(AXWindowController.candidateOwnerPID(in: [windowInfo(pid: 1, layer: 0, alpha: 0), windowInfo(pid: 2, layer: 0)],
                                                   at: CGPoint(x: 100, y: 100)) == 2,
               "transparent windows are ignored")
        expect(AXWindowController.candidateOwnerPID(in: [windowInfo(pid: 2, layer: 0)],
                                                   at: CGPoint(x: -100, y: -100)) == nil,
               "unrelated windows are not selected")

        var attempts = 0
        var timeouts: [Float] = []
        let recovered: Result<Int, WindowFailure> = AXReadPolicy.read(request: WindowRequest(), deadline: 10, now: { 0 }) { timeout in
            attempts += 1; timeouts.append(timeout)
            return attempts == 1 ? (.cannotComplete, nil) : (.success, 42)
        }
        expect((try? recovered.get()) == 42 && attempts == 2, "transient communication failure recovers")
        expect(timeouts == [0.5, 1.0], "retry uses a longer response timeout")
        attempts = 0
        let failed: Result<Int, WindowFailure> = AXReadPolicy.read(request: WindowRequest(), deadline: 10, now: { 0 }) { _ in
            attempts += 1; return (.cannotComplete, nil)
        }
        expect(attempts == 2 && failed == .failure(.unresponsive), "persistent communication failure is bounded")
        attempts = 0
        let denied: Result<Int, WindowFailure> = AXReadPolicy.read(request: WindowRequest(), deadline: 10, now: { 0 }) { _ in
            attempts += 1; return (.apiDisabled, nil)
        }
        expect(attempts == 1 && denied == .failure(.permission), "permission errors are not retried")
        let cancelledRead = WindowRequest(); cancelledRead.cancel()
        attempts = 0
        let cancelledReadResult: Result<Int, WindowFailure> = AXReadPolicy.read(request: cancelledRead, deadline: 10, now: { 0 }) { _ in
            attempts += 1; return (.success, 42)
        }
        expect(attempts == 0 && cancelledReadResult == .failure(.cancelled), "cancelled reads never call AX")
        var clock: TimeInterval = 0
        attempts = 0
        let expired: Result<Int, WindowFailure> = AXReadPolicy.read(request: WindowRequest(), deadline: 0.2, now: { clock }) { timeout in
            expect(timeout <= 0.2, "remaining deadline caps timeout")
            clock = 0.3; attempts += 1; return (.cannotComplete, nil)
        }
        expect(attempts == 1 && expired == .failure(.unresponsive), "expired lookup skips retry")
        attempts = 0
        let missing: Result<Int, WindowFailure> = AXReadPolicy.read(request: WindowRequest(), deadline: 10, now: { 0 }) { _ in
            attempts += 1; return (.noValue, nil)
        }
        expect(attempts == 1 && missing == .failure(.noWindow), "missing attributes are not retried")
        let interruptedRead = WindowRequest()
        let interrupted: Result<Int, WindowFailure> = AXReadPolicy.read(request: interruptedRead, deadline: 10, now: { 0 }) { _ in
            interruptedRead.cancel(); return (.success, 42)
        }
        expect(interrupted == .failure(.cancelled), "late read success cannot revive a cancelled lookup")
        let element = AXUIElementCreateApplication(getpid())
        let candidate = AXWindowController.WindowCandidate(pid: 100, frame: bounds)
        expect(!AXWindowController.matchesCandidate(WindowSnapshot(element: element, frame: bounds, pid: 200), candidate: candidate),
               "fallback never selects another application's window")
        expect(!AXWindowController.matchesCandidate(WindowSnapshot(element: element, frame: bounds.offsetBy(dx: 50, dy: 0), pid: 100), candidate: candidate),
               "fallback never selects an overlapping but different window")
        expect(AXWindowController.matchesCandidate(WindowSnapshot(element: element, frame: bounds, pid: 100), candidate: candidate),
               "fallback identifies the expected window by owner and bounds")

        var buttons = ConsumedMouseButtons()
        buttons.recordDown(.left)
        expect(buttons.shouldConsume(.leftMouseDragged), "resize drag consumed after mode ends")
        expect(buttons.shouldConsume(.leftMouseUp), "resize up consumed after mode ends")
        expect(!buttons.shouldConsume(.leftMouseUp), "next ordinary up passes")
        buttons.recordDown(.right)
        expect(!buttons.shouldConsume(.leftMouseUp), "unrelated button passes")
        expect(buttons.shouldConsume(.rightMouseUp), "right up consumed across app switch")
        expect(!buttons.shouldConsume(.rightMouseUp), "right pair cleared")

        let suite = "com.goldenrabbit.ohmygrid.regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        settings.outerMargin = .infinity
        settings.innerGap = -20
        expect(settings.outerMargin == 0 && settings.innerGap == 0, "non-finite/negative stored gaps sanitized")
        settings.outerMargin = 500
        settings.innerGap = 500
        expect(settings.outerMargin == 48 && settings.innerGap == 32, "stored gaps bounded")
        let valid = CustomPreset(name: "Good", width: 640, height: 480)
        let bad = CustomPreset(name: "Bad", width: -1, height: Int.max)
        settings.customPresets = [valid, bad]
        expect(settings.customPresets == [valid], "invalid sizes not persisted")
        defaults.set(try! JSONEncoder().encode([bad, valid]), forKey: "customResizePresets")
        expect(settings.customPresets == [valid], "old invalid presets are filtered")
        expect(!CustomPreset(name: "Zero", width: 0, height: 900).isValid, "zero size rejected")
        expect(CustomPreset(name: "Max", width: 16384, height: 16384).isValid, "documented max accepted")
        let store = SettingsStore(settings: settings)
        let originalGrid = store.hotkey
        store.setGridHotkey(SnapAction.allCases[0].defaultHotkey)
        expect(store.hotkey == originalGrid && !store.hotkeyError.isEmpty, "grid-to-snap conflict rejected")
        store.setSnapHotkey(originalGrid, for: SnapAction.allCases[0])
        expect(!store.snapHotkeyError.isEmpty, "snap-to-grid conflict rejected")
        store.customPresets = [bad]
        expect(settings.customPresets == [valid], "invalid edit preserves last saved settings")
        store.customPresets = [CustomPreset(name: "Fixed", width: 800, height: 600)]
        expect(settings.customPresets == store.customPresets, "valid corrected draft is saved")

        // Invalid geometry must be rejected before any permission/AX operation.
        let result = await withCheckedContinuation { continuation in
            AXWindowController.shared.setFrame(.null, for: AXUIElementCreateApplication(getpid())) {
                continuation.resume(returning: $0)
            }
        }
        if case .failure(.invalidGeometry) = result { checks += 1 }
        else { fatalError("Invalid frame reached AX") }
        let cancelled = WindowRequest()
        cancelled.cancel()
        let cancelledResult = await withCheckedContinuation { continuation in
            AXWindowController.shared.setFrame(bounds, for: AXUIElementCreateApplication(getpid()), request: cancelled) {
                continuation.resume(returning: $0)
            }
        }
        if case .failure(.cancelled) = cancelledResult { checks += 1 }
        else { fatalError("Cancelled work reached AX") }
        print("PASS: \(checks) regression checks (Release optimization)")
    }
}
