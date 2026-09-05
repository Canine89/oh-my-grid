import SwiftUI

/// 첫 실행 온보딩: 언어 → 권한 → 제스처 연습 → 마무리 설정.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    private let accent = Color(nsColor: Brand.accent)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch model.page {
                    case .language: LanguagePage(model: model)
                    case .permission: PermissionPage(model: model)
                    case .practice: PracticePage(model: model)
                    case .finish: FinishPage(model: model)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 28)
                .padding(.bottom, 16)
                .transition(.opacity)
                .id(model.page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 520, minHeight: 440)
        .animation(.easeInOut(duration: 0.2), value: model.page)
    }

    private var footer: some View {
        HStack {
            pageDots
            Spacer()
            if model.page == .language {
                EmptyView()
            } else if model.page == .permission {
                Button("Back") { model.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Skip") { model.next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            } else if model.page == .practice {
                Button("Back") { model.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                if !model.snapSucceeded {
                    Button("Skip") { model.next() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            } else {
                Button("Back") { model.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            primaryButton
                .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.page {
        case .language:
            Button("Continue") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .permission:
            Button("Next") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.permissionGranted)
        case .practice:
            Button("Next") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.snapSucceeded)
        case .finish:
            Button("Get Started") { model.onFinish?() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Page.allCases, id: \.rawValue) { p in
                Circle()
                    .fill(p == model.page ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - 공통 조각

private struct PageHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color(nsColor: Brand.accent))
                .frame(height: 56)
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey
    var done = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color(nsColor: Brand.accent))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusPill: View {
    let ok: Bool
    let okText: LocalizedStringKey
    let waitingText: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
            }
            (ok ? Text(okText) : Text(waitingText))
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
        .animation(.easeInOut(duration: 0.2), value: ok)
    }
}

// MARK: - 0. 언어

/// 첫 화면. 영어가 기본이라 영어로 시작하고, 한국어 카드를 누르면 이 가이드부터 즉시 한국어로 바뀐다.
private struct LanguagePage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(symbol: "globe",
                       title: "Welcome to \(Brand.name)",
                       subtitle: "Choose the language for the menu bar, settings, and this guide. You can change it anytime in Settings → General.")

            HStack(spacing: 14) {
                ForEach(AppLanguage.allCases) { lang in
                    LanguageCard(language: lang, selected: model.language == lang) {
                        model.language = lang
                    }
                }
            }

            Text("Prefer Korean? Pick 한국어 — this guide switches right away.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
    }
}

private struct LanguageCard: View {
    let language: AppLanguage
    let selected: Bool
    let action: () -> Void

    private var accent: Color { Color(nsColor: Brand.accent) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.5))
                Text(verbatim: language.nativeName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 170, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? accent : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

// MARK: - 1. 권한

private struct PermissionPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(symbol: "lock.shield",
                       title: "Accessibility Permission Needed",
                       subtitle: "Used to move other apps’ windows and read the gesture while you drag.\nNo screen recording is used.")

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Open the Accessibility list in System Settings with the button below.")
                StepRow(number: 2, text: "Turn on the oh-my-grid switch in the list.")
                Text("If the app is missing, use + to add this app from Applications.")
                    .font(.callout).foregroundStyle(.secondary)
                StepRow(number: 3, text: "Come back to this window — it moves on automatically.", done: model.permissionGranted)
            }
            .frame(maxWidth: 400, alignment: .leading)

            Button {
                model.onOpenPermission?()
            } label: {
                Label("Open System Settings", systemImage: "gearshape")
            }
            .controlSize(.large)

            StatusPill(ok: model.permissionGranted, okText: "Granted", waitingText: "Waiting for permission…")
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 2. 연습

private struct PracticePage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            MiniGridIllustration(succeeded: model.snapSucceeded)
                .frame(width: 220, height: 130)

            VStack(spacing: 6) {
                (model.snapSucceeded ? Text("Success! The window snapped to the grid") : Text("Practice with this window"))
                    .font(.system(size: 22, weight: .bold))
                (model.snapSucceeded
                     ? Text("You can now place any app’s window the same way.")
                     : Text("Drag the title bar, then click the right button once to turn on the grid."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.snapSucceeded {
                VStack(alignment: .leading, spacing: 10) {
                    StepRow(number: 1, text: "Grab this window’s title bar with the left button and start dragging.")
                    StepRow(number: 2, text: "While dragging, click the right button once. (No need to hold it.)")
                    StepRow(number: 3, text: "Move until the blue block covers the cells you want, then release the left button.")
                }
                .frame(maxWidth: 420, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left")
                    Text("On a trackpad, press **\(model.hotkeyDisplay)** while dragging. Esc cancels.")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 6×4 그리드에 3×2 블록이 선택된 모습의 축소판. 성공 시 초록으로 바뀐다.
private struct MiniGridIllustration: View {
    let succeeded: Bool
    @State private var pulse = false

    var body: some View {
        let cols = 6, rows = 4
        let color = succeeded ? Color.green : Color(nsColor: Brand.accent)
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25)))
                // 셀 선
                Path { p in
                    for c in 1..<cols {
                        p.move(to: CGPoint(x: cw * CGFloat(c), y: 0))
                        p.addLine(to: CGPoint(x: cw * CGFloat(c), y: geo.size.height))
                    }
                    for r in 1..<rows {
                        p.move(to: CGPoint(x: 0, y: ch * CGFloat(r)))
                        p.addLine(to: CGPoint(x: geo.size.width, y: ch * CGFloat(r)))
                    }
                }
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                // 선택 블록 (col 1..3, row 1..2)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(color, lineWidth: 2))
                    .frame(width: cw * 3, height: ch * 2)
                    .offset(x: cw * 1, y: ch * 1)
                    .shadow(color: color.opacity(pulse ? 0.55 : 0.2), radius: pulse ? 12 : 4)
                    .scaleEffect(succeeded ? 1.0 : (pulse ? 1.02 : 1.0))
                // 커서
                if !succeeded {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .offset(x: cw * 3.5, y: ch * 2.4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white, .green)
                        .offset(x: cw * 2.5 - 13, y: ch * 2 - 13)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: succeeded)
    }
}

// MARK: - 3. 마무리

private struct FinishPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(symbol: "checkmark.seal",
                       title: "You’re All Set",
                       subtitle: "Pick the options you use most. You can change them anytime in the menu bar → Settings…")

            Form {
                Toggle("Launch at Login", isOn: $model.launchAtLogin)
                Toggle("Edge Snapping (drag a window to a screen edge)", isOn: $model.edgeSnap)
                Picker("Grid Size", selection: $model.gridPreset) {
                    ForEach(OnboardingModel.GridPreset.allCases) { p in
                        Text(p.label).tag(Optional(p))
                    }
                    if model.gridPreset == nil {
                        Text("Current (\(model.currentGridLabel))").tag(Optional<OnboardingModel.GridPreset>.none)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 440)

            if let err = model.launchAtLoginError {
                Text("⚠️ Couldn’t change login item: \(err)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
    }
}
