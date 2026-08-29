import SwiftUI
import UniformTypeIdentifiers

/// 설정 창 본문. 탭: 일반 / 그리드 / 단축키 / 창 크기 / 예외 앱 / 정보.
struct SettingsView: View {
    enum Tab: Hashable { case general, grid, hotkey, presets, exclusion, about }

    @ObservedObject var store: SettingsStore
    @State private var tab: Tab

    init(store: SettingsStore, initialTab: Tab = .general) {
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "switch.2") }
                .tag(Tab.general)
            GridTab(store: store)
                .tabItem { Label("Grid", systemImage: "rectangle.split.3x3") }
                .tag(Tab.grid)
            HotkeyTab(store: store)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.hotkey)
            PresetsTab(store: store)
                .tabItem { Label("Sizes", systemImage: "arrow.up.left.and.arrow.down.right") }
                .tag(Tab.presets)
            ExclusionTab(store: store)
                .tabItem { Label("Excluded Apps", systemImage: "app.badge.checkmark") }
                .tag(Tab.exclusion)
            AboutTab(store: store)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - 일반

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Grid Gesture", isOn: $store.enabled)
                Text("Click the right button once while dragging a window to turn on the grid. Right-click again or press Esc to cancel.")
                    .settingsCaption()
                Toggle("Edge Snapping", isOn: $store.edgeSnap)
                Text("Drag a window to the left, right, or bottom edge for a half; to the top edge to maximize.")
                    .settingsCaption()
            }
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }))
                Text(store.launchAtLoginMessage).settingsCaption()
            }
            Section("Permission") {
                HStack(spacing: 10) {
                    Image(systemName: store.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.permissionGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                        (store.permissionGranted
                             ? Text("Granted — windows can be moved.")
                             : Text("Not granted — windows can’t be moved."))
                            .settingsCaption()
                    }
                    Spacer()
                    if store.permissionGranted {
                        Button("Open Settings…") { AccessibilityPermission.openSystemSettings() }
                    } else {
                        Button("Request Permission…") { AccessibilityPermission.requestAndOpenSettings() }
                    }
                }
                HStack {
                    Text("See the first-run walkthrough again")
                        .settingsCaption()
                    Spacer()
                    Button("Getting Started…") { store.openOnboarding?() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 그리드

private struct GridTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                GridPreview(columns: store.columns, rows: store.rows,
                            outerMargin: store.outerMargin, innerGap: store.innerGap)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section("Cells") {
                Stepper(value: $store.columns, in: 1...24) {
                    LabeledContent("Columns") { Text("\(store.columns)").monospacedDigit() }
                }
                Stepper(value: $store.rows, in: 1...24) {
                    LabeledContent("Rows") { Text("\(store.rows)").monospacedDigit() }
                }
            }
            Section("Gaps") {
                LabeledContent {
                    HStack {
                        Slider(value: $store.outerMargin, in: 0...48, step: 1)
                        Text("\(Int(store.outerMargin)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Screen edges")
                }
                LabeledContent {
                    HStack {
                        Slider(value: $store.innerGap, in: 0...32, step: 1)
                        Text("\(Int(store.innerGap)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Between windows")
                }
                Text("The edge gap applies only to sides touching the screen edge; the window gap applies to all sides. Edge and keyboard snapping use the same values.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

/// 현재 열·행·여백을 반영한 축소판 화면. 3×2 블록이 선택된 예시를 보여준다.
private struct GridPreview: View {
    let columns: Int
    let rows: Int
    let outerMargin: Double
    let innerGap: Double

    var body: some View {
        let accent = Color(nsColor: Brand.accent)
        GeometryReader { geo in
            // 주 화면 비율로 축소(없으면 16:10).
            let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            let scale = min(geo.size.width / screen.width, geo.size.height / screen.height)
            let w = screen.width * scale, h = screen.height * scale
            let cw = w / CGFloat(columns), ch = h / CGFloat(rows)
            let selCols = min(3, columns), selRows = min(2, rows)
            let c0 = min(1, columns - selCols), r0 = min(1, rows - selRows)
            let sel = selectionRect(c0: c0, r0: r0, selCols: selCols, selRows: selRows,
                                    cw: cw, ch: ch, scale: scale)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.3)))
                Path { p in
                    for c in 1..<max(columns, 1) {
                        p.move(to: CGPoint(x: cw * CGFloat(c), y: 0)); p.addLine(to: CGPoint(x: cw * CGFloat(c), y: h))
                    }
                    for r in 1..<max(rows, 1) {
                        p.move(to: CGPoint(x: 0, y: ch * CGFloat(r))); p.addLine(to: CGPoint(x: w, y: ch * CGFloat(r)))
                    }
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(accent, lineWidth: 1.5))
                    .frame(width: max(sel.width, 2), height: max(sel.height, 2))
                    .offset(x: sel.minX, y: sel.minY)
                Text("\(selCols) × \(selRows)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: Brand.labelBackground)))
                    .position(x: sel.midX, y: sel.midY)
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.easeOut(duration: 0.15), value: columns)
            .animation(.easeOut(duration: 0.15), value: rows)
        }
    }

    /// 선택 블록(여백 적용 전) → 여백 적용: 화면 끝에 닿는 변만 바깥 여백, 모든 변 안쪽 간격.
    /// (`GridSessionController.applyGaps`와 같은 규칙)
    private func selectionRect(c0: Int, r0: Int, selCols: Int, selRows: Int,
                               cw: CGFloat, ch: CGFloat, scale: CGFloat) -> CGRect {
        var sel = CGRect(x: cw * CGFloat(c0), y: ch * CGFloat(r0),
                         width: cw * CGFloat(selCols), height: ch * CGFloat(selRows))
        let m = outerMargin * scale, g = innerGap * scale
        sel = sel.insetBy(dx: g, dy: g)
        if c0 == 0 { sel.origin.x += m; sel.size.width -= m }
        if c0 + selCols == columns { sel.size.width -= m }
        if r0 == 0 { sel.origin.y += m; sel.size.height -= m }
        if r0 + selRows == rows { sel.size.height -= m }
        return sel
    }
}

// MARK: - 단축키

private struct HotkeyTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Grid Shortcut") {
                HStack {
                    Text("Press while dragging a window")
                    Spacer()
                    ShortcutRecorder(hotkey: $store.hotkey, error: $store.hotkeyError)
                        .frame(width: 150, height: 24)
                    Button("Default") { store.resetHotkey() }
                        .disabled(store.hotkey == .default)
                }
                if !store.hotkeyError.isEmpty {
                    Text(store.hotkeyError).font(.system(size: 11)).foregroundStyle(.red)
                }
                Text("When a right-click while dragging is awkward (trackpads), press this combination while dragging to turn on the grid. macOS system and standard app shortcuts (⌘Space, ⇧⌘4, ⌘C…) can’t be assigned.")
                    .settingsCaption()
            }
            Section {
                Toggle("Keyboard Snapping", isOn: $store.keyboardSnapEnabled)
                Text("Move the frontmost window without the mouse — halves with arrows, quarters with U/I/J/K, ⌃⌥↩ to maximize, ⌃⌥C to center.")
                    .settingsCaption()
            }
            Section {
                ForEach(SnapAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(hotkey: Binding(
                            get: { store.snapHotkey(for: action) },
                            set: { store.setSnapHotkey($0, for: action) }),
                                         error: $store.snapHotkeyError)
                            .frame(width: 150, height: 24)
                    }
                    .disabled(!store.keyboardSnapEnabled)
                }
                if !store.snapHotkeyError.isEmpty {
                    Text(store.snapHotkeyError).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Reset All") { store.resetSnapHotkeys() }
                        .disabled(store.snapHotkeys.isEmpty)
                }
            } header: {
                Text("Snap Shortcuts")
            }
        }
        .formStyle(.grouped)
    }
}

/// AppKit `ShortcutRecorderView`를 SwiftUI 에서 쓰기 위한 래퍼.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    @Binding var error: String

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let v = ShortcutRecorderView(hotkey: hotkey)
        v.onChange = { hotkey = $0 }
        v.onError = { error = $0 }
        return v
    }

    func updateNSView(_ v: ShortcutRecorderView, context: Context) {
        v.setHotkey(hotkey)
    }
}

// MARK: - 창 크기 프리셋

private struct PresetsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($store.customPresets) { $preset in
                    HStack(spacing: 8) {
                        TextField("Name (optional)", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Width", value: $preset.width, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Text("×").foregroundStyle(.secondary)
                        TextField("Height", value: $preset.height, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                    }
                    .tag(preset.id)
                }
                .onMove { store.customPresets.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if store.customPresets.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("No custom sizes")
                            .foregroundStyle(.secondary)
                        Text("Sizes you add here appear under “Custom” in the menu bar → Resize Window.")
                            .settingsCaption()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button { store.addPreset() } label: { Image(systemName: "plus") }
                    .help("Add a size (1280 × 800)")
                Button {
                    store.removePresets(ids: selection)
                    selection.removeAll()
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("Remove selected")
                Divider().frame(height: 18)
                Button {
                    store.capturePresetFromWindow()
                } label: {
                    Label("Capture from Window", systemImage: "scope")
                }
                .help("Adds the current size of the next window you click")
                Spacer()
                Text("Built-in video and App Store sizes are always in the menu.")
                    .settingsCaption()
            }
            .padding(10)
        }
    }
}

// MARK: - 예외 앱

private struct ExclusionTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: Set<String> = []
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            List(store.excludedApps, id: \.self, selection: $selection) { id in
                HStack(spacing: 10) {
                    Image(nsImage: SettingsStore.appIcon(forBundleID: id))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SettingsStore.appName(forBundleID: id))
                        Text(id).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if store.excludedApps.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("No excluded apps").foregroundStyle(.secondary)
                        Text("Add apps that use drag and right-click themselves (games, etc.). While they’re frontmost, grid and edge snapping stay out of the way. You can also drop apps onto this window.")
                            .settingsCaption()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                }
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: Brand.accent), lineWidth: 2)
                        .padding(4)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, url.pathExtension == "app" else { return }
                        DispatchQueue.main.async { store.addExcludedApps(urls: [url]) }
                    }
                }
                return true
            }
            Divider()
            HStack(spacing: 8) {
                Button { addViaPanel() } label: { Image(systemName: "plus") }
                    .help("Choose from Applications…")
                Button {
                    store.removeExcludedApps(selection)
                    selection.removeAll()
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("Remove selected")
                Divider().frame(height: 18)
                Menu {
                    let apps = SettingsStore.runningApps().filter { !store.excludedApps.contains($0.bundleID) }
                    if apps.isEmpty {
                        Text("No running apps to add")
                    }
                    ForEach(apps, id: \.bundleID) { app in
                        Button(app.name) { store.addExcludedApp(bundleID: app.bundleID) }
                    }
                } label: {
                    Label("From Running Apps", systemImage: "macwindow.on.rectangle")
                }
                .fixedSize()
                Spacer()
            }
            .padding(10)
        }
    }

    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose apps to exclude")
        panel.message = String(localized: "Grid and edge snapping are disabled while these apps are frontmost.")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        store.addExcludedApps(urls: panel.urls)
    }
}

// MARK: - 정보

private struct AboutTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text(Brand.name).font(.system(size: 22, weight: .bold))
                Text("Version \(SettingsStore.versionString)").foregroundStyle(.secondary).monospacedDigit()
                Text(Brand.tagline).settingsCaption()
            }
            Button("Check for Updates…") { store.checkForUpdates?() }
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/Canine89/oh-my-grid")!)
                Link("Contact", destination: URL(string: "mailto:hgpark@goldenrabbit.co.kr")!)
                Link("Changelog", destination: URL(string: "https://github.com/Canine89/oh-my-grid/blob/main/CHANGELOG.md")!)
            }
            .font(.system(size: 12))
            Spacer()
            Text("© 2026 Golden Rabbit · Free & open source")
                .settingsCaption()
        }
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 공통

private extension View {
    func settingsCaption() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
