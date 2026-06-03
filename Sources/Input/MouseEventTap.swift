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

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // OS가 부하/타임아웃으로 탭을 끈 경우 재활성.
            glog("탭 비활성화 감지(\(type.rawValue)) → 재활성")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .leftMouseDown:
            leftDown = true
            return pass

        case .leftMouseUp:
            leftDown = false
            // 드래그(좌버튼)가 끝나는 시점 = 창이 이미 커서 위치에 있는 시점.
            // 여기서 확정 목표로 한 번 스냅한다(번쩍임 없음).
            session.commitPending()
            return pass   // 좌클릭은 절대 소비하지 않는다.

        case .rightMouseDown:
            // 좌드래그 도중에만 무장. 평상시 우클릭/컨텍스트 메뉴는 건드리지 않는다.
            glog("rightMouseDown @\(pt(event.location)) leftDown=\(leftDown) enabled=\(Settings.shared.enabled)")
            if leftDown, session.arm(at: event.location) {
                return nil                // 컨텍스트 메뉴가 뜨지 않도록 소비.
            }
            return pass

        case .rightMouseUp:
            // 그리드를 닫고 선택을 확정만 한다(창은 아직 안 옮김). 실제 스냅은 좌버튼 해제 때.
            if session.isArmed {
                session.lockSelection()
                return nil
            }
            return pass

        case .leftMouseDragged:
            // 창은 OS 드래그로 커서를 그대로 따라가게 둔다(소비하지 않음) → 마지막 스냅이 매끄럽다.
            if session.isArmed { session.update(to: event.location) }
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

    private func pt(_ p: CGPoint) -> String { "(\(Int(p.x)),\(Int(p.y)))" }

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
