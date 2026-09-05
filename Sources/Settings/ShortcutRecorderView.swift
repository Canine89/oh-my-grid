import AppKit

/// 키 조합을 눌러 단축키를 녹화하는 작은 컨트롤. 클릭하면 녹화 모드로 들어가고,
/// 다음에 누른 키 조합을 검증해 유효하면 `onChange`로 알린다(예약어는 `onError`).
final class ShortcutRecorderView: NSView {
    /// 유효한 새 단축키가 녹화되면 호출.
    var onChange: ((Hotkey) -> Void)?
    /// 검증 실패/해제 메시지(""이면 지움).
    var onError: ((String) -> Void)?

    private var hotkey: Hotkey
    private var recording = false
    static var isRecordingShortcut: Bool {
        guard NSApp.isActive, let recorder = NSApp.keyWindow?.firstResponder as? ShortcutRecorderView else { return false }
        return recorder.recording
    }
    /// 클릭으로 포커스를 받은 경우에만 녹화를 시작한다(창이 열리며 자동으로 첫 응답자가 될 때는 녹화 안 함).
    private var clickArmed = false
    private let label = NSTextField(labelWithString: "")

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Record shortcut"))
        refresh()
    }

    override func accessibilityPerformPress() -> Bool {
        clickArmed = true
        window?.makeFirstResponder(self)
        recording = true
        refresh()
        return true
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// 외부에서 값 갱신(기본값 복원 등).
    func setHotkey(_ hk: Hotkey) {
        hotkey = hk
        refresh()
    }

    private func refresh() {
        if recording {
            label.stringValue = String(localized: "Press a key combination…")
            label.textColor = .secondaryLabelColor
            layer?.borderColor = Brand.accent.cgColor
            layer?.backgroundColor = Brand.accent.withAlphaComponent(0.08).cgColor
        } else {
            label.stringValue = hotkey.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        recording = clickArmed
        clickArmed = false
        refresh()
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refresh()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        clickArmed = true
        if window?.firstResponder === self {
            // 이미 포커스가 있으면(자동 첫 응답자) 다시 만들어 녹화 상태로 전환.
            recording = true
            clickArmed = false
            refresh()
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !recording, event.keyCode == 49 || event.keyCode == 36 {
            _ = accessibilityPerformPress()
            return
        }
        guard recording else { super.keyDown(with: event); return }
        // 수정키 없는 Esc → 녹화 취소.
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        let hk = Hotkey.from(event: event)
        if let err = hk.validationError {
            onError?(err)
            return   // 녹화 상태 유지 — 다른 조합을 다시 시도할 수 있게.
        }
        onError?("")
        onChange?(hk)
        window?.makeFirstResponder(nil) // The binding is the source of truth when validation rejects a shortcut.
    }
}
