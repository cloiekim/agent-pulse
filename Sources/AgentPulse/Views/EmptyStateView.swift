import SwiftUI
import AppKit

/// 디자인 5b — 감시 중이지만 아무것도 안 돌고 있을 때.
///
/// ⚠️ 이 화면의 역할이 바뀌었습니다.
///
/// 원래는 "Open ChatGPT ↗" 버튼이 있었는데, **왜 하필 ChatGPT 인지 이유가 없었고**
/// 애초에 "아무것도 안 돌고 있음" 은 고쳐야 할 문제가 아닙니다 — 조용한 게 정상입니다.
///
/// 사용자가 이 화면에서 정말 궁금한 건 하나입니다:
/// **"이게 지금 제대로 보고 있긴 한 건가?"**
/// 그래서 연결 상태 점검표로 바꿨습니다.
struct EmptyStateView: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    // ⚠️ Environment 로 받으면 안 됩니다 — 팝오버는 뜰 때의 environment 를
    //    붙들고 있어서, 언어를 바꿔도 이미 열려 있는 화면에 반영되지 않습니다.
    private var loc: Loc { AppSettings.shared.loc }

    var body: some View {
        VStack(spacing: 12) {
            Text(loc("Nothing running", "돌고 있는 작업 없음"))
                .font(Theme.body(.semibold))
                .foregroundStyle(theme.textPrimary)

            Text(loc("You'll see agents here the moment they start.",
                     "에이전트가 시작되면 바로 여기 나타납니다."))
                .font(Theme.supporting())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(ConnectionStatus.all(loc)) { surface in
                    SurfaceRow(surface: surface)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(theme.subtleBg,
                        in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .padding(.top, 2)

            // ⚠️ 이 한 줄이 반복 질문 다섯 개를 막습니다.
            //
            //    "돌고 있는데 왜 안 떠?" 를 다섯 번 물었고, 매번 답은 같았습니다 —
            //    Cowork(데스크톱 앱) 작업은 클라우드에서 돌아 이 Mac 에 흔적이 없습니다.
            //    앱이 맞게 동작해도 사용자 기대와 어긋나면 그건 앱의 문제입니다.
            //    **감지 못 하는 것을 미리 말해주는 게 정직하고, 결국 더 신뢰를 얻습니다.**
            Text(loc("Tasks in the Claude desktop app aren't shown — they run in the cloud, not on this Mac.",
                     "Claude 데스크톱 앱(Cowork) 작업은 표시되지 않습니다 — 이 Mac 이 아니라 클라우드에서 실행됩니다."))
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }
}

/// 디자인 5c — 첫 실행. 크롬 확장을 아직 설치하지 않았을 때.
///
/// ⚠️ 이 화면은 **세션이 하나도 없을 때만** 나옵니다.
/// 터미널 세션이 잡혀 있으면 목록이 우선입니다 (MenuPanel 참고).
struct OnboardingView: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    /// 건너뛰기. 다시는 이 화면을 안 봅니다.
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            LogoPair()

            Text("Connect your browser")
                .font(Theme.body(.semibold))
                .foregroundStyle(theme.textPrimary)

            Text("Install the Chrome extension so Agent Pulse can watch your ChatGPT and Claude tabs. Nothing is sent anywhere — it runs locally.")
                .font(Theme.supporting())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 240)
                // 이게 없으면 SwiftUI 가 한 줄로 압축하고 "..." 로 잘라버립니다.
                .fixedSize(horizontal: false, vertical: true)

            // TODO(Phase 4): 확장이 스토어에 올라가면 실제 URL 로 교체.
            //                지금은 확장이 존재하지 않으므로 막다른 길이 되지 않도록
            //                건너뛰기를 같이 둡니다.
            Button {
                NSWorkspace.shared.open(URL(string: "https://chromewebstore.google.com/")!)
            } label: {
                Text("Install extension")
                    .font(Theme.supporting(.semibold))
                    .foregroundStyle(theme.accentFg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(theme.accentBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button(action: onSkip) {
                Text("Skip — terminal only").underline()
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }
}

/// 두 개의 34×34 로고 타일. 빈 상태와 온보딩이 공유합니다.
private struct LogoPair: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    var body: some View {
        HStack(spacing: 8) {
            ForEach([AgentKind.claudeWeb, .chatgptWeb], id: \.self) { agent in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.avatarTile)
                    .frame(width: 34, height: 34)
                    .overlay {
                        BrandMark(agent: agent).frame(width: 18, height: 18)
                    }
            }
        }
    }
}


/// 연결 상태 한 줄. **안 된 항목은 눌러서 바로 설치**할 수 있습니다.
///
/// ⚠️ 예전엔 "run install-codex-notify.sh" 같은 안내만 적어뒀습니다.
///    읽을 수는 있지만 손이 안 갑니다 — 터미널을 열고, 파일을 찾고,
///    경로를 맞춰야 하니까요. 설치 마찰은 테스터를 잃는 가장 흔한 이유고,
///    여기가 그 마찰이 제일 큰 자리입니다.
private struct SurfaceRow: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let surface: ConnectionStatus.Surface

    @State private var hovering = false
    @State private var copied = false

    private var actionable: Bool {
        !surface.connected && SetupActions.isActionable(surface.id)
    }

    var body: some View {
        Group {
            if actionable {
                Button { SetupActions.run(surface.id) } label: { row }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
            } else {
                row
            }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: surface.connected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 11))
                .foregroundStyle(surface.connected ? theme.doneFg : theme.textSecondary)
                .frame(width: 14)

            Text(surface.name)
                .font(Theme.supporting())
                .foregroundStyle(surface.connected ? theme.textPrimary : theme.textSecondary)

            Spacer(minLength: 8)

            if actionable {
                // 설명이 아니라 **버튼**임을 분명히 합니다.
                HStack(spacing: 3) {
                    Text(loc("Set up", "설정하기"))
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(theme.subtleBg.opacity(hovering ? 0 : 1), in: Capsule())
                .background(hovering ? theme.accentBg.opacity(0.25) : .clear, in: Capsule())
            } else if !surface.connected, let command = SetupActions.command(for: surface.id) {
                // 버튼으로 못 해주면 **복사라도** 하게 합니다.
                // 명령어를 보고 손으로 옮겨 치게 두면 오타가 납니다.
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(copied ? theme.doneFg : theme.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.subtleBg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("Copy", "복사"))
            } else if !surface.connected, let hint = surface.hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
    }
}
