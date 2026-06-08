import AppKit

/// 창 크기 고정 모드일 때 화면 상단 중앙에 뜨는 안내 HUD.
/// 입력은 `MouseEventTap`이 처리하므로 클릭을 가로채지 않는다(`ignoresMouseEvents = true`).
final class ResizeHUDWindow: NSWindow {
    init(text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padX: CGFloat = 16
        let padY: CGFloat = 10
        let w = label.frame.width + padX * 2
        let h = label.frame.height + padY * 2

        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        // 반투명 재질은 밝은 배경/화면 녹화에서 흰 글자 대비가 약해 묻힌다.
        // 어디서나(녹화 포함) 또렷하도록 불투명한 진한 배경 + 흰 글자로 고정한다.
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.95).cgColor
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        label.frame = NSRect(x: padX, y: (h - label.frame.height) / 2,
                             width: w - padX * 2, height: label.frame.height)
        bg.addSubview(label)
        contentView = bg

        // 메인 화면 상단 중앙(메뉴바 아래)에 배치.
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            setFrameOrigin(NSPoint(x: vf.midX - w / 2, y: vf.maxY - h - 24))
        }
    }
}
