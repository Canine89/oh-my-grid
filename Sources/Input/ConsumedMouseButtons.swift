import CoreGraphics

/// A consumed down must own its matching drag/up, regardless of later mode changes.
struct ConsumedMouseButtons {
    private var left = false
    private var right = false

    mutating func recordDown(_ button: CGMouseButton) {
        if button == .left { left = true }
        if button == .right { right = true }
    }

    mutating func shouldConsume(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseUp:
            defer { left = false }
            return left
        case .rightMouseUp:
            defer { right = false }
            return right
        case .leftMouseDragged: return left
        case .rightMouseDragged: return right
        default: return false
        }
    }
}
