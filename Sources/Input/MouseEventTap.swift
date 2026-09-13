import AppKit
import CoreGraphics

/// 세션 레벨 CGEventTap으로 마우스 제스처를 관찰·소비한다.
/// 제스처: **좌버튼 드래그 도중 우버튼 누름 → 그리드 무장**, 셀을 가로질러 끈 뒤 버튼을 놓으면 창이 스냅된다.
/// 접근성 권한이 있어야 탭이 동작한다.
///
/// 탭은 메인 런루프에 붙어 있어 콜백이 메인 스레드에서 돈다. 능동 탭(`.defaultTap`)은 콜백이 돌아올 때까지
/// WindowServer가 해당 입력을 붙들기 때문에, 메인 스레드가 멈추면(권한 prompt, 모달, 느린 IPC)
/// 시스템 전체의 클릭·키 입력이 함께 멈춘다. 그래서
/// 1) 콜백 경로에서는 IPC(권한 조회, 탭 재설치)를 하지 않고
/// 2) `TapStallGuard`가 백그라운드에서 메인 스레드를 감시해 멈추면 탭을 즉시 끄고, 회복되면 다시 켠다.
@MainActor
final class MouseEventTap {
    static let shared = MouseEventTap()
    private init() {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftDown = false
    private var consumedButtons = ConsumedMouseButtons()
    /// 창 크기 고정 호버 미리보기용. armed일 때만 mouseMoved를 탭 마스크에 넣는다.
    private var tracksMouseMoved = false
    private var reinstallScheduled = false
    private let stallGuard = TapStallGuard()

    /// 앱 시작 시 1회 호출 — 탭 설치. 권한이 없으면 false.
    @discardableResult
    func start() -> Bool {
        guard AccessibilityPermission.isGranted else { stop(); return false }
        if let tap, CFMachPortIsValid(tap) {
            if !stallGuard.isSuspended, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return stallGuard.isSuspended || CGEvent.tapIsEnabled(tap: tap)
        }
        removeTap()
        return installTap()
    }

    /// 창 크기 고정 호버가 필요할 때만 mouseMoved를 구독해 평상시 콜백 부담을 줄인다.
    /// 재설치는 다음 런루프 턴으로 미룬다 — 탭 콜백 안에서 자기 자신을 무효화·재생성(WindowServer 왕복)하지 않도록.
    func setTracksMouseMoved(_ enabled: Bool) {
        guard tracksMouseMoved != enabled else { return }
        tracksMouseMoved = enabled
        guard tap != nil, !reinstallScheduled else { return }
        reinstallScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.reinstallTap() }
        }
    }

    private func reinstallTap() {
        reinstallScheduled = false
        guard tap != nil else { return }   // 그 사이 stop() 됐으면 설치하지 않는다.
        removeTap()
        if !installTap() {
            // 마스크 변경 중 권한이 회수되면 탭이 유실된 채 남는다 → 허용 감지 watcher로 복구.
            glog("mouseMoved 마스크 변경 중 탭 재설치 실패 → 권한 watcher 요청")
            NotificationCenter.default.post(name: .accessibilityPermissionWatchRequested, object: nil)
        }
    }

    @discardableResult
    private func installTap() -> Bool {
        var mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        if tracksMouseMoved {
            mask |= (1 << CGEventType.mouseMoved.rawValue)
        }

        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            glog("MouseEventTap: tapCreate failed; trusted=\(AccessibilityPermission.isGranted)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
        tap = machPort
        runLoopSource = source
        stallGuard.start(tap: machPort) { [weak self] in
            MainActor.assumeIsolated { self?.recoverFromStall() }
        }
        glog("이벤트 탭 생성 성공 (isTrusted=\(AccessibilityPermission.isGranted), enabled=\(Settings.shared.enabled), mouseMoved=\(tracksMouseMoved))")
        return true
    }

    func stop() {
        removeTap()
        leftDown = false
        consumedButtons = ConsumedMouseButtons()
    }

    private func removeTap() {
        stallGuard.stop()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
    }

    /// 메인 스레드 정지로 탭이 잠시 꺼졌다가 회복된 뒤. 그 사이 놓친 버튼 up 때문에 다음 클릭을
    /// 잘못 소비하지 않도록 버튼 상태를 초기화하고 진행 중이던 세션은 정리한다.
    private func recoverFromStall() {
        leftDown = false
        consumedButtons = ConsumedMouseButtons()
        let session = GridSessionController.shared
        if session.isArmed || session.hasPending { session.cancel() }
    }

    /// 콜백에서 호출 — 이벤트 처리 후 통과(event)/소비(nil) 결정.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let session = GridSessionController.shared

        // OS가 부하/타임아웃으로 탭을 끈 경우는 예외 앱 여부와 무관하게 항상 재활성.
        // (정지 감시가 꺼 둔 상태면 감시가 회복 시점에 다시 켠다.)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            glog("탭 비활성화 감지(\(type.rawValue)) → 재활성")
            if let tap, !stallGuard.isSuspended { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        // Finish consumed button pairs even after the mode ended or the frontmost app changed.
        if consumedButtons.shouldConsume(type) {
            if type == .leftMouseUp { leftDown = false }
            if type == .rightMouseDragged, session.isArmed { session.update(to: event.location) }
            return nil
        }
        if type == .keyDown, ShortcutRecorderView.isRecordingShortcut { return pass }

        // 창 크기 고정 모드: 메뉴에서 비율을 고른 직후 — 다음 좌클릭으로 그 창을 리사이즈하고 소비한다.
        // (사용자가 명시적으로 시작한 동작이라 예외 앱 가드보다 먼저 처리한다.)
        let resize = WindowResizeController.shared
        if resize.isArmed {
            switch type {
            case .leftMouseDown:
                resize.applyAt(point: event.location)
                consumedButtons.recordDown(.left)
                return nil
            case .leftMouseUp:
                return pass
            case .mouseMoved:
                resize.updateHover(at: event.location)
                return pass
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventKeycode) == 53 {   // Esc
                    resize.cancel()
                    glog("Esc → 창 크기 고정 취소")
                    return nil
                }
                return pass
            case .rightMouseDown:
                resize.cancel()   // 우클릭으로도 취소
                return pass
            default:
                return pass
            }
        }

        // 예외 목록에 든 앱(게임 등)이 맨 앞이면 입력에 일절 개입하지 않는다.
        // 진행 중이던 세션·상태는 깔끔히 정리해 앱 전환 후 잔상이 남지 않게 한다.
        if ActiveAppMonitor.shared.isFrontmostExcluded {
            if session.isArmed || session.hasPending { session.cancel() }
            leftDown = false
            return pass
        }

        switch type {
        case .leftMouseDown:
            leftDown = true
            // 일반 드래그 가장자리 스냅을 위해 후보 창을 캡처(엣지 스냅이 꺼져 있으면 내부에서 무시).
            session.beginDrag(at: event.location)
            return pass

        case .leftMouseUp:
            leftDown = false
            // 드래그(좌버튼)가 끝나는 시점 = 창이 이미 커서 위치에 있는 시점.
            // 가장자리 스냅 목표가 있으면 먼저 확정한 뒤, 확정 목표로 한 번 스냅한다(번쩍임 없음).
            session.endEdgeDrag()
            session.commitPending()
            return pass   // 좌클릭은 절대 소비하지 않는다.

        case .rightMouseDown:
            // 좌드래그 도중 우클릭(클릭) = 그리드 모드 토글. 우버튼을 계속 누르고 있을 필요 없다.
            // 켜진 상태에서 다시 우클릭하면 그리드 모드 해제(일반 드래그로 복귀).
            if leftDown {
                if session.isArmed {
                    session.cancel()
                    consumedButtons.recordDown(.right)
                    return nil
                } else if session.arm(at: event.location) {
                    consumedButtons.recordDown(.right)
                    return nil
                }
            }
            return pass

        case .rightMouseUp:
            return pass

        case .leftMouseDragged:
            // 창은 OS 드래그로 커서를 그대로 따라가게 둔다(소비하지 않음) → 마지막 스냅이 매끄럽다.
            if session.isArmed {
                session.update(to: event.location)
            } else {
                // 그리드 비무장 시: 일반 드래그 가장자리 절반 스냅 미리보기 갱신.
                session.updateEdgeDrag(to: event.location)
            }
            return pass

        case .rightMouseDragged:
            if session.isArmed {
                session.update(to: event.location)
                return nil
            }
            return pass

        case .mouseMoved:
            return pass

        case .keyDown:
            // 무장/확정대기 중 Esc(키코드 53) → 창 변경 없이 취소.
            if (session.isArmed || session.hasPending),
               event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                session.cancel()
                glog("Esc → 세션 취소")
                return nil
            }
            // 키보드 스냅 단축키(⌃⌥← 등) → 맨 앞 창을 절반/사분면/최대화.
            if !leftDown, KeyboardSnapController.shared.handle(event) {
                return nil
            }
            // 창을 드래그하는 도중 그리드 단축키 → 우클릭과 동일하게 그리드 토글.
            // 트랙패드에서 "끌면서 우클릭"이 어려운 걸 키보드로 대체한다(기본 ⌃⌥G, 설정 변경 가능).
            if leftDown, Settings.shared.gridHotkey.matches(event) {
                if session.isArmed {
                    session.cancel()
                } else {
                    session.arm(at: event.location)
                }
                return nil
            }
            return pass

        default:
            return pass
        }
    }

    /// 무장 중 Esc 등으로 외부에서 취소할 때.
    func cancelSession() {
        GridSessionController.shared.cancel()
    }
}

/// CGEventTap C 콜백. 탭은 메인 런루프에 설치되므로 메인 스레드에서 호출된다 → assumeIsolated 안전.
private func mouseEventTapCallback(proxy: CGEventTapProxy,
                                   type: CGEventType,
                                   event: CGEvent,
                                   userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        tap.handle(type: type, event: event)
    }
}

/// 메인 스레드 정지 감시. 백그라운드 타이머가 메인 큐에 ping을 보내고, 응답이 `stallThreshold` 안에
/// 오지 않으면 백그라운드 스레드에서 탭을 끈다(WindowServer가 우리 응답을 기다리며 입력을 붙들지 않게).
/// 메인 스레드가 다시 ping에 응답하면 탭을 켜고 `onRecover`로 상태 정리를 맡긴다.
/// 모든 상태는 `lock`으로 보호되며, 탭 포트는 `start`/`stop` 사이에서만 유효하다.
private final class TapStallGuard: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.goldenrabbit.ohmygrid.tap-stall-guard", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var tap: CFMachPort?
    private var pingSentAt: TimeInterval?
    private var suspended = false
    private var generation = 0
    private var onRecover: (() -> Void)?

    private let pingInterval: TimeInterval = 0.25
    private let stallThreshold: TimeInterval = 0.5

    var isSuspended: Bool {
        lock.lock(); defer { lock.unlock() }
        return suspended
    }

    func start(tap: CFMachPort, onRecover: @escaping () -> Void) {
        stop()
        lock.lock()
        self.tap = tap
        self.onRecover = onRecover
        pingSentAt = nil
        suspended = false
        generation &+= 1
        let generation = self.generation
        lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.tick(generation: generation) }
        timer.resume()
        lock.lock()
        self.timer = timer
        lock.unlock()
    }

    func stop() {
        lock.lock()
        timer?.cancel()
        timer = nil
        tap = nil
        onRecover = nil
        pingSentAt = nil
        suspended = false
        generation &+= 1
        lock.unlock()
    }

    private func tick(generation: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard self.generation == generation, let tap else { lock.unlock(); return }
        if let sentAt = pingSentAt {
            // 이전 ping이 아직 응답되지 않았다 → 메인 스레드가 멈춰 있다.
            if !suspended, now - sentAt >= stallThreshold {
                suspended = true
                CGEvent.tapEnable(tap: tap, enable: false)
                lock.unlock()
                glog("메인 스레드 정지 감지(\(Int((now - sentAt) * 1000))ms) → 이벤트 탭 임시 해제")
                return
            }
            lock.unlock()
            return
        }
        pingSentAt = now
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.pong(generation: generation) }
    }

    private func pong(generation: Int) {
        lock.lock()
        guard self.generation == generation else { lock.unlock(); return }
        pingSentAt = nil
        guard suspended, let tap else { lock.unlock(); return }
        suspended = false
        CGEvent.tapEnable(tap: tap, enable: true)
        let recover = onRecover
        lock.unlock()
        glog("메인 스레드 회복 → 이벤트 탭 재활성")
        recover?()
    }
}
