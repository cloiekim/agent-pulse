import SwiftUI
import AppKit

/// 세션 한 줄. 디자인 4a 의 핵심 컴포넌트입니다.
///
/// 레이아웃: [아바타 28] 10 [제목/부제목 · flex] 10 [알약]
/// 패딩 10/14, 제목 14/500 말줄임, 부제목 12.
///
/// 부제목 형식: `Claude Code · my-repo — tool approval`
///              `ChatGPT · tab — 4m 12s`
struct SessionRow: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    // ⚠️ Environment 로 받으면 안 됩니다 — 팝오버는 뜰 때의 environment 를
    //    붙들고 있어서, 언어를 바꿔도 이미 열려 있는 화면에 반영되지 않습니다.
    private var loc: Loc { AppSettings.shared.loc }

    let session: AgentSession
    var onPrimaryAction: (() -> Void)?
    var onOpen: (() -> Void)?
    /// 목록에 같은 제목이 또 있는가. 있으면 시작 시각으로 구분합니다.
    var duplicateTitle = false
    /// 처리한 항목을 목록에서 지웁니다.
    var onDismiss: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AgentAvatar(agent: session.agent, product: session.surfaceName)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .layoutPriority(1)
                    .font(Theme.body(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // 같은 제목이 여러 개일 때만 시작 시각으로 구분합니다.
                // 항상 붙이면 제목 자리를 빼앗아 정작 제목이 잘립니다.
                if let startedLabel {
                    Text(startedLabel)
                        .font(Theme.supporting())
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize()
                }

                Text(subtitle)
                    .font(Theme.supporting())
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ⚠️ 한도 초과엔 `Jump` 가 의미 없습니다.
            //    가서 할 수 있는 게 없거든요 — 기다리는 것뿐입니다.
            //    대신 **얼마나 기다려야 하는지**를 그 자리에 보여줍니다.
            //    그게 이 상황에서 유일하게 쓸모 있는 정보입니다.
            if session.isRateLimited {
                Text(resetCountdown ?? loc("Limited", "한도 초과"))
                    .font(Theme.supporting(.medium))
                    .foregroundStyle(theme.attentionFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(theme.attentionBg, in: Capsule())
                    .fixedSize()
            } else {
                // 어떤 상태든 누르면 그 세션이 있는 곳으로 갑니다.
                StatusPill(state: session.state, action: onPrimaryAction ?? onOpen)
            }
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.rowPaddingV)
        .background(rowBackground)
        .contentShape(Rectangle())
        // ⚠️ 처리한 항목을 지울 방법이 있어야 합니다.
        //    실패를 보고 조치했는데도 30분간 목록과 메뉴바에 남아 있으면,
        //    "봤다" 고 말할 방법이 없어서 계속 눈에 걸립니다.
        .contextMenu {
            if let onDismiss {
                Button(loc("Dismiss", "목록에서 지우기"), action: onDismiss)
            }
            if session.isServerError {
                Button(loc("Open status page", "상태 페이지 열기")) {
                    if let url = URL(string: "https://status.claude.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        // 한도 초과는 갈 곳이 없으므로 행 클릭도 막습니다.
        .onTapGesture { if !session.isRateLimited { onOpen?() } }
        .onHover { hovering = $0 }
        // ⚠️ 내부 URL(agentpulse://terminal?cwd=…)을 그대로 보여주면 안 됩니다.
        //    사용자에게 아무 의미 없고, 만들다 만 것처럼 보입니다.
        .help(jumpHint)
    }

    /// 승인 대기 행만 배경이 노랗게 깔립니다. 나머지는 hover 시에만.
    private var rowBackground: Color {
        if session.state == .needsApproval { return theme.attentionRowBg }
        return hovering ? theme.rowHover : .clear
    }

    /// 승인 대기는 노랑, 에러는 빨강, 나머지는 회색.
    private var subtitleColor: Color {
        switch session.state {
        case .needsApproval, .waitingInput: theme.attentionText
        case .failed:                       theme.errorText
        default:                            theme.textSecondary
        }
    }

    /// `에이전트 · 위치 — 상태/시간`
    ///
    /// ⚠️ 제목이 이미 폴더명이면 위치를 또 쓰지 않습니다.
    ///    `/tmp` 에서 띄우면 제목도 `tmp`, 부제목도 `tmp` 가 되어
    ///    **같은 글자를 두 번 보여주고 정작 필요한 정보가 잘렸습니다.**
    private var subtitle: String {
        // 같은 사이트라도 표면이 다르면 그걸 씁니다 (`Claude Design` 등).
        // 그래야 제목만 보고 "이게 어디서 온 거지?" 를 안 묻게 됩니다.
        var parts = [session.surfaceName ?? session.agent.displayName]

        let place: String? = {
            if session.agent.surface != .terminal { return loc("tab", "탭") }
            guard let project = AgentSession.projectName(from: session.cwd) else {
                return loc("terminal", "터미널")
            }
            // 제목과 같으면 생략합니다.
            return project == session.title ? nil : project
        }()
        if let place { parts.append(place) }

        // ⚠️ 실패한 행에서는 **이유가 제목보다 중요합니다.**
        //    예전엔 `Claude Code · deepsynth — er…` 처럼 이유가 잘려서
        //    아무 정보가 없었습니다. 프로젝트명은 제목에서 이미 읽히니 뺍니다.
        if session.state == .failed {
            // ⚠️ 한도 초과는 **언제 풀리는지**가 유일하게 쓸모 있는 정보입니다.
            //    `rate_limit` 이라는 코드를 그대로 보여주면 아무 도움이 안 됩니다.
            // 알림과 **같은 함수**를 씁니다 (AgentSession.failureReason).
            if let reason = session.failureReason(loc) { return reason }
        }

        // 보여줄 시간이 없으면 대시도 붙이지 않습니다.
        // `Claude Code —` 처럼 끝나면 뒤가 잘린 것처럼 보입니다.
        let left = parts.joined(separator: " · ")
        return timing.isEmpty ? left : left + " — " + timing
    }

    /// 한도가 풀리기까지 남은 시간. `2시간 15분` 처럼.
    ///
    /// ⚠️ 절대 시각(`오후 8:30`)보다 남은 시간이 낫습니다.
    ///    "지금부터 얼마나 못 쓰나" 가 알고 싶은 것이지,
    ///    몇 시인지를 계산해서 빼는 건 사용자가 할 일이 아닙니다.
    private var resetCountdown: String? {
        guard let resets = UsageSnapshot.nextReset else { return nil }
        let remaining = resets.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return remaining.shortDuration(loc)
    }

    /// 같은 제목이 여러 개일 때 구분용으로 붙이는 시작 시각.
    ///
    /// 홈이나 같은 프로젝트에서 여러 세션을 돌리면 제목이 비슷해집니다.
    /// 그때 시작 시각이 있으면 "아, 아까 그거" 가 됩니다.
    private var startedLabel: String? {
        guard duplicateTitle else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: loc.language == .korean ? "ko_KR" : "en_US")
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f.string(from: session.startedAt)
    }

    /// 클릭했을 때 어디로 가는지 사람 말로.
    private var jumpHint: String {
        // 서버 오류는 코드를 고칠 게 아니라 기다리는 상황입니다.
        // 그러니 터미널보다 상태 페이지가 맞습니다.
        if session.isRateLimited {
            return loc("See usage below", "아래 사용량 참고")
        }
        if session.isServerError {
            return loc("Open status.claude.com", "status.claude.com 열기")
        }
        switch session.origin {
        case .claudeDesktop:
            return loc("Open in Claude", "Claude 앱에서 열기")
        case .browser:
            return loc("Open the tab", "브라우저 탭 열기")
        case .terminal:
            let project = AgentSession.projectName(from: session.cwd)
            return project.map { loc("Go to terminal · \($0)", "터미널로 이동 · \($0)") }
                ?? loc("Go to terminal", "터미널로 이동")
        }
    }

    /// 상태마다 **의미 있는 시간**이 다릅니다.
    ///
    /// 예전엔 전부 `runtime`(시작 후 경과)을 썼는데, 이미 끝난 작업에도
    /// 숫자가 계속 올라가서 "8분 57초 걸렸다" 인지 "8분 57초 전에 시작했다" 인지
    /// 알 수 없었습니다.
    ///
    /// - 실행 중  → 시작 후 경과 (계속 늘어나는 게 맞음)
    /// - 승인 대기 → **이 상태로 얼마나 묶여 있는가**. 이게 이 제품의 핵심 숫자입니다
    /// - 완료·실패 → 언제 끝났는가
    private var timing: String {
        switch session.state {
        case .running:
            return session.runtime.clockDuration

        case .needsApproval, .waitingInput:
            let waiting = session.timeInState
            let suffix = session.state.subtitleSuffix(loc) ?? ""
            // 막 뜬 건 굳이 시간을 안 붙입니다. 20초쯤부터 의미가 생깁니다.
            guard waiting > 20 else { return suffix }
            let d = waiting.shortDuration(loc)
            return loc("\(suffix) · waiting \(d)", "\(suffix) · \(d)째")

        case .failed:
            return session.state.subtitleSuffix(loc) ?? loc("error", "오류")

        case .completed:
            let ago = session.timeInState
            if ago < 20 { return loc("just now", "방금") }
            let d = ago.shortDuration(loc)
            return loc("\(d) ago", "\(d) 전")

        case .queued, .idle:
            return session.state.subtitleSuffix(loc) ?? session.detail ?? ""
        }
    }
}

extension TimeInterval {
    /// "4m 12s", "1m 03s" — 디자인의 표기 방식.
    var clockDuration: String {
        let total = max(0, Int(self))
        let m = total / 60, s = total % 60
        if m == 0 { return "\(s)s" }
        return String(format: "%dm %02ds", m, s)
    }
}
