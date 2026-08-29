import AppKit

/// oh-my-grid 브랜드 상수.
enum Brand {
    static let name = "oh-my-grid"
    static var tagline: String { String(localized: "Snap windows to a grid with a right-click while dragging") }

    /// 브랜드 컬러 (그리드 하이라이트/강조).
    static let accent = NSColor(srgbRed: 0.20, green: 0.55, blue: 0.96, alpha: 1)

    /// 그리드 선 색. 밝은 앱 위에서도 시끄럽지 않게 저대비.
    static let gridLine = NSColor(white: 1.0, alpha: 0.28)
    /// 그리드 교차점 도트 색. 선보다 또렷해 셀 경계를 잡아 준다.
    static let gridDot = NSColor(white: 1.0, alpha: 0.85)
    /// 오버레이 전체 디밍(그리드 모드에서만).
    static let overlayDim = NSColor(white: 0, alpha: 0.10)

    /// 선택 블록 라벨(셀 수 · 픽셀 크기) 배경/테두리/글자.
    static let labelBackground = NSColor(white: 0.08, alpha: 0.82)
    static let labelBorder = NSColor(white: 1.0, alpha: 0.18)
    static let labelText = NSColor.white
}
