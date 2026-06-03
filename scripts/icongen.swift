import AppKit

// 1024x1024 앱 아이콘 — 블루 스퀘어클 배경 + 6x4 그리드 + 강조 셀 블록
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// 스퀘어클 배경
let margin: CGFloat = 92
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let corner = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

cg.saveGState()
cg.addPath(squircle); cg.clip()
let colors = [NSColor(srgbRed: 0.30, green: 0.62, blue: 0.99, alpha: 1).cgColor,
              NSColor(srgbRed: 0.13, green: 0.40, blue: 0.86, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
cg.restoreGState()

// 그리드 영역
let inset: CGFloat = margin + 150
let area = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let cols = 6, rows = 4
let cellW = area.width / CGFloat(cols)
let cellH = area.height / CGFloat(rows)

// 강조 셀 블록 (좌상단 3x2 영역) — 흰색 반투명 채움
let blockCols = 3, blockRows = 2
let block = CGRect(x: area.minX, y: area.maxY - CGFloat(blockRows) * cellH,
                   width: CGFloat(blockCols) * cellW, height: CGFloat(blockRows) * cellH)
NSColor.white.withAlphaComponent(0.30).setFill()
NSBezierPath(rect: block).fill()

// 그리드 선
let line = NSBezierPath()
line.lineWidth = 16
line.lineCapStyle = .round
for c in 0...cols {
    let x = area.minX + CGFloat(c) * cellW
    line.move(to: CGPoint(x: x, y: area.minY)); line.line(to: CGPoint(x: x, y: area.maxY))
}
for r in 0...rows {
    let y = area.minY + CGFloat(r) * cellH
    line.move(to: CGPoint(x: area.minX, y: y)); line.line(to: CGPoint(x: area.maxX, y: y))
}
NSColor.white.setStroke()
line.stroke()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("written: \(CommandLine.arguments[1])")
