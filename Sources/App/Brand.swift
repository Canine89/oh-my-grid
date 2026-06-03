import AppKit

/// oh-my-grid 브랜드 상수.
enum Brand {
    static let name = "oh-my-grid"
    static let tagline = "드래그 중 우클릭으로 창을 그리드에 스냅"

    /// 브랜드 컬러 (그리드 하이라이트/강조).
    static let accent = NSColor(srgbRed: 0.20, green: 0.55, blue: 0.96, alpha: 1)

    /// 그리드 선 색.
    static let gridLine = NSColor(white: 1.0, alpha: 0.55)
}
