import AppKit
@preconcurrency import ApplicationServices

/// Cancellation is read on the AX queue and written on the main thread.
final class WindowRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

struct WindowSnapshot {
    let element: AXUIElement
    let frame: CGRect
    let pid: pid_t
}

enum WindowFailure: Error {
    case permission, noWindow, invalidGeometry, unsupported, unresponsive, constrained, unavailable, cancelled

    var message: String {
        switch self {
        case .cancelled: return String(localized: "Window action cancelled.")
        case .permission: return String(localized: "Allow Accessibility access in System Settings, then try again.")
        case .noWindow: return String(localized: "No movable window was found. Choose a normal app window and try again.")
        case .invalidGeometry: return String(localized: "This size or grid selection is invalid. Check the size and gaps.")
        case .unsupported: return String(localized: "This window does not support moving or resizing.")
        case .unresponsive: return String(localized: "Couldn’t communicate with this app. It may be busy or window access may be restricted.")
        case .constrained: return String(localized: "The app limited the window’s size or position. The requested layout could not be applied.")
        case .unavailable: return String(localized: "Window access failed. Check Accessibility access and try a different window.")
        }
    }
}

/// All cross-process AX calls run on one worker queue, never on the event-tap/UI run loop.
/// A short per-message timeout prevents an unresponsive target from blocking later requests indefinitely.
final class AXWindowController: @unchecked Sendable {
    static let shared = AXWindowController()
    private let queue = DispatchQueue(label: "com.goldenrabbit.ohmygrid.ax", qos: .userInitiated)
    private let timeout: Float = 0.15
    private init() {}

    @MainActor
    func queryWindow(at point: CGPoint? = nil, request: WindowRequest = WindowRequest(), completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            let result: Result<WindowSnapshot, WindowFailure>
            if request.isCancelled {
                result = .failure(.cancelled)
            } else if !AXIsProcessTrusted() {
                result = .failure(.permission)
            } else if let point {
                result = self.window(at: point)
            } else if let pid {
                let app = AXUIElementCreateApplication(pid)
                self.prepare(app)
                if let window = self.copyElement(app, kAXFocusedWindowAttribute) {
                    result = self.snapshot(window)
                } else { result = .failure(.noWindow) }
            } else { result = .failure(.noWindow) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    @MainActor
    func inspect(_ window: AXUIElement, completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        queue.async {
            let result = self.snapshot(window)
            DispatchQueue.main.async { completion(result) }
        }
    }

    @MainActor
    func setFrame(_ rect: CGRect, for window: AXUIElement, request: WindowRequest = WindowRequest(),
                  completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        queue.async {
            let result = request.isCancelled ? .failure(WindowFailure.cancelled) : self.apply(rect, to: window, request: request)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func apply(_ rect: CGRect, to window: AXUIElement, request: WindowRequest) -> Result<WindowSnapshot, WindowFailure> {
        guard ScreenGeometry.isValidWindowRect(rect) else { return .failure(.invalidGeometry) }
        guard AXIsProcessTrusted() else { return .failure(.permission) }
        prepare(window)
        let initial = snapshot(window)
        guard case .success(let before) = initial else { return initial }
        if ScreenGeometry.matches(before.frame, target: rect) { return .success(before) }
        var movable: DarwinBoolean = false
        var resizable: DarwinBoolean = false
        let positionError = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable)
        let sizeError = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
        guard positionError == .success else { return .failure(failure(positionError)) }
        guard sizeError == .success else { return .failure(failure(sizeError)) }
        let needsMove = abs(before.frame.minX - rect.minX) > 2 || abs(before.frame.minY - rect.minY) > 2
        let needsResize = abs(before.frame.width - rect.width) > 2 || abs(before.frame.height - rect.height) > 2
        guard (!needsMove || movable.boolValue), (!needsResize || resizable.boolValue) else { return .failure(.unsupported) }
        guard !request.isCancelled else { return .failure(.cancelled) }
        var point = rect.origin
        var size = rect.size
        if movable.boolValue, let value = AXValueCreate(.cgPoint, &point) {
            let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            guard error == .success else { return .failure(failure(error)) }
        }
        if needsResize, let value = AXValueCreate(.cgSize, &size) {
            let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            guard error == .success else { return .failure(failure(error)) }
        }
        if movable.boolValue, let value = AXValueCreate(.cgPoint, &point) {
            let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            guard error == .success else { return .failure(failure(error)) }
        }
        // An AX success code alone is insufficient: applications may clamp the frame.
        switch snapshot(window) {
        case .success(let after):
            return ScreenGeometry.matches(after.frame, target: rect) ? .success(after) : .failure(.constrained)
        case .failure(let error): return .failure(error)
        }
    }

    private func window(at point: CGPoint) -> Result<WindowSnapshot, WindowFailure> {
        guard point.x.isFinite, point.y.isFinite else { return .failure(.invalidGeometry) }
        // Public WindowServer metadata identifies the app beneath our noninteractive overlays.
        // Only PID, bounds, layer and visibility are inspected; no images are captured.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = windows.first(where: { info in
                  guard let pid = info[kCGWindowOwnerPID as String] as? Int,
                        let raw = info[kCGWindowBounds as String] as? [String: Any],
                        let frame = CGRect(dictionaryRepresentation: raw as CFDictionary),
                        frame.contains(point) else { return false }
                  let layer = info[kCGWindowLayer as String] as? Int ?? 0
                  let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
                  return alpha > 0 && !(pid == Int(getpid()) && layer != 0)
              }), let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return .failure(.noWindow) }
        let app = AXUIElementCreateApplication(pid)
        prepare(app)
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element)
        guard error == .success else { return .failure(failure(error)) }
        guard let element, let window = enclosingWindow(of: element) else { return .failure(.noWindow) }
        return snapshot(window)
    }

    private func prepare(_ element: AXUIElement) { AXUIElementSetMessagingTimeout(element, timeout) }

    private func failure(_ error: AXError) -> WindowFailure {
        switch error {
        case .apiDisabled: return .permission
        case .cannotComplete: return .unresponsive
        case .attributeUnsupported, .actionUnsupported, .notImplemented: return .unsupported
        case .invalidUIElement, .noValue: return .noWindow
        default: return .unavailable
        }
    }

    private func snapshot(_ window: AXUIElement) -> Result<WindowSnapshot, WindowFailure> {
        prepare(window)
        var position: CFTypeRef?
        var size: CFTypeRef?
        let pError = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        guard pError == .success else { return .failure(failure(pError)) }
        let sError = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
        guard sError == .success else { return .failure(failure(sError)) }
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return .failure(.unsupported) }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s) else { return .failure(.unsupported) }
        let frame = CGRect(origin: p, size: s)
        guard ScreenGeometry.isValidWindowRect(frame) else { return .failure(.invalidGeometry) }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return .failure(.noWindow) }
        return .success(WindowSnapshot(element: window, frame: frame, pid: pid))
    }

    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        prepare(element)
        if let win = copyElement(element, kAXWindowAttribute), role(win) == kAXWindowRole as String { return win }
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let el = current else { break }
            if role(el) == kAXWindowRole as String { return el }
            current = copyElement(el, kAXParentAttribute)
        }
        return nil
    }

    private func role(_ element: AXUIElement) -> String? {
        prepare(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        prepare(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let result = raw as! AXUIElement
        prepare(result)
        return result
    }
}
