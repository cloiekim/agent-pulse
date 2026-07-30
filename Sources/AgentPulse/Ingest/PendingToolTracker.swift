import Foundation

/// 승인 대기를 **제때** 잡기 위한 보정 레이어.
///
/// 왜 필요한가:
/// Claude Code 의 `Notification`/`idle_prompt` 훅은 60초 이상 idle 이고
/// 터미널이 포커스되지 않았을 때만 발화합니다(claude-code #13024).
/// 사용자는 그 60초 동안 아무것도 모른 채 기다립니다.
///
/// 이 클래스가 하는 일:
/// `PreToolUse` 가 오면 타이머를 겁니다. `graceInterval`(기본 2.5초) 안에
/// 같은 세션의 `PostToolUse` 가 오지 않으면 → 승인 프롬프트가 떠 있는 것으로
/// 간주하고 `needsApproval` 이벤트를 스스로 발행합니다.
///
/// 즉 공식 훅의 60초를 2.5초로 줄입니다. 이게 제품의 기술적 해자입니다.
///
/// ## 이건 **보조 장치**입니다 (중요)
///
/// Claude Code 는 권한이 필요할 때 `Notification` 훅을 **즉시** 쏩니다
/// (`permission_prompt`). 60초 규칙은 유휴 상태(`idle_prompt`)에만 적용됩니다.
/// 우리는 그 훅을 이미 받고 있으므로, **정확한 신호가 이미 있습니다.**
///
/// 그럼 이 타이머는 왜 남겨두나:
/// 훅이 어떤 이유로 안 올 수 있기 때문입니다 (설정 누락, 버전 차이, 권한 문제).
/// 그때 아무 표시도 없이 20분을 흘려보내는 것보단 낫습니다.
///
/// ## 유예 시간을 25초로 잡은 이유
///
/// 2.5초 → 6초로 올렸는데도 **작업 중에 승인 알림이 떴습니다.**
/// 빌드·네트워크 호출·서브에이전트는 6초를 우습게 넘깁니다.
///
/// 시간으로 승인을 추정하는 건 애초에 틀린 접근이었습니다.
/// 정확한 신호가 따로 있는데 추측으로 앞지르려 한 거예요.
///
/// 그래서 이제:
///   · 진짜 승인 → `Notification` 훅이 **즉시** 잡습니다 (오탐 0)
///   · 훅이 안 오면 → 25초 뒤 이 타이머가 받칩니다 (공식 60초보다 여전히 빠름)
///
/// **정확한 신호를 우선하고, 추측은 뒤로 미룹니다.**
actor PendingToolTracker {

    /// 추측 타이머를 쓸지.
    ///
    /// ⚠️ **기본값은 꺼짐입니다.**
    ///
    /// 2.5초 → 6초 → 25초로 세 번 올렸는데 세 번 다 작업 중에 승인 알림이 떴습니다.
    /// 숫자 문제가 아니라 **접근이 틀린 겁니다.** 도구가 오래 걸리는 이유는
    /// 수십 가지인데, 그중 하나가 승인 대기일 뿐입니다. 시간만으로는 구분이 안 됩니다.
    ///
    /// 그리고 틀린 알림의 비용은 놓친 알림보다 큽니다:
    /// 놓치면 한 번 손해지만, 틀리면 **그다음부터 모든 알림을 안 믿게 됩니다.**
    ///
    /// 정확한 신호(`Notification` 훅의 `permission_prompt`)가 이미 있으므로
    /// 그것만 씁니다. 훅이 안 오는 환경이 발견되면 그때 다시 켭니다.
    static var fallbackEnabled = false


    private var pending: [String: Task<Void, Never>] = [:]
    private let graceInterval: Duration
    private let emit: @Sendable (AgentEvent) -> Void

    init(graceInterval: Duration = .seconds(25),
         emit: @escaping @Sendable (AgentEvent) -> Void) {
        self.graceInterval = graceInterval
        self.emit = emit
    }

    /// 훅 이벤트를 통과시키면서 필요한 경우 추가 이벤트를 발행합니다.
    func observe(_ event: AgentEvent, hookName: String) {
        let key = "\(event.agent.rawValue):\(event.sessionKey)"

        switch hookName {
        case "PreToolUse":
            pending[key]?.cancel()
            pending[key] = nil

            // 추측 타이머는 기본으로 꺼져 있습니다 (위 주석 참고).
            guard Self.fallbackEnabled else { return }

            // 승인을 요구할 수 없는 도구는 추적하지 않습니다.
            guard Self.canRequireApproval(event.toolName) else { return }

            pending[key] = Task { [emit, graceInterval] in
                try? await Task.sleep(for: graceInterval)
                guard !Task.isCancelled else { return }

                // ⚠️ `origin` 을 반드시 물고 와야 합니다.
                //    이 승격 이벤트가 곧 알림이 되는데, origin 이 빠지면
                //    기본값 `.terminal` 로 떨어져서 **데스크톱 앱 세션인데
                //    터미널이 뜹니다.** 제목은 맞게 나와서 더 헷갈립니다.
                emit(AgentEvent(
                    agent: event.agent,
                    sessionKey: event.sessionKey,
                    toolName: event.toolName,
                    hookName: "timer-fallback",   // 훅이 아니라 추측입니다
                    state: .needsApproval,
                    title: event.title,
                    cwd: event.cwd,
                    detail: event.detail ?? "tool approval",
                    origin: event.origin,
                    returnTarget: event.returnTarget
                ))
            }

        case "Notification", "PermissionRequest":
            // 진짜 신호가 도착했습니다. 추측 타이머는 더 이상 필요 없습니다.
            pending[key]?.cancel()
            pending[key] = nil

        case "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "SessionEnd":
            // 도구가 실제로 실행됐다 → 승인 프롬프트가 아니었음. 타이머 취소.
            pending[key]?.cancel()
            pending[key] = nil

        default:
            break
        }
    }

    /// 이 도구가 **승인 프롬프트를 띄울 수 있는가.**
    ///
    /// Claude Code 는 파일을 바꾸거나 외부에 영향을 주는 도구에만 승인을 묻습니다.
    /// 읽기 전용 도구는 아무리 오래 걸려도 승인이 아니므로, 큰 파일을 읽느라
    /// 시간이 걸린 걸 승인 대기로 오해하지 않게 합니다.
    ///
    /// 모르는 이름(주로 MCP 도구)은 **승인 가능으로 봅니다** — 놓치는 것보다
    /// 가끔 헛집는 게 낫고, 6초 유예가 대부분 걸러줍니다.
    static func canRequireApproval(_ toolName: String?) -> Bool {
        guard let name = toolName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return true
        }
        return !readOnlyTools.contains(name)
    }

    /// 절대 승인을 묻지 않는 도구들.
    private static let readOnlyTools: Set<String> = [
        "Read", "Glob", "Grep", "LS", "NotebookRead",
        "TodoWrite", "TodoRead", "Task", "ExitPlanMode",
        "WebSearch",   // 검색은 묻지 않습니다 (WebFetch 는 물을 수 있음)
    ]

    func cancelAll() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }
}
