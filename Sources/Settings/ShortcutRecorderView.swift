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
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// 외부에서 값 갱신(기본값 복원 등).
    func setHotkey(_ hk: Hotkey) {
        hotkey = hk
        refresh()
    }

    private func refresh() {
        if recording {
            label.stringValue = "키 조합을 누르세요…"
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
        recording = true
        refresh()
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refresh()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
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
        hotkey = hk
        window?.makeFirstResponder(nil)   // 녹화 종료(refresh는 resignFirstResponder에서)
        onChange?(hk)
        onError?("")
    }
}
