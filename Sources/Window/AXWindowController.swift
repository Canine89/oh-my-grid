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

enum WindowFailure: Error, Equatable {
    case permission, noWindow, invalidGeometry, unsupported, unresponsive, constrained, unavailable, cancelled

    static func fromAX(_ error: AXError) -> Self {
        switch error {
        case .apiDisabled: return .permission
        case .cannotComplete: return .unresponsive
        case .attributeUnsupported, .actionUnsupported, .notImplemented: return .unsupported
        case .invalidUIElement, .noValue: return .noWindow
        default: return .unavailable
        }
    }

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
    private let timeout: Float = 0.5
    // Accessed only on `queue`; all reads in one lookup share a deadline and cancellation token.
    private var readRequest = WindowRequest()
    private var readDeadline: TimeInterval?
    private init() {}

    @MainActor
    func queryWindow(at point: CGPoint? = nil, applicationPID: pid_t? = nil, request: WindowRequest = WindowRequest(), completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        let pid = applicationPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            self.readRequest = request
            self.readDeadline = ProcessInfo.processInfo.systemUptime + 2.5
            defer { self.readDeadline = nil }
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
                switch self.readAttribute(app, kAXFocusedWindowAttribute) {
                case .success(let raw) where CFGetTypeID(raw) == AXUIElementGetTypeID():
                    result = self.snapshot(raw as! AXUIElement)
                case .success: result = .failure(.noWindow)
                case .failure(let error): result = .failure(error)
                }
            } else { result = .failure(.noWindow) }
            if case .failure(let error) = result { glog("Window lookup failed: \(error)") }
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
            switch result {
            case .failure(let error): DispatchQueue.main.async { completion(.failure(error)) }
            case .success: self.finishPlacement(rect, window: window, request: request, completion: completion)
            }
        }
    }

    private func apply(_ rect: CGRect, to window: AXUIElement, request: WindowRequest) -> Result<Void, WindowFailure> {
        guard ScreenGeometry.isValidWindowRect(rect) else { return .failure(.invalidGeometry) }
        guard AXIsProcessTrusted() else { return .failure(.permission) }
        prepare(window)
        let initial = snapshot(window)
        let before: WindowSnapshot
        switch initial {
        case .success(let snapshot): before = snapshot
        case .failure(let error): return .failure(error)
        }
        if ScreenGeometry.matches(before.frame, target: rect) { return .success(()) }
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
        if movable.boolValue, let value = AXValueCreate(.cgPoint, &point) {
            let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            guard error == .success else { return .failure(failure(error)) }
        }
        return .success(())
    }

    /// Separate position, size, and final position into different target-app run-loop turns.
    /// Sending all three immediately can cause the last position write to restore a stale size.
    private func finishPlacement(_ target: CGRect, window: AXUIElement, request: WindowRequest,
                                 completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        queue.asyncAfter(deadline: .now() + 0.05) {
            guard !request.isCancelled else {
                DispatchQueue.main.async { completion(.failure(.cancelled)) }
                return
            }
            let current: WindowSnapshot
            switch self.snapshot(window) {
            case .success(let snapshot): current = snapshot
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if abs(current.frame.width - target.width) > 2 || abs(current.frame.height - target.height) > 2 {
                var size = target.size
                let value = AXValueCreate(.cgSize, &size)!
                let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
                guard error == .success else {
                    let failure = self.failure(error)
                    DispatchQueue.main.async { completion(.failure(failure)) }
                    return
                }
            }
            self.queue.asyncAfter(deadline: .now() + 0.05) {
                guard !request.isCancelled else {
                    DispatchQueue.main.async { completion(.failure(.cancelled)) }
                    return
                }
                if case .success(let current) = self.snapshot(window),
                   abs(current.frame.minX - target.minX) > 2 || abs(current.frame.minY - target.minY) > 2 {
                    var point = target.origin
                    let value = AXValueCreate(.cgPoint, &point)!
                    let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                    guard error == .success else {
                        let failure = self.failure(error)
                        DispatchQueue.main.async { completion(.failure(failure)) }
                        return
                    }
                }
                self.verifyPlacement(target, window: window, request: request, attempt: 0, completion: completion)
            }
        }
    }

    /// AppKit can acknowledge an AX write before committing the frame. Poll on the worker
    /// queue until it settles; never block the input callback or announce premature failure.
    private func verifyPlacement(_ target: CGRect, window: AXUIElement, request: WindowRequest, attempt: Int,
                                 completion: @escaping @MainActor (Result<WindowSnapshot, WindowFailure>) -> Void) {
        queue.asyncAfter(deadline: .now() + 0.08) {
            guard !request.isCancelled else {
                DispatchQueue.main.async { completion(.failure(.cancelled)) }
                return
            }
            switch self.snapshot(window) {
            case .success(let actual):
                if ScreenGeometry.matches(actual.frame, target: target) {
                    glog("Placement verified: \(rs(actual.frame))")
                    DispatchQueue.main.async { completion(.success(actual)) }
                } else if attempt < 5 {
                    if (attempt == 2 || attempt == 4),
                       abs(actual.frame.width - target.width) <= 2,
                       abs(actual.frame.height - target.height) <= 2 {
                        // Some apps finish resizing after acknowledging the final position.
                        // Reapply only the position once the requested size has settled.
                        var point = target.origin
                        let value = AXValueCreate(.cgPoint, &point)!
                        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                        if error != .success { glog("Position correction failed: \(error.rawValue)") }
                    }
                    self.verifyPlacement(target, window: window, request: request, attempt: attempt + 1, completion: completion)
                } else {
                    glog("Placement constrained: target=\(rs(target)), actual=\(rs(actual.frame))")
                    DispatchQueue.main.async { completion(.failure(.constrained)) }
                }
            case .failure(let error): DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    struct WindowCandidate {
        let pid: pid_t
        let frame: CGRect
    }

    static func candidateWindow(in windows: [[String: Any]], at point: CGPoint) -> WindowCandidate? {
        for info in windows {
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  frame.contains(point) else { continue }
            return WindowCandidate(pid: owner.int32Value, frame: frame)
        }
        return nil
    }

    static func candidateOwnerPID(in windows: [[String: Any]], at point: CGPoint) -> pid_t? {
        candidateWindow(in: windows, at: point)?.pid
    }

    static func matchesCandidate(_ window: WindowSnapshot, candidate: WindowCandidate) -> Bool {
        window.pid == candidate.pid && ScreenGeometry.matches(window.frame, target: candidate.frame)
    }

    private func window(at point: CGPoint) -> Result<WindowSnapshot, WindowFailure> {
        guard point.x.isFinite, point.y.isFinite else { return .failure(.invalidGeometry) }
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidate = Self.candidateWindow(in: infos, at: point)
        // System-wide hit testing avoids app-scoped hit-test failures during title-bar drags.
        let system = AXUIElementCreateSystemWide()
        let hit: Result<AXUIElement, WindowFailure> = read { timeout in
            AXUIElementSetMessagingTimeout(system, timeout)
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
            return (error, element)
        }
        var lastFailure: WindowFailure = .noWindow
        if case .success(let element) = hit, let window = enclosingWindow(of: element) {
            switch snapshot(window) {
            case .success(let snapshot):
                // If WindowServer identifies a normal window, ensure hit testing did not pick a utility overlay.
                if let candidate {
                    if snapshot.pid == candidate.pid, snapshot.frame.contains(point) { return .success(snapshot) }
                } else if snapshot.frame.contains(point), snapshot.pid != getpid() {
                    return .success(snapshot)
                }
            case .failure(let error): lastFailure = error
            }
        } else if case .failure(let error) = hit {
            if error == .permission || error == .cancelled { return .failure(error) }
            lastFailure = error
        }
        // Fallback: inspect only the identified app's windows. Never fall back to an unrelated focused window.
        guard let candidate else { return .failure(lastFailure) }
        let app = AXUIElementCreateApplication(candidate.pid)
        switch readAttribute(app, kAXWindowsAttribute) {
        case .failure(let error): return .failure(error)
        case .success(let raw):
            guard CFGetTypeID(raw) == CFArrayGetTypeID(), let windows = raw as? [AXUIElement] else { return .failure(.unsupported) }
            for window in windows.prefix(32) {
                guard !readRequest.isCancelled else { return .failure(.cancelled) }
                if let deadline = readDeadline, ProcessInfo.processInfo.systemUptime >= deadline { return .failure(.unresponsive) }
                switch snapshot(window) {
                case .success(let snapshot):
                    if Self.matchesCandidate(snapshot, candidate: candidate) {
                        glog("Window lookup recovered using window enumeration")
                        return .success(snapshot)
                    }
                case .failure(let error): lastFailure = error
                }
            }
        }
        return .failure(lastFailure)
    }

    private func prepare(_ element: AXUIElement) { AXUIElementSetMessagingTimeout(element, timeout) }

    private func failure(_ error: AXError) -> WindowFailure {
        glog("AX call failed: \(error.rawValue)")
        return WindowFailure.fromAX(error)
    }

    private func read<Value>(_ operation: (Float) -> (AXError, Value?)) -> Result<Value, WindowFailure> {
        AXReadPolicy.read(request: readDeadline == nil ? WindowRequest() : readRequest,
                          deadline: readDeadline ?? (ProcessInfo.processInfo.systemUptime + 1.5), operation: operation)
    }

    private func readAttribute(_ element: AXUIElement, _ attribute: String) -> Result<CFTypeRef, WindowFailure> {
        let result: Result<CFTypeRef, WindowFailure> = read { timeout in
            AXUIElementSetMessagingTimeout(element, timeout)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (error, value)
        }
        if case .failure(let error) = result, error == .unresponsive || error == .permission {
            glog("AX read \(attribute) failed: \(error)")
        }
        return result
    }

    private func snapshot(_ window: AXUIElement) -> Result<WindowSnapshot, WindowFailure> {
        prepare(window)
        let position: CFTypeRef
        let size: CFTypeRef
        switch readAttribute(window, kAXPositionAttribute) {
        case .success(let value): position = value
        case .failure(let error): return .failure(error)
        }
        switch readAttribute(window, kAXSizeAttribute) {
        case .success(let value): size = value
        case .failure(let error): return .failure(error)
        }
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return .failure(.unsupported) }
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
        guard case .success(let value) = readAttribute(element, kAXRoleAttribute) else { return nil }
        return value as? String
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        prepare(element)
        guard case .success(let raw) = readAttribute(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let result = raw as! AXUIElement
        prepare(result)
        return result
    }
}
