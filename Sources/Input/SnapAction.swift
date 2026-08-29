import AppKit

/// 키보드 단축키로 실행하는 창 스냅 동작. 각 동작은 기본 단축키(⌃⌥ + 키)를 갖고 설정에서 바꿀 수 있다.
enum SnapAction: String, CaseIterable, Codable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize, center
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    /// 기본 단축키. 화살표=절반, Return=최대화, C=가운데, U/I/J/K=사분면(Rectangle 계열 앱과 같은 관례).
    var defaultHotkey: Hotkey {
        let mods: HotkeyModifiers = [.control, .option]
        switch self {
        case .leftHalf:    return Hotkey(keyCode: 123, mods: mods)   // ←
        case .rightHalf:   return Hotkey(keyCode: 124, mods: mods)   // →
        case .topHalf:     return Hotkey(keyCode: 126, mods: mods)   // ↑
        case .bottomHalf:  return Hotkey(keyCode: 125, mods: mods)   // ↓
        case .maximize:    return Hotkey(keyCode: 36,  mods: mods)   // ↩
        case .center:      return Hotkey(keyCode: 8,   mods: mods)   // C
        case .topLeft:     return Hotkey(keyCode: 32,  mods: mods)   // U
        case .topRight:    return Hotkey(keyCode: 34,  mods: mods)   // I
        case .bottomLeft:  return Hotkey(keyCode: 38,  mods: mods)   // J
        case .bottomRight: return Hotkey(keyCode: 40,  mods: mods)   // K
        }
    }

    /// 사람이 읽는 이름(설정·메뉴·오버레이 라벨).
    var title: String {
        switch self {
        case .leftHalf:    return String(localized: "Left Half")
        case .rightHalf:   return String(localized: "Right Half")
        case .topHalf:     return String(localized: "Top Half")
        case .bottomHalf:  return String(localized: "Bottom Half")
        case .maximize:    return String(localized: "Maximize")
        case .center:      return String(localized: "Center")
        case .topLeft:     return String(localized: "Top Left Quarter")
        case .topRight:    return String(localized: "Top Right Quarter")
        case .bottomLeft:  return String(localized: "Bottom Left Quarter")
        case .bottomRight: return String(localized: "Bottom Right Quarter")
        }
    }

    /// 사용 영역(`usable`, CG 전역 top-left) 안에서 이 동작의 목표 사각형. `current`는 가운데 정렬에 쓰는 현재 창 프레임.
    func targetRect(usable u: CGRect, current: CGRect) -> CGRect {
        let halfW = u.width / 2, halfH = u.height / 2
        switch self {
        case .leftHalf:    return CGRect(x: u.minX, y: u.minY, width: halfW, height: u.height)
        case .rightHalf:   return CGRect(x: u.midX, y: u.minY, width: halfW, height: u.height)
        case .topHalf:     return CGRect(x: u.minX, y: u.minY, width: u.width, height: halfH)
        case .bottomHalf:  return CGRect(x: u.minX, y: u.midY, width: u.width, height: halfH)
        case .maximize:    return u
        case .center:
            let w = min(current.width, u.width), h = min(current.height, u.height)
            return CGRect(x: u.midX - w / 2, y: u.midY - h / 2, width: w, height: h)
        case .topLeft:     return CGRect(x: u.minX, y: u.minY, width: halfW, height: halfH)
        case .topRight:    return CGRect(x: u.midX, y: u.minY, width: halfW, height: halfH)
        case .bottomLeft:  return CGRect(x: u.minX, y: u.midY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: u.midX, y: u.midY, width: halfW, height: halfH)
        }
    }
}
