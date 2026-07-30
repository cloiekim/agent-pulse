import SwiftUI

/// 행 오른쪽에 붙는 알약. 상태에 따라 두 가지 성격을 가집니다.
///
/// - `Approve` / `Retry` — 누를 수 있는 **버튼** (accent 또는 subtle)
/// - `Running` / `Waiting` / `Done` — 읽기 전용 **상태 표시** (color-muted 배경)
///
/// 색만으로 의미를 싣지 않도록 항상 텍스트를 함께 둡니다.
struct StatusPill: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    // ⚠️ Environment 로 받으면 안 됩니다 — 팝오버는 뜰 때의 environment 를
    //    붙들고 있어서, 언어를 바꿔도 이미 열려 있는 화면에 반영되지 않습니다.
    private var loc: Loc { AppSettings.shared.loc }

    let state: SessionState
    var action: (() -> Void)?

    var body: some View {
        // ⚠️ 예전엔 승인 대기·실패일 때만 누를 수 있었습니다.
        //    그런데 실행 중인 작업이야말로 "지금 어떻게 돼가나" 보러 가고 싶은
        //    대상입니다. 알약은 전부 누르면 해당 창으로 갑니다.
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if state == .running {
                // 맥동하는 점 — "지금 살아 있다"는 유일한 신호.
                PulsingDot(color: theme.runningDot)
            }
            Text(state.pillLabel(loc))
                .font(Theme.supporting(state.hasPrimaryAction ? .semibold : .medium))

            // ⚠️ 화살표는 **동작하는 알약에만** 붙입니다.
            //    `Running`·`Done` 도 눌리긴 하지만 읽히는 성격이 상태 표시라,
            //    거기까지 붙이면 "전부 버튼" 처럼 보여서 오히려 위계가 사라집니다.
            if state.hasPrimaryAction {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, state.hasPrimaryAction ? 12 : 10)
        .padding(.vertical, state.hasPrimaryAction ? 5 : 3)
        .background(background, in: Capsule())
        .fixedSize()
    }

    private var background: Color {
        switch state {
        case .needsApproval:            theme.accentBg   // 가장 급한 것만 accent
        case .failed, .waitingInput:    theme.subtleBg
        case .running:                  theme.runningBg
        case .completed:                theme.doneBg
        case .queued, .idle:            theme.neutralPillBg
        }
    }

    private var foreground: Color {
        switch state {
        case .needsApproval:            theme.accentFg
        case .failed, .waitingInput:    theme.subtleFg
        case .running:                  theme.runningFg
        case .completed:                theme.doneFg
        case .queued, .idle:            theme.neutralPillFg
        }
    }
}

/// 1.6초 주기로 옅어졌다 진해지는 5px 점. 디자인의 `@keyframes pulse`.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 5

    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dim ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

/// 헤더의 요약 칩 — "3 running", "1 needs you".
struct CountChip: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    // ⚠️ Environment 로 받으면 안 됩니다 — 팝오버는 뜰 때의 environment 를
    //    붙들고 있어서, 언어를 바꿔도 이미 열려 있는 화면에 반영되지 않습니다.
    private var loc: Loc { AppSettings.shared.loc }

    enum Kind { case running, needsYou }
    let kind: Kind
    let count: Int

    var body: some View {
        // ⚠️ 형태를 메뉴바·알약과 똑같이 맞춥니다: `단어` + 개수.
        //
        //    예전엔 칩만 `1 running` 이라 숫자가 앞에 오고 소문자로 시작했습니다.
        //    바로 옆 알약은 `Running` 이라 나란히 놓고 보면 어긋나 보입니다.
        //    영어 문법상으론 둘 다 맞지만, **한 화면에서 같은 것을 두 가지로 쓰면**
        //    사용자는 다른 뜻인가 하고 한 번 더 생각하게 됩니다.
        Text(kind == .running
             ? loc("Running \(count)", "실행 중 \(count)")
             : loc("Needs you \(count)", "확인 필요 \(count)"))
            .font(Theme.supporting(.medium))
            .foregroundStyle(kind == .running ? theme.runningFg : theme.attentionFg)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(kind == .running ? theme.runningBg : theme.attentionBg, in: Capsule())
            .fixedSize()
    }
}
