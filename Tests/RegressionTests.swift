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
