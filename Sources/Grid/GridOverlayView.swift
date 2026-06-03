import AppKit

/// 그리드 선과 선택된 셀 블록 하이라이트를 그리는 뷰.
/// 좌표는 CG 전역(top-left)을 `cgOrigin`만큼 빼서 뷰-로컬(flipped)로 변환해 그린다.
final class GridOverlayView: NSView {
    /// 이 뷰가 덮는 디스플레이의 CG 전역(top-left) 원점.
    var cgOrigin: CGPoint = .zero
    /// 디스플레이의 CG 전역 경계(셀 폭/높이 계산용).
    var displayBounds: CGRect = .zero
    var columns: Int = 6
    var rows: Int = 4
    /// 선택된 셀 블록의 CG 전역(top-left) 사각형. nil이면 미선택.
    var selection: CGRect? {
        didSet { needsDisplay = true }
    }
    /// true이면 그리드 선을 그리지 않고 `selection` 하이라이트만 표시(가장자리 스냅 미리보기용).
    var previewOnly = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard displayBounds.width > 0, displayBounds.height > 0 else { return }

        // 은은한 전체 디밍.
        NSColor(white: 0, alpha: 0.12).setFill()
        bounds.fill()

        // 그리드 선 (미리보기 모드에서는 생략 — 단일 하이라이트만 보여줌).
        if !previewOnly {
            let cellW = bounds.width / CGFloat(columns)
            let cellH = bounds.height / CGFloat(rows)
            let linePath = NSBezierPath()
            linePath.lineWidth = 1
            for c in 0...columns {
                let x = CGFloat(c) * cellW
                linePath.move(to: CGPoint(x: x, y: 0))
                linePath.line(to: CGPoint(x: x, y: bounds.height))
            }
            for r in 0...rows {
                let y = CGFloat(r) * cellH
                linePath.move(to: CGPoint(x: 0, y: y))
                linePath.line(to: CGPoint(x: bounds.width, y: y))
            }
            Brand.gridLine.setStroke()
            linePath.stroke()
        }

        // 선택 블록 하이라이트.
        if let sel = selection {
            let local = CGRect(x: sel.minX - cgOrigin.x,
                               y: sel.minY - cgOrigin.y,
                               width: sel.width,
                               height: sel.height)
            Brand.accent.withAlphaComponent(0.28).setFill()
            local.fill()
            let border = NSBezierPath(rect: local)
            border.lineWidth = 3
            Brand.accent.setStroke()
            border.stroke()
        }
    }
}
