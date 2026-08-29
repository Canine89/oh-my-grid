import AppKit

/// 한 디스플레이를 덮는 투명·보더리스 그리드 오버레이 윈도우.
/// 입력은 `MouseEventTap`이 처리하므로 이 창은 마우스 이벤트를 가로채지 않는다(`ignoresMouseEvents = true`).
/// 등장/퇴장은 짧은 페이드로 처리해 툭 튀어나오는 느낌을 없앤다.
final class GridOverlayWindow: NSWindow {
    let gridView: GridOverlayView

    private static let fadeInDuration: TimeInterval = 0.16
    private static let fadeOutDuration: TimeInterval = 0.14

    init(screen: NSScreen) {
        gridView = GridOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true          // 드래그를 방해하지 않는다 — 입력은 이벤트 탭이 담당.
        isReleasedWhenClosed = false
        animationBehavior = .none          // 시스템 기본 창 애니메이션 대신 직접 페이드.

        contentView = gridView
        setFrame(screen.frame, display: true)
    }

    /// 투명 상태로 띄운 뒤 페이드 인.
    func fadeIn() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// 페이드 아웃 후 orderOut. 완료 전까지 클로저가 self 를 붙잡아 창이 먼저 해제되지 않는다.
    func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [self] in
            orderOut(nil)
        })
    }
}
