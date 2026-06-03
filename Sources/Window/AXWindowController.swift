import AppKit
import ApplicationServices

/// AXUIElement 기반 창 조회/조작.
/// 좌표·크기는 모두 **CG 전역(top-left, points)** 공간을 쓴다 → `ScreenGeometry` 셀 사각형과 동일.
@MainActor
final class AXWindowController {
    static let shared = AXWindowController()
    private let systemWide = AXUIElementCreateSystemWide()
    private init() {}

    /// CG 전역(top-left) 좌표 아래에 있는 창 엘리먼트.
    /// 위치의 자식 엘리먼트(타이틀바 등)를 받은 뒤 상위 윈도우로 올라간다. 실패 시 프런트모스트 포커스 창 폴백.
    func windowUnderCursor(cgPoint point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        if err == .success, let el = element, let win = enclosingWindow(of: el) {
            return win
        }
        return frontmostFocusedWindow()
    }

    /// 창의 현재 frame (CG 전역 top-left).
    func frame(of window: AXUIElement) -> CGRect? {
        guard let pos = axValue(window, kAXPositionAttribute, type: .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, type: .cgSize, as: CGSize.self) else {
            return nil
        }
        return CGRect(origin: pos, size: size)
    }

    /// 창을 주어진 frame(CG 전역 top-left)으로 이동·리사이즈.
    /// position→size→position 순서로 두 번 위치를 적용해, 크기 변경 중 화면 가장자리 클램프로
    /// 위치가 밀리는 현상을 보정한다.
    @discardableResult
    func setFrame(_ rect: CGRect, for window: AXUIElement) -> Bool {
        let okPos1 = setPosition(rect.origin, for: window)
        let okSize = setSize(rect.size, for: window)
        let okPos2 = setPosition(rect.origin, for: window)
        return okPos1 && okSize && okPos2
    }

    // MARK: - 내부 구현

    private func setPosition(_ point: CGPoint, for window: AXUIElement) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    /// 임의 엘리먼트 → 그것을 포함하는 윈도우 엘리먼트.
    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        // 1) kAXWindowAttribute 가 곧장 윈도우를 주는 경우.
        if let win = copyElement(element, kAXWindowAttribute), role(win) == (kAXWindowRole as String) {
            return win
        }
        // 2) 부모로 거슬러 올라가며 role 이 윈도우인 것을 찾는다.
        var current: AXUIElement? = element
        var hops = 0
        while let el = current, hops < 12 {
            if role(el) == (kAXWindowRole as String) { return el }
            current = copyElement(el, kAXParentAttribute)
            hops += 1
        }
        return nil
    }

    /// 프런트모스트 앱의 포커스 창 (폴백).
    private func frontmostFocusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return copyElement(appElement, kAXFocusedWindowAttribute)
    }

    private func role(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value else { return nil }
        // AXUIElement 타입인지 확인 후 캐스팅.
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func axValue<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType, as: T.Type) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }
}
