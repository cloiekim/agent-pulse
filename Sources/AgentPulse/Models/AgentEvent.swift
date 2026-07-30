import Foundation

/// 모든 입력 소스(Claude Code 훅, Codex notify, 크롬 확장)가
/// 최종적으로 변환되는 단 하나의 이벤트 형식.
///
/// 새 에이전트를 붙일 때 해야 하는 일은 "그 에이전트의 신호를
/// AgentEvent 로 바꾸는 매퍼 하나 작성"뿐입니다.
/// Store 와 View 는 절대 수정하지 않습니다.
struct AgentEvent: Codable, Identifiable {
    var id = UUID()

    /// 어떤 에이전트에서 왔는가.
    let agent: AgentKind

    /// 세션 고유 키.
    /// - Claude Code: 훅의 `session_id`
    /// - Codex: `turn-id` 또는 cwd 해시
    /// - 브라우저: 대화 URL 의 conversation id
    let sessionKey: String
    /// 어떤 도구인지 (`Bash`, `Read`, …). 승인 가능 여부 판단에 씁니다.
    var toolName: String? = nil
    /// 어느 훅에서 왔는지. 진단용 — 오탐 추적에 꼭 필요합니다.
    var hookName: String? = nil

    /// 이 이벤트가 의미하는 상태.
    let state: SessionState

    /// 프로젝트 이름 (터미널) 또는 대화 제목 (브라우저).
    var title: String?

    /// 작업 디렉터리. 터미널 세션의 프로젝트 식별에 씀.
    var cwd: String?

    /// 상태 아래 한 줄로 보여줄 세부 정보.
    /// 예) "Bash: npm test", "파일 7개 수정"
    var detail: String?

    /// 이 세션이 어디서 시작됐는가. Jump 목적지를 결정합니다.
    var origin: SessionOrigin = .terminal

    /// 클릭했을 때 돌아갈 곳.
    /// - 터미널: `agentpulse://terminal?tty=/dev/ttys003`
    /// - 브라우저: 실제 대화 URL
    var returnTarget: String?

    var timestamp: Date = Date()

    /// 원본 페이로드. 디버깅용으로만 보관하고 절대 외부로 보내지 않습니다.
    var raw: [String: String]?
}


extension AgentEvent {
    // AgentSession 과 같은 이유 — 필드가 늘어도 예전 기록을 계속 읽을 수 있어야 합니다.
    enum CodingKeys: String, CodingKey {
        case id, agent, sessionKey, toolName, hookName, state, title, cwd, detail, origin, returnTarget, timestamp, raw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        agent = try c.decode(AgentKind.self, forKey: .agent)
        sessionKey = try c.decode(String.self, forKey: .sessionKey)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        hookName = try c.decodeIfPresent(String.self, forKey: .hookName)
        state = try c.decode(SessionState.self, forKey: .state)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        origin = try c.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .terminal
        returnTarget = try c.decodeIfPresent(String.self, forKey: .returnTarget)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        raw = try c.decodeIfPresent([String: String].self, forKey: .raw)
    }
}

/// 세션이 시작된 곳. `Jump` 가 어디로 갈지를 정합니다.
///
/// 같은 Claude Code 세션이라도 터미널에서 띄운 것과 데스크톱 앱 Code 탭에서
/// 띄운 것은 **돌아갈 곳이 완전히 다릅니다.** 구분하지 않으면 엉뚱한 앱이 뜹니다.
enum SessionOrigin: String, Codable {
    case terminal
    case claudeDesktop
    case browser
}
