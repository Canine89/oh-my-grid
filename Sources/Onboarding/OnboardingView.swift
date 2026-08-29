import SwiftUI

/// 첫 실행 온보딩: 권한 → 제스처 연습 → 마무리 설정.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    private let accent = Color(nsColor: Brand.accent)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case .permission: PermissionPage(model: model)
                case .practice: PracticePage(model: model)
                case .finish: FinishPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .transition(.opacity)
            .id(model.page)

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
            if model.page == .permission {
                Button("건너뛰기") { model.next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else if model.page == .practice {
                Button("뒤로") { model.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                if !model.snapSucceeded {
                    Button("건너뛰기") { model.next() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            } else {
                Button("뒤로") { model.back() }
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
        case .permission:
            Button("다음") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.permissionGranted)
        case .practice:
            Button("다음") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.snapSucceeded)
        case .finish:
            Button("시작하기") { model.onFinish?() }
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
    let title: String
    let subtitle: String

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
    let text: String
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
    let okText: String
    let waitingText: String

    var body: some View {
        HStack(spacing: 8) {
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(ok ? okText : waitingText)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
        .animation(.easeInOut(duration: 0.2), value: ok)
    }
}

// MARK: - 1. 권한

private struct PermissionPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(symbol: "lock.shield",
                       title: "손쉬운 사용 권한이 필요합니다",
                       subtitle: "다른 앱의 창을 옮기고 드래그 중 제스처를 읽는 데 씁니다.\n화면 녹화·파일 접근 권한은 사용하지 않습니다.")

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "아래 버튼으로 시스템 설정의 손쉬운 사용 목록을 엽니다.")
                StepRow(number: 2, text: "목록에서 oh-my-grid 스위치를 켭니다.")
                StepRow(number: 3, text: "이 창으로 돌아오면 자동으로 다음 단계로 넘어갑니다.", done: model.permissionGranted)
            }
            .frame(maxWidth: 400, alignment: .leading)

            Button {
                model.onOpenPermission?()
            } label: {
                Label("시스템 설정 열기", systemImage: "gearshape")
            }
            .controlSize(.large)

            StatusPill(ok: model.permissionGranted, okText: "허용됨", waitingText: "권한을 기다리는 중…")
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
                Text(model.snapSucceeded ? "성공! 창이 그리드에 맞춰졌습니다" : "이 창으로 연습해 보세요")
                    .font(.system(size: 22, weight: .bold))
                Text(model.snapSucceeded
                     ? "이제 어떤 앱의 창이든 같은 방법으로 배치할 수 있습니다."
                     : "제목 표시줄을 잡고 드래그하다 오른쪽 버튼을 한 번 누르면 그리드가 켜집니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.snapSucceeded {
                VStack(alignment: .leading, spacing: 10) {
                    StepRow(number: 1, text: "이 창의 제목 표시줄을 왼쪽 버튼으로 잡고 드래그를 시작합니다.")
                    StepRow(number: 2, text: "드래그하는 도중 오른쪽 버튼을 한 번 클릭합니다. (계속 누르고 있지 않아도 됩니다)")
                    StepRow(number: 3, text: "파란 블록이 원하는 칸들을 덮도록 움직인 뒤 왼쪽 버튼을 놓습니다.")
                }
                .frame(maxWidth: 420, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left")
                    Text("트랙패드라면 드래그 중 **\(model.hotkeyDisplay)** 를 누르세요. Esc 로 취소합니다.")
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
                       title: "준비됐습니다",
                       subtitle: "자주 쓰는 옵션만 골라 두세요. 언제든 메뉴 막대 → 설정… 에서 바꿀 수 있습니다.")

            Form {
                Toggle("로그인 시 자동 실행", isOn: $model.launchAtLogin)
                Toggle("가장자리 절반 스냅 (창을 화면 끝으로 드래그)", isOn: $model.edgeSnap)
                Picker("그리드 크기", selection: $model.gridPreset) {
                    ForEach(OnboardingModel.GridPreset.allCases) { p in
                        Text(p.label).tag(Optional(p))
                    }
                    if model.gridPreset == nil {
                        Text("현재 (\(model.currentGridLabel))").tag(Optional<OnboardingModel.GridPreset>.none)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 440)

            if let err = model.launchAtLoginError {
                Text("⚠️ 로그인 항목 변경 실패: \(err)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
    }
}
