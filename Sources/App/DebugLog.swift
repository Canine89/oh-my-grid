import Foundation
import CoreGraphics

/// rect 를 짧게 포맷 (로그용).
func rs(_ r: CGRect) -> String {
    "[\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))]"
}

/// 경량 로거(Console/unified logging). 진단이 필요할 때 `log stream --predicate 'process=="oh-my-grid"'`.
func glog(_ message: String) {
    NSLog("[oh-my-grid] \(message)")
}
