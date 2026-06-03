import AppKit

/// 한 디스플레이를 덮는 투명·보더리스 그리드 오버레이 윈도우.
/// 입력은 `MouseEventTap`이 처리하므로 이 창은 마우스 이벤트를 가로채지 않는다(`ignoresMouseEvents = true`).
final class GridOverlayWindow: NSWindow {
    let gridView: GridOverlayView

    init(screen: NSScreen) {
        gridView = GridOverlayView()
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

        contentView = gridView
        setFrame(screen.frame, display: true)
    }
}
