import AppKit
import CoreGraphics

/// 좌표계 메모
/// - **CG 전역(top-left)**: 메인 디스플레이 좌상단이 원점, y 아래로 증가. `CGDisplayBounds`,
///   `CGEvent.location`, AX(`kAXPosition`/`kAXSize`)가 모두 이 공간을 쓴다 → 셀 계산을 여기서 한다.
/// - **AppKit 전역(bottom-left)**: 메인 디스플레이 좌하단이 원점, y 위로 증가. `NSScreen.frame`,
///   `NSWindow.setFrame`가 이 공간을 쓴다 → 오버레이 윈도우 배치에만 변환해 쓴다.
enum ScreenGeometry {
    /// 그리드 셀의 (열, 행) 인덱스. 0-based, 범위 클램프.
    struct Cell: Equatable {
        var col: Int
        var row: Int
    }

    /// 화면 가장자리 스냅 존. (코너 1/4 없음 — 위쪽은 최대화)
    enum EdgeZone: Equatable {
        case left, right, top, bottom
    }

    /// `CGDirectDisplayID`에 해당하는 NSScreen.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// CG 전역(top-left) 점을 포함하는 디스플레이를 찾는다.
    static func displayContaining(cgPoint point: CGPoint) -> (id: CGDirectDisplayID, bounds: CGRect)? {
        for screen in NSScreen.screens {
            let id = screen.displayID
            let bounds = CGDisplayBounds(id)
            if bounds.contains(point) { return (id, bounds) }
        }
        // 어느 화면에도 안 들어가면 메인으로 폴백.
        guard let main = NSScreen.main else { return nil }
        return (main.displayID, CGDisplayBounds(main.displayID))
    }

    /// CG 전역(top-left) 점이 속한 셀 인덱스.
    static func cell(at point: CGPoint, bounds: CGRect, cols: Int, rows: Int) -> Cell {
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        let col = Int((point.x - bounds.minX) / cellW)
        let row = Int((point.y - bounds.minY) / cellH)
        return Cell(col: clamp(col, 0, cols - 1), row: clamp(row, 0, rows - 1))
    }

    /// 두 셀(anchor~current)을 포함하는 셀 블록의 CG 전역(top-left) 사각형.
    static func unionRect(anchor: Cell, current: Cell, bounds: CGRect, cols: Int, rows: Int) -> CGRect {
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        let minCol = min(anchor.col, current.col)
        let maxCol = max(anchor.col, current.col)
        let minRow = min(anchor.row, current.row)
        let maxRow = max(anchor.row, current.row)
        return CGRect(x: bounds.minX + CGFloat(minCol) * cellW,
                      y: bounds.minY + CGFloat(minRow) * cellH,
                      width: CGFloat(maxCol - minCol + 1) * cellW,
                      height: CGFloat(maxRow - minRow + 1) * cellH)
    }

    /// 메뉴바·Dock을 제외한 사용 영역을 CG 전역(top-left) 사각형으로 반환.
    /// `NSScreen.visibleFrame`(AppKit bottom-left)을 CG 전역으로 변환한다 → 스냅 창이 메뉴바 밑으로 안 들어감.
    static func cgVisibleBounds(for screen: NSScreen) -> CGRect {
        let totalHeight = NSScreen.screens.map { CGDisplayBounds($0.displayID).maxY }.max() ?? screen.frame.maxY
        let vf = screen.visibleFrame
        // y 뒤집기: AppKit bottom-left → CG top-left.
        return CGRect(x: vf.minX,
                      y: totalHeight - vf.maxY,
                      width: vf.width,
                      height: vf.height)
    }

    /// CG 전역(top-left) 점이 디스플레이 가장자리 밴드(`threshold` 폭) 안에 있으면 해당 존을 반환.
    /// 코너 중첩 시 위/아래(수평 가장자리)를 좌/우보다 먼저 매칭한다.
    static func edgeZone(at point: CGPoint, bounds: CGRect, threshold: CGFloat) -> EdgeZone? {
        if point.y <= bounds.minY + threshold { return .top }
        if point.y >= bounds.maxY - threshold { return .bottom }
        if point.x <= bounds.minX + threshold { return .left }
        if point.x >= bounds.maxX - threshold { return .right }
        return nil
    }

    /// 존에 해당하는 목표 사각형(CG 전역 top-left). `usable`은 메뉴바/Dock 제외 사용 영역.
    static func rect(for zone: EdgeZone, usable: CGRect) -> CGRect {
        switch zone {
        case .left:
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height)
        case .right:
            return CGRect(x: usable.midX, y: usable.minY, width: usable.width / 2, height: usable.height)
        case .bottom:
            return CGRect(x: usable.minX, y: usable.midY, width: usable.width, height: usable.height / 2)
        case .top:
            return usable   // 최대화
        }
    }

    /// CG 전역(top-left) 사각형 → AppKit 전역(bottom-left) 사각형. 오버레이 윈도우 배치용.
    static func appKitRect(fromCG rect: CGRect) -> CGRect {
        // 모든 화면을 포함하는 전역 높이 기준으로 y를 뒤집는다.
        let totalHeight = NSScreen.screens.map { CGDisplayBounds($0.displayID).maxY }.max() ?? rect.maxY
        return CGRect(x: rect.minX,
                      y: totalHeight - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, v))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
