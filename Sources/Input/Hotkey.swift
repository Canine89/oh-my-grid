import AppKit
import CoreGraphics

/// 단축키 수정키 집합(저장·표시·매칭에 공통으로 쓰는 내부 표현).
struct HotkeyModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let control = HotkeyModifiers(rawValue: 1 << 0)
    static let option  = HotkeyModifiers(rawValue: 1 << 1)
    static let command = HotkeyModifiers(rawValue: 1 << 2)
    static let shift   = HotkeyModifiers(rawValue: 1 << 3)
}

/// 그리드 발동 단축키. UserDefaults 저장, CGEvent 매칭, 표시 문자열, 예약어 검증을 담당한다.
struct Hotkey: Hashable {
    var keyCode: Int
    var mods: HotkeyModifiers

    /// 기본값: ⌃⌥G.
    static let `default` = Hotkey(keyCode: 5, mods: [.control, .option])

    // MARK: 매칭

    /// CGEvent(keyDown)가 이 단축키와 정확히 일치하는지(관련 수정키만 비교).
    func matches(_ event: CGEvent) -> Bool {
        guard Int(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return false }
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        var needed: CGEventFlags = []
        if mods.contains(.control) { needed.insert(.maskControl) }
        if mods.contains(.option)  { needed.insert(.maskAlternate) }
        if mods.contains(.command) { needed.insert(.maskCommand) }
        if mods.contains(.shift)   { needed.insert(.maskShift) }
        return event.flags.intersection(relevant) == needed
    }

    /// 녹화된 NSEvent(keyDown) → Hotkey.
    static func from(event: NSEvent) -> Hotkey {
        var m: HotkeyModifiers = []
        let f = event.modifierFlags
        if f.contains(.control) { m.insert(.control) }
        if f.contains(.option)  { m.insert(.option) }
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.shift)   { m.insert(.shift) }
        return Hotkey(keyCode: Int(event.keyCode), mods: m)
    }

    // MARK: 표시

    /// "⌃⌥G" 형태의 사람이 읽는 문자열(수정키 순서 ⌃⌥⇧⌘).
    var displayString: String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += Hotkey.keyName(keyCode)
        return s
    }

    // MARK: 검증 (시스템·기본 단축키 차단)

    /// 설정 불가 사유(없으면 nil). 수정키 최소조건 + 예약 단축키 목록으로 막는다.
    var validationError: String? {
        if mods.isEmpty || mods == [.shift] {
            return "⌘·⌃·⌥ 중 하나 이상을 포함해야 합니다 (수정키 없는 키는 일반 입력과 충돌)."
        }
        if Hotkey.reserved.contains(self) {
            return "macOS 시스템·앱 기본 단축키라서 사용할 수 없습니다."
        }
        return nil
    }

    var isValid: Bool { validationError == nil }

    // MARK: 키코드 → 표시 이름

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(_ code: Int) -> String {
        keyNames[code] ?? "키\(code)"
    }

    // MARK: 예약 단축키 (리서치 기반)

    /// macOS 시스템 전역 + 앱 공통 기본 단축키. 사용자가 그리드 단축키로 못 쓰게 막는다.
    static let reserved: Set<Hotkey> = {
        let M: HotkeyModifiers = .command
        let C: HotkeyModifiers = .control
        let O: HotkeyModifiers = .option
        let S: HotkeyModifiers = .shift
        var set: Set<Hotkey> = []
        func add(_ code: Int, _ mods: HotkeyModifiers) { set.insert(Hotkey(keyCode: code, mods: mods)) }

        // 시스템 전역
        add(49, [M])          // ⌘Space  Spotlight
        add(49, [C])          // ⌃Space  입력 소스 전환
        add(49, [C, M])       // ⌃⌘Space 이모지·기호
        add(48, [M])          // ⌘Tab    앱 전환
        add(50, [M])          // ⌘`      같은 앱 창 전환
        add(123, [C]); add(124, [C]); add(125, [C]); add(126, [C])  // ⌃화살표 미션컨트롤/스페이스
        add(3,  [C, M])       // ⌃⌘F     전체 화면
        add(12, [C, M])       // ⌃⌘Q     화면 잠금
        add(53, [O, M])       // ⌥⌘Esc   강제 종료
        add(2,  [O, M])       // ⌥⌘D     Dock 자동 숨김
        add(20, [S, M]); add(21, [S, M]); add(23, [S, M]); add(22, [S, M])  // ⇧⌘3/4/5/6 스크린샷
        add(12, [S, M])       // ⇧⌘Q     로그아웃

        // 앱 공통 기본 (전역 소비 시 광범위하게 깨지므로 차단)
        for code in [12, 13, 8, 9, 7, 6, 0, 1, 45, 31, 35, 3, 4, 46, 17, 43] {
            add(code, [M])    // ⌘Q W C V X Z A S N O P F H M T ,
        }
        add(6, [S, M])        // ⇧⌘Z     다시 실행

        return set
    }()
}
