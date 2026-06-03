import AppKit

/// 그리드 크기·활성 설정 + 접근성 권한 상태를 보여주는 환경설정 창.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    private let enabledCheck = NSButton(checkboxWithTitle: "그리드 제스처 활성화", target: nil, action: nil)
    private let edgeSnapCheck = NSButton(checkboxWithTitle: "가장자리 절반 스냅 (창을 화면 끝으로 드래그)", target: nil, action: nil)
    private let colsField = NSTextField()
    private let colsStepper = NSStepper()
    private let rowsField = NSTextField()
    private let rowsStepper = NSStepper()
    private let permissionLabel = NSTextField(labelWithString: "")

    func showWindow() {
        if window == nil { build() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "\(Brand.name) 설정"
        win.delegate = self
        win.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 활성 토글
        enabledCheck.target = self
        enabledCheck.action = #selector(toggleEnabled)
        stack.addArrangedSubview(enabledCheck)

        // 가장자리 절반 스냅 토글
        edgeSnapCheck.target = self
        edgeSnapCheck.action = #selector(toggleEdgeSnap)
        stack.addArrangedSubview(edgeSnapCheck)

        // 열
        stack.addArrangedSubview(makeStepperRow(title: "열 (가로 칸 수)",
                                                field: colsField, stepper: colsStepper,
                                                action: #selector(colsChanged)))
        // 행
        stack.addArrangedSubview(makeStepperRow(title: "행 (세로 칸 수)",
                                                field: rowsField, stepper: rowsStepper,
                                                action: #selector(rowsChanged)))

        // 권한 상태
        permissionLabel.font = .systemFont(ofSize: 11)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 2
        permissionLabel.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(permissionLabel)

        let permBtn = NSButton(title: "손쉬운 사용 설정 열기…", target: self,
                               action: #selector(openAccessibility))
        permBtn.bezelStyle = .rounded
        stack.addArrangedSubview(permBtn)

        let hint = NSTextField(wrappingLabelWithString:
            "사용법: 창을 드래그하는 도중 오른쪽 버튼을 한 번 클릭하면 그리드가 켜집니다. 그대로 셀을 가로질러 움직인 뒤 왼쪽 버튼을 놓으면 창이 스냅됩니다. (다시 우클릭하거나 Esc로 취소)\n가장자리 스냅: 창을 화면 좌·우·아래 끝으로 끌면 절반, 위 끝으로 끌면 최대화됩니다.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(hint)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        win.contentView = content
        window = win
    }

    private func makeStepperRow(title: String, field: NSTextField, stepper: NSStepper, action: Selector) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        field.alignment = .right
        field.isEditable = true
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true

        stepper.minValue = 1
        stepper.maxValue = 24
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action

        let row = NSStackView(views: [label, field, stepper])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 340).isActive = true
        return row
    }

    private func refresh() {
        enabledCheck.state = Settings.shared.enabled ? .on : .off
        edgeSnapCheck.state = Settings.shared.edgeSnapEnabled ? .on : .off
        colsField.integerValue = Settings.shared.columns
        colsStepper.integerValue = Settings.shared.columns
        rowsField.integerValue = Settings.shared.rows
        rowsStepper.integerValue = Settings.shared.rows
        if AccessibilityPermission.isGranted {
            permissionLabel.stringValue = "✅ 손쉬운 사용 권한 허용됨 — 창을 옮길 수 있습니다."
        } else {
            permissionLabel.stringValue = "⚠️ 손쉬운 사용 권한이 없어 창을 옮길 수 없습니다. 아래 버튼으로 허용한 뒤 앱을 다시 실행하세요."
        }
    }

    @objc private func toggleEnabled() {
        Settings.shared.enabled = (enabledCheck.state == .on)
        notifyChanged()
    }

    @objc private func toggleEdgeSnap() {
        Settings.shared.edgeSnapEnabled = (edgeSnapCheck.state == .on)
        notifyChanged()
    }

    @objc private func colsChanged(_ sender: NSControl) {
        let v = sender.integerValue
        Settings.shared.columns = v
        colsField.integerValue = Settings.shared.columns
        colsStepper.integerValue = Settings.shared.columns
        notifyChanged()
    }

    @objc private func rowsChanged(_ sender: NSControl) {
        let v = sender.integerValue
        Settings.shared.rows = v
        rowsField.integerValue = Settings.shared.rows
        rowsStepper.integerValue = Settings.shared.rows
        notifyChanged()
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.openSystemSettings()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .gridSettingsChanged, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 닫을 때 권한 상태를 다시 반영할 수 있게 참조 유지(release 안 함).
    }
}
