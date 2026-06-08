import AppKit

/// 창 크기 고정 모드에서 커서 아래 "대상 창"을 강조하는 보더리스 윈도우.
/// 화면 전체가 아니라 대상 창 frame 크기만 덮는다(AX 위치 조회가 전체를 가리지 않게).
/// 입력은 가로채지 않는다(`ignoresMouseEvents = true`).
final class ResizeHighlightWindow: NSWindow {
    private let highlightView = HighlightView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = highlightView
    }

    /// CG 전역(top-left) 창 frame 위로 강조를 배치한다.
    func place(cgFrame: CGRect) {
        let ak = ScreenGeometry.appKitRect(fromCG: cgFrame)
        setFrame(ak, display: true)
        highlightView.frame = NSRect(origin: .zero, size: ak.size)
        highlightView.needsDisplay = true
    }
}

/// 강조 채움 + 테두리를 그리는 뷰.
private final class HighlightView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Brand.accent.withAlphaComponent(0.22).setFill()
        bounds.fill()
        let inset = bounds.insetBy(dx: 1.5, dy: 1.5)
        let border = NSBezierPath(rect: inset)
        border.lineWidth = 3
        Brand.accent.setStroke()
        border.stroke()
    }
}
