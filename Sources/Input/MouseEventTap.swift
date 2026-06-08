import AppKit
import CoreGraphics

/// 세션 레벨 CGEventTap으로 마우스 제스처를 관찰·소비한다.
/// 제스처: **좌버튼 드래그 도중 우버튼 누름 → 그리드 무장**, 셀을 가로질러 끈 뒤 버튼을 놓으면 창이 스냅된다.
/// 접근성 권한이 있어야 탭이 동작한다.
@MainActor
final class MouseEventTap {
    static let shared = MouseEventTap()
    private init() {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftDown = false
    /// 그리드 모드 토글로 우클릭(down)을 소비했으면 짝이 되는 up도 소비(컨텍스트 메뉴 차단).
    private var consumedRightDown = false
    /// 창 크기 고정 클릭(down)을 소비했으면 짝이 되는 up도 소비.
    private var consumedResizeDown = false

    /// 앱 시작 시 1회 호출 — 탭 설치. 권한이 없으면 false.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("MouseEventTap: tapCreate 실패 (접근성 권한 필요)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
        tap = machPort
        runLoopSource = source
        glog("이벤트 탭 생성 성공 (isTrusted=\(AccessibilityPermission.isGranted), enabled=\(Settings.shared.enabled))")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
    }

    /// 콜백에서 호출 — 이벤트 처리 후 통과(event)/소비(nil) 결정.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let session = GridSessionController.shared

        // OS가 부하/타임아웃으로 탭을 끈 경우는 예외 앱 여부와 무관하게 항상 재활성.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            glog("탭 비활성화 감지(\(type.rawValue)) → 재활성")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        // 창 크기 고정 모드: 메뉴에서 비율을 고른 직후 — 다음 좌클릭으로 그 창을 리사이즈하고 소비한다.
        // (사용자가 명시적으로 시작한 동작이라 예외 앱 가드보다 먼저 처리한다.)
        let resize = WindowResizeController.shared
        if resize.isArmed {
            switch type {
            case .leftMouseDown:
                resize.applyAt(point: event.location)
                consumedResizeDown = true
                return nil
            case .leftMouseUp:
                if consumedResizeDown { consumedResizeDown = false; return nil }
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
            consumedRightDown = false
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
                    consumedRightDown = true
                    return nil
                } else if session.arm(at: event.location) {
                    consumedRightDown = true
                    return nil
                }
            }
            return pass

        case .rightMouseUp:
            // 토글로 소비한 우클릭의 짝 → 컨텍스트 메뉴가 뜨지 않게 함께 소비.
            if consumedRightDown {
                consumedRightDown = false
                return nil
            }
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
