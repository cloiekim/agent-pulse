import Foundation

/// 이벤트들을 접어서 만든 "지금 이 세션의 상태".
///
/// 이벤트는 append-only 스트림이고, 세션은 그 스트림의 현재 상태입니다.
struct AgentSession: Identifiable, Codable {
    var id: String { "\(agent.rawValue):\(sessionKey)" }

    let agent: AgentKind
    let sessionKey: String

    var state: SessionState
    var title: String
    var detail: String?
    var cwd: String?
    var returnTarget: String?
    /// 이 세션이 **실제로 뭔가 한 적이 있는가.**
    ///
    /// ⚠️ 터미널을 열고 `claude` 만 띄웠다 닫으면 `SessionStart` → `SessionEnd` 만
    ///    옵니다. 제목도, 걸린 시간도, 한 일도 없는 껍데기 세션입니다.
    ///    실제로 그런 게 다섯 개 쌓여서 목록이 `~ / Idle` 로 도배됐습니다.
    ///    **아무것도 안 한 세션은 정보가 아닙니다.**
    /// 같은 사이트 안의 세부 표면 (`Claude Design` 등).
    var product: String?

    var hasWorked = false

    /// 이 실패가 **우리 잘못이 아닌** 서버 쪽 문제인가.
    ///
    /// 사용자가 할 수 있는 게 다릅니다:
    ///   · 코드 오류 → 고쳐야 합니다
    ///   · 서버 오류 → **기다리면 됩니다.** 상태 페이지를 보는 게 유일한 행동입니다
    /// 그래서 구분해서 보여주는 게 실질적으로 도움이 됩니다.
    /// 한도에 걸려 멈춘 것인가.
    ///
    /// ⚠️ 서버 오류와 **다르게** 다뤄야 합니다.
    ///   · 서버 오류 → 곧 풀립니다. 상태 페이지를 봅니다
    ///   · 한도 초과 → **정해진 시각까지 못 씁니다.** 볼 곳은 사용량입니다
    ///
    /// 그리고 `rate_limit` 이라는 API 코드를 그대로 보여주면 안 됩니다.
    /// 사용자는 그게 무슨 뜻인지, 언제 풀리는지 알 수 없습니다.
    var isRateLimited: Bool {
        guard state == .failed, let detail else { return false }
        let lowered = detail.lowercased()
        return ["rate_limit", "rate limit", "429", "usage limit", "out of credit"]
            .contains { lowered.contains($0) }
    }

    var isServerError: Bool {
        guard state == .failed, let detail else { return false }
        let lowered = detail.lowercased()
        // 한도 초과가 먼저 — 겹치면 그쪽이 더 정확한 설명입니다.
        if isRateLimited { return false }
        return ["500", "502", "503", "529", "internal server",
                "overloaded", "api error", "server error", "upstream"]
            .contains { lowered.contains($0) }
    }

    var origin: SessionOrigin

    var startedAt: Date
    var lastEventAt: Date

    /// 이 상태로 얼마나 오래 있었는가.
    /// "승인 대기 20분"이 이 제품의 핵심 메시지이므로 1급 시민입니다.
    var timeInState: TimeInterval { Date().timeIntervalSince(lastEventAt) }

    var runtime: TimeInterval { Date().timeIntervalSince(startedAt) }

    /// 사용자가 놓쳤다고 볼 수 있는 시점. 재알림(re-nudge)의 기준.
    var isStale: Bool {
        state.blocksProgress && timeInState > 120
    }

    // MARK: - 관대한 디코딩
    //
    // ⚠️ Swift 가 자동 생성하는 디코더는 **프로퍼티 기본값을 쓰지 않습니다.**
    //    필드를 하나 추가하는 순간 예전에 저장된 파일이 전부 못 읽히고,
    //    사용자는 이유도 모른 채 기록을 잃습니다. (실제로 `origin` 을 추가했을 때
    //    24시간치 활동 기록이 조용히 날아갔습니다.)
    //
    //    그래서 새로 생기는 필드는 전부 `decodeIfPresent` 로 받습니다.
    //    앞으로 필드를 추가할 때도 여기에 같은 방식으로 넣으세요.

    enum CodingKeys: String, CodingKey {
        case agent, sessionKey, state, title, detail, cwd, returnTarget, origin, hasWorked, product
        case startedAt, lastEventAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decode(AgentKind.self, forKey: .agent)
        sessionKey = try c.decode(String.self, forKey: .sessionKey)
        state = try c.decode(SessionState.self, forKey: .state)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        returnTarget = try c.decodeIfPresent(String.self, forKey: .returnTarget)
        origin = try c.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .terminal
        hasWorked = try c.decodeIfPresent(Bool.self, forKey: .hasWorked) ?? true
        product = try c.decodeIfPresent(String.self, forKey: .product)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastEventAt = try c.decode(Date.self, forKey: .lastEventAt)
    }

    /// ⚠️ 이름이 `init(from:)` 이면 안 됩니다 — Codable 의
    /// `init(from decoder:)` 합성과 충돌합니다.
    init(starting event: AgentEvent) {
        self.agent = event.agent
        self.sessionKey = event.sessionKey
        self.state = event.state
        self.title = event.title ?? Self.projectName(from: event.cwd) ?? event.agent.displayName
        self.detail = event.detail
        self.cwd = event.cwd
        self.returnTarget = event.returnTarget
        self.origin = event.origin
        self.product = event.product
        self.startedAt = event.timestamp
        self.lastEventAt = event.timestamp
    }

    /// 새 이벤트를 접어 넣습니다. nil 필드는 기존 값을 유지합니다.
    mutating func apply(_ event: AgentEvent) {
        state = event.state
        if let t = event.title { title = t }
        if let d = event.detail { detail = d }
        if let c = event.cwd { cwd = c }
        if let r = event.returnTarget { returnTarget = r }
        origin = event.origin
        if let p = event.product { product = p }
        lastEventAt = event.timestamp
    }

    static func projectName(from cwd: String?) -> String? {
        // ⚠️ 홈 디렉터리에서 띄운 세션은 폴더명이 계정 이름(`mihyunkim`)입니다.
        //    그게 여러 개 쌓이면 전부 같은 제목이라 구분이 안 됩니다.
        //    `~` 로 보여주면 최소한 "프로젝트가 아니라 홈에서 띄웠다" 는 게 읽힙니다.
        if let cwd,
           URL(fileURLWithPath: cwd).standardizedFileURL
            == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            return "~"
        }

        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

extension TimeInterval {
    /// "38m" / "38분", "4h 38m" / "4시간 38분" 같은 짧은 표기.
    ///
    /// ⚠️ 예전엔 한국어로 하드코딩돼 있어서 영어 설정에서도
    /// `resets in 4시간 38분` 처럼 섞여 나왔습니다.
    /// 시간 표기도 문구의 일부이므로 언어를 따라가야 합니다.
    func shortDuration(_ loc: Loc) -> String {
        let total = max(0, Int(self))

        if total < 60 {
            return loc("\(total)s", "\(total)초")
        }
        if total < 3600 {
            return loc("\(total / 60)m", "\(total / 60)분")
        }

        let h = total / 3600, m = (total % 3600) / 60
        if m == 0 {
            return loc("\(h)h", "\(h)시간")
        }
        return loc("\(h)h \(m)m", "\(h)시간 \(m)분")
    }
}
