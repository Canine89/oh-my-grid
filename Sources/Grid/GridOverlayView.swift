import AppKit
import QuartzCore

/// 그리드 선·교차점 도트와 선택된 셀 블록 하이라이트, 크기 라벨을 그리는 레이어 기반 뷰.
///
/// 좌표: 입력은 모두 CG 전역(top-left). `cgOrigin`을 빼 뷰-로컬 top-left로 만든 뒤,
/// 뷰는 AppKit 기본(bottom-left)이므로 y를 한 번 뒤집어 레이어에 배치한다.
/// (뷰를 flipped 로 두지 않는 이유: 레이어 contents/텍스트가 뒤집히는 문제를 피하기 위함.)
///
/// 선택 블록은 셀이 바뀔 때 spring 보간으로 미끄러지고, 라벨은 블록 중앙을 따라간다.
final class GridOverlayView: NSView {
    /// 이 뷰가 덮는 디스플레이의 CG 전역(top-left) 원점.
    var cgOrigin: CGPoint = .zero
    /// 디스플레이의 CG 전역 경계(셀 폭/높이 계산용). 설정 후 `rebuildGrid()` 호출.
    var displayBounds: CGRect = .zero
    var columns: Int = 6
    var rows: Int = 4

    /// 선택된 셀 블록의 CG 전역(top-left) 사각형. nil이면 미선택.
    /// 첫 설정은 즉시, 이후 변경은 spring 애니메이션.
    var selection: CGRect? {
        didSet {
            guard oldValue != selection else { return }
            layoutSelection(animated: oldValue != nil)
        }
    }

    /// 선택 블록 중앙에 띄울 라벨("3 × 2 · 1280 × 720" 등). nil이면 숨김.
    var label: String? {
        didSet {
            guard oldValue != label else { return }
            renderLabel()
            layoutSelection(animated: false, onlyLabelSize: true)
        }
    }

    /// true이면 디밍·그리드 선을 그리지 않고 `selection` 하이라이트만 표시(가장자리 스냅 미리보기용).
    var previewOnly = false {
        didSet { rebuildGrid() }
    }

    // MARK: 레이어

    private let dimLayer = CALayer()
    private let lineLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let selectionLayer = CALayer()
    private let labelLayer = CALayer()

    private var labelSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.masksToBounds = false

        dimLayer.backgroundColor = Brand.overlayDim.cgColor
        dimLayer.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]

        lineLayer.strokeColor = Brand.gridLine.cgColor
        lineLayer.fillColor = nil
        lineLayer.lineWidth = 1
        lineLayer.actions = ["path": NSNull(), "opacity": NSNull()]

        dotLayer.fillColor = Brand.gridDot.cgColor
        dotLayer.strokeColor = nil
        dotLayer.actions = ["path": NSNull(), "opacity": NSNull()]

        selectionLayer.backgroundColor = Brand.accent.withAlphaComponent(0.20).cgColor
        selectionLayer.borderColor = Brand.accent.cgColor
        selectionLayer.borderWidth = 2
        selectionLayer.cornerRadius = 10
        selectionLayer.cornerCurve = .continuous
        // 바깥 글로우.
        selectionLayer.shadowColor = Brand.accent.cgColor
        selectionLayer.shadowOpacity = 0.55
        selectionLayer.shadowRadius = 14
        selectionLayer.shadowOffset = .zero
        selectionLayer.isHidden = true
        selectionLayer.actions = [
            "position": Self.springAction(keyPath: "position"),
            "bounds": Self.springAction(keyPath: "bounds"),
            "hidden": NSNull(),
        ]

        labelLayer.isHidden = true
        labelLayer.actions = [
            "position": Self.springAction(keyPath: "position"),
            "bounds": NSNull(),
            "contents": NSNull(),
            "hidden": NSNull(),
        ]

        root.addSublayer(dimLayer)
        root.addSublayer(lineLayer)
        root.addSublayer(dotLayer)
        root.addSublayer(selectionLayer)
        root.addSublayer(labelLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        lineLayer.contentsScale = scale
        dotLayer.contentsScale = scale
        labelLayer.contentsScale = scale
        renderLabel()
    }

    override func layout() {
        super.layout()
        rebuildGrid()
    }

    // MARK: 그리드

    /// `displayBounds`/`columns`/`rows`/`previewOnly` 반영. 프레임이 잡힌 뒤 호출해야 한다.
    func rebuildGrid() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        dimLayer.frame = bounds
        dimLayer.isHidden = previewOnly
        lineLayer.frame = bounds
        dotLayer.frame = bounds

        guard !previewOnly, displayBounds.width > 0, displayBounds.height > 0, columns > 0, rows > 0 else {
            lineLayer.path = nil
            dotLayer.path = nil
            lineLayer.isHidden = true
            dotLayer.isHidden = true
            return
        }
        lineLayer.isHidden = false
        dotLayer.isHidden = false

        // 메뉴바/Dock을 제외한 사용 영역(displayBounds)에만 그린다.
        let grid = localRect(fromCG: displayBounds)
        let cellW = grid.width / CGFloat(columns)
        let cellH = grid.height / CGFloat(rows)

        // 1px 선이 픽셀 경계에 걸쳐 흐려지지 않게 반 픽셀 보정.
        let scale = window?.backingScaleFactor ?? 2
        let half = 0.5 / scale
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale + half }

        let lines = CGMutablePath()
        for c in 0...columns {
            let x = snap(grid.minX + CGFloat(c) * cellW)
            lines.move(to: CGPoint(x: x, y: grid.minY))
            lines.addLine(to: CGPoint(x: x, y: grid.maxY))
        }
        for r in 0...rows {
            let y = snap(grid.minY + CGFloat(r) * cellH)
            lines.move(to: CGPoint(x: grid.minX, y: y))
            lines.addLine(to: CGPoint(x: grid.maxX, y: y))
        }
        lineLayer.path = lines

        // 교차점 도트(가장자리 제외 — 화면 테두리에 점이 붙으면 지저분함).
        let dots = CGMutablePath()
        let radius: CGFloat = 2
        if columns > 1, rows > 1 {
            for c in 1..<columns {
                for r in 1..<rows {
                    let center = CGPoint(x: grid.minX + CGFloat(c) * cellW,
                                         y: grid.minY + CGFloat(r) * cellH)
                    dots.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }
        dotLayer.path = dots
    }

    // MARK: 선택 블록 + 라벨

    private func layoutSelection(animated: Bool, onlyLabelSize: Bool = false) {
        guard let sel = selection else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionLayer.isHidden = true
            labelLayer.isHidden = true
            CATransaction.commit()
            return
        }
        let local = localRect(fromCG: sel)
        let center = CGPoint(x: local.midX, y: local.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if !onlyLabelSize {
            selectionLayer.isHidden = false
            selectionLayer.bounds = CGRect(origin: .zero, size: local.size)
            selectionLayer.position = center
        }
        if label != nil, labelSize.width > 0 {
            labelLayer.isHidden = false
            labelLayer.bounds = CGRect(origin: .zero, size: labelSize)
            labelLayer.position = center
        } else {
            labelLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// 라벨 텍스트를 알약 모양 이미지로 렌더해 레이어 contents 로 올린다.
    /// (CATextLayer 대신 이미지로 두면 폰트 렌더링·좌표계 문제 없이 항상 또렷하다.)
    private func renderLabel() {
        guard let text = label, !text.isEmpty else {
            labelLayer.contents = nil
            labelSize = .zero
            return
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Brand.labelText,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let padX: CGFloat = 14
        let padY: CGFloat = 7
        let size = CGSize(width: ceil(textSize.width + padX * 2), height: ceil(textSize.height + padY * 2))
        labelSize = size

        let image = NSImage(size: size, flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: rect.height / 2, yRadius: rect.height / 2)
            Brand.labelBackground.setFill()
            pill.fill()
            Brand.labelBorder.setStroke()
            pill.lineWidth = 1
            pill.stroke()
            str.draw(at: CGPoint(x: padX, y: (rect.height - textSize.height) / 2))
            return true
        }
        labelLayer.contents = image.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
    }

    // MARK: 좌표 변환 / 애니메이션

    /// CG 전역(top-left) → 뷰-로컬(bottom-left).
    private func localRect(fromCG rect: CGRect) -> CGRect {
        let topLeftY = rect.minY - cgOrigin.y
        return CGRect(x: rect.minX - cgOrigin.x,
                      y: bounds.height - topLeftY - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    /// 셀 이동 시 쓰는 spring. 살짝 오버슈트하되 빠르게 안착(≈0.35s).
    private static func springAction(keyPath: String) -> CASpringAnimation {
        let s = CASpringAnimation(keyPath: keyPath)
        s.mass = 1
        s.stiffness = 420
        s.damping = 34
        s.initialVelocity = 0
        s.duration = s.settlingDuration
        return s
    }
}
