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
                .tabItem { Label("일반", systemImage: "switch.2") }
                .tag(Tab.general)
            GridTab(store: store)
                .tabItem { Label("그리드", systemImage: "rectangle.split.3x3") }
                .tag(Tab.grid)
            HotkeyTab(store: store)
                .tabItem { Label("단축키", systemImage: "keyboard") }
                .tag(Tab.hotkey)
            PresetsTab(store: store)
                .tabItem { Label("창 크기", systemImage: "arrow.up.left.and.arrow.down.right") }
                .tag(Tab.presets)
            ExclusionTab(store: store)
                .tabItem { Label("예외 앱", systemImage: "app.badge.checkmark") }
                .tag(Tab.exclusion)
            AboutTab(store: store)
                .tabItem { Label("정보", systemImage: "info.circle") }
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
                Toggle("그리드 제스처", isOn: $store.enabled)
                Text("창을 드래그하는 도중 오른쪽 버튼을 한 번 클릭하면 그리드가 켜집니다. 다시 우클릭하거나 Esc 로 취소합니다.")
                    .settingsCaption()
                Toggle("가장자리 절반 스냅", isOn: $store.edgeSnap)
                Text("창을 화면 좌·우·아래 끝으로 끌면 절반, 위 끝으로 끌면 최대화됩니다.")
                    .settingsCaption()
            }
            Section {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }))
                Text(store.launchAtLoginMessage).settingsCaption()
            }
            Section("권한") {
                HStack(spacing: 10) {
                    Image(systemName: store.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.permissionGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("손쉬운 사용")
                        Text(store.permissionGranted
                             ? "허용됨 — 창을 옮길 수 있습니다."
                             : "권한이 없어 창을 옮길 수 없습니다.")
                            .settingsCaption()
                    }
                    Spacer()
                    Button(store.permissionGranted ? "설정 열기…" : "권한 요청…") {
                        if store.permissionGranted {
                            AccessibilityPermission.openSystemSettings()
                        } else {
                            AccessibilityPermission.requestAndOpenSettings()
                        }
                    }
                }
                HStack {
                    Text("처음 쓰는 방법을 다시 보려면")
                        .settingsCaption()
                    Spacer()
                    Button("시작 가이드…") { store.openOnboarding?() }
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
            Section("칸 수") {
                Stepper(value: $store.columns, in: 1...24) {
                    LabeledContent("열 (가로)") { Text("\(store.columns)").monospacedDigit() }
                }
                Stepper(value: $store.rows, in: 1...24) {
                    LabeledContent("행 (세로)") { Text("\(store.rows)").monospacedDigit() }
                }
            }
            Section("여백") {
                LabeledContent {
                    HStack {
                        Slider(value: $store.outerMargin, in: 0...48, step: 1)
                        Text("\(Int(store.outerMargin)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("화면 가장자리")
                }
                LabeledContent {
                    HStack {
                        Slider(value: $store.innerGap, in: 0...32, step: 1)
                        Text("\(Int(store.innerGap)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("창 사이")
                }
                Text("가장자리 여백은 화면 끝에 닿는 변에만, 창 사이 간격은 모든 변에 적용됩니다. 가장자리 절반 스냅에도 같은 값이 쓰입니다.")
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
            Section("그리드 단축키") {
                HStack {
                    Text("창 드래그 중 입력")
                    Spacer()
                    ShortcutRecorder(hotkey: $store.hotkey, error: $store.hotkeyError)
                        .frame(width: 150, height: 24)
                    Button("기본값") { store.resetHotkey() }
                        .disabled(store.hotkey == .default)
                }
                if !store.hotkeyError.isEmpty {
                    Text(store.hotkeyError).font(.system(size: 11)).foregroundStyle(.red)
                }
                Text("트랙패드처럼 드래그 중 우클릭이 어려울 때, 창을 드래그하는 도중 이 조합을 누르면 우클릭과 똑같이 그리드가 켜집니다. macOS 시스템·앱 기본 단축키(⌘Space, ⇧⌘4, ⌘C 등)는 지정할 수 없습니다.")
                    .settingsCaption()
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
                        TextField("이름 (선택)", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("너비", value: $preset.width, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Text("×").foregroundStyle(.secondary)
                        TextField("높이", value: $preset.height, format: .number.grouping(.never))
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
                        Text("사용자 지정 크기가 없습니다")
                            .foregroundStyle(.secondary)
                        Text("아래에서 추가하면 메뉴 막대 → 창 크기 고정 에 “사용자 지정” 섹션으로 나타납니다.")
                            .settingsCaption()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button { store.addPreset() } label: { Image(systemName: "plus") }
                    .help("새 크기 추가 (1280 × 800)")
                Button {
                    store.removePresets(ids: selection)
                    selection.removeAll()
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("선택 제거")
                Divider().frame(height: 18)
                Button {
                    store.capturePresetFromWindow()
                } label: {
                    Label("창 클릭으로 가져오기", systemImage: "scope")
                }
                .help("다음에 클릭하는 창의 현재 크기를 프리셋으로 추가합니다")
                Spacer()
                Text("영상·App Store 기본 프리셋은 메뉴에 항상 표시됩니다.")
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
                        Text("예외 앱이 없습니다").foregroundStyle(.secondary)
                        Text("게임처럼 드래그·우클릭을 직접 쓰는 앱을 여기 넣으면, 그 앱이 맨 앞일 때는 그리드와 가장자리 스냅이 개입하지 않습니다. 앱을 이 창으로 끌어다 놓아도 됩니다.")
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
                    .help("Applications 에서 앱 선택…")
                Button {
                    store.removeExcludedApps(selection)
                    selection.removeAll()
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("선택 제거")
                Divider().frame(height: 18)
                Menu {
                    let apps = SettingsStore.runningApps().filter { !store.excludedApps.contains($0.bundleID) }
                    if apps.isEmpty {
                        Text("추가할 실행 중인 앱이 없습니다")
                    }
                    ForEach(apps, id: \.bundleID) { app in
                        Button(app.name) { store.addExcludedApp(bundleID: app.bundleID) }
                    }
                } label: {
                    Label("실행 중인 앱에서", systemImage: "macwindow.on.rectangle")
                }
                .fixedSize()
                Spacer()
            }
            .padding(10)
        }
    }

    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "그리드를 끌 앱 선택"
        panel.message = "이 앱이 맨 앞일 때는 그리드·가장자리 스냅이 동작하지 않습니다."
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
                Text("버전 \(SettingsStore.versionString)").foregroundStyle(.secondary).monospacedDigit()
                Text(Brand.tagline).settingsCaption()
            }
            Button("업데이트 확인…") { store.checkForUpdates?() }
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/Canine89/oh-my-grid")!)
                Link("문의하기", destination: URL(string: "mailto:hgpark@goldenrabbit.co.kr")!)
                Link("변경 이력", destination: URL(string: "https://github.com/Canine89/oh-my-grid/blob/main/CHANGELOG.md")!)
            }
            .font(.system(size: 12))
            Spacer()
            Text("© 2026 Golden Rabbit · 무료 / 오픈소스")
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
