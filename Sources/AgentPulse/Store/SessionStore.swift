import Foundation
import Observation

/// 모든 세션의 단일 진실 공급원(single source of truth).
///
/// 입력은 오직 `ingest(_:)` 하나뿐입니다. Claude Code 훅이든,
/// Codex notify 든, 크롬 확장이든 전부 여기로 모입니다.
@Observable
@MainActor
final class SessionStore {

    /// 살아 있는 세션들. 상태 우선순위 → 오래 기다린 순으로 정렬.
    private(set) var sessions: [AgentSession] = []

    /// 최근 활동 피드. MVP 는 24시간, Pro 는 30일 (PRD 참조).
    private(set) var feed: [AgentEvent] = []

    /// 완료 후 이 시간이 지나면 목록에서 조용히 사라집니다.
    private let completedTTL: TimeInterval = 30 * 60

    private var index: [String: Int] = [:]   // session.id -> sessions 배열 인덱스
    private let notifier: Notifier

    /// 데모 모드에서는 실제 저장 파일을 건드리지 않습니다.
    private let persists: Bool

    init(notifier: Notifier = Notifier(), persists: Bool = true) {
        self.notifier = notifier
        self.persists = persists

        // 껐다 켜도 기록이 남습니다.
        // 단, 진행 중이던 세션은 복원하지 않습니다 — Persistence.swift 주석 참고.
        if persists, let snapshot = Persistence.load() {
            sessions = snapshot.sessions
            feed = snapshot.feed
            resort()
        }
    }

    /// 디스크 저장은 잦으면 낭비이므로 최소 간격을 둡니다.
    private var lastSavedAt = Date.distantPast
    private let saveThrottle: TimeInterval = 2

    private func persistIfNeeded(force: Bool = false) {
        guard persists else { return }
        guard force || Date().timeIntervalSince(lastSavedAt) > saveThrottle else { return }
        lastSavedAt = Date()
        Persistence.save(sessions: sessions, feed: feed)
    }

    /// 앱 종료 직전에 호출합니다.
    func flush() {
        persistIfNeeded(force: true)
    }

    // MARK: - 입력

    func ingest(_ event: AgentEvent) {
        let key = "\(event.agent.rawValue):\(event.sessionKey)"
        let previousState = index[key].map { sessions[$0].state }

        // 실제로 뭔가 한 이벤트인가. (시작·종료만으로는 "일했다" 고 보지 않습니다)
        let didWork = event.state == .running
            || event.state == .needsApproval
            || event.state == .waitingInput
            || event.state == .completed
            || event.state == .failed

        if let i = index[key] {
            sessions[i].apply(event)
            if didWork { sessions[i].hasWorked = true }
        } else {
            var fresh = AgentSession(starting: event)
            fresh.hasWorked = didWork
            sessions.append(fresh)
        }

        // 브라우저에서 이벤트가 왔다는 건 확장이 살아 있다는 뜻입니다.
        if event.agent.surface == .browser { ConnectionStatus.markBrowserSeen() }

        feed.insert(event, at: 0)
        if feed.count > 500 { feed.removeLast(feed.count - 500) }

        resort()

        // 개발용 확인 로그. 이벤트가 들어왔는데 UI 가 안 바뀌면
        // 여기까지 왔는지부터 확인하세요.
        apLog("이벤트 수신: \(event.agent.rawValue) \(event.state.rawValue) [\(event.hookName ?? "-")] — 세션 \(sessions.count)개, 주의 \(needsAttention.count)개")

        // 상태가 "실제로 바뀌었을 때"만 알림.
        // 같은 상태의 반복 이벤트로 사용자를 두들기지 않기 위한 가드입니다.
        if previousState != event.state, event.state.deservesNotification,
           let session = sessions.first(where: { $0.id == key }) {
            notifier.notify(for: session)
        }

        persistIfNeeded()
    }

    // MARK: - 파생 값 (뷰가 읽는 것들)

    /// 지금 당장 사용자를 필요로 하는 세션들. 메뉴 맨 위에 옵니다.
    var needsAttention: [AgentSession] {
        sessions.filter { $0.state.blocksProgress }
    }

    var running: [AgentSession] {
        sessions.filter { $0.state == .running }
    }

    /// "지금 몇 개 돌리고 있나"에 대한 답.
    ///
    /// 승인 대기·입력 대기·큐 대기도 포함합니다 — 멈춰 있어도 여전히
    /// 사용자가 신경 써야 하는 작업이니까요. 끝났거나 잠든 것만 뺍니다.
    var activeCount: Int {
        sessions.filter {
            switch $0.state {
            case .running, .needsApproval, .waitingInput, .queued: true
            case .completed, .failed, .idle: false
            }
        }.count
    }

    var recentlyCompleted: [AgentSession] {
        sessions.filter { $0.state == .completed || $0.state == .failed }
    }

    /// 메뉴바 아이콘이 표시할 대표 상태.
    /// 가장 급한 것 하나를 보여줍니다.
    var headlineState: SessionState? {
        sessions.min(by: { $0.state.priority < $1.state.priority })?.state
    }

    // MARK: - 정리

    /// 조용해진 세션을 얼마나 들고 있을지.
    ///
    /// ⚠️ 예전엔 `completed`·`failed` 만 정리하고 `idle` 은 영원히 남겼습니다.
    ///    터미널을 자주 여닫으면 idle 이 계속 쌓여서, 실제로 14개가 넘어
    ///    팝오버가 화면을 벗어났습니다. **끝난 지 오래된 세션은 정보가 아니라
    ///    잡음입니다.**
    private let idleTTL: TimeInterval = 30 * 60

    /// 아무리 최근이어도 이 개수를 넘기지 않습니다.
    /// 목록이 길어지면 어차피 아무도 안 읽습니다.
    private let maxSessions = 20

    /// 타이머로 주기 호출. 오래된 세션을 걷어냅니다.
    func prune() {
        let now = Date()
        sessions.removeAll { session in
            // 아무것도 안 하고 조용해진 세션은 바로 버립니다.
            // 터미널만 열었다 닫은 껍데기라 보여줄 게 없습니다.
            if session.state == .idle, !session.hasWorked { return true }

            let age = now.timeIntervalSince(session.lastEventAt)
            switch session.state {
            case .completed, .failed: return age > completedTTL
            case .idle:               return age > idleTTL
            default:                  return false
            }
        }

        // 그래도 많으면 오래된 것부터 버립니다. 돌고 있는 건 절대 안 버립니다.
        if sessions.count > maxSessions {
            let active = sessions.filter { $0.state.blocksProgress || $0.state == .running }
            let rest = sessions.filter { !($0.state.blocksProgress || $0.state == .running) }
                .sorted { $0.lastEventAt > $1.lastEventAt }
                .prefix(max(0, maxSessions - active.count))
            sessions = active + rest
        }
        resort()
    }

    func dismiss(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        resort()
    }

    func clearCompleted() {
        sessions.removeAll { $0.state == .completed || $0.state == .failed }
        resort()
    }

    private func resort() {
        sessions.sort {
            $0.state.priority != $1.state.priority
                ? $0.state.priority < $1.state.priority
                : $0.lastEventAt < $1.lastEventAt   // 오래 기다린 것이 위로
        }
        index = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($1.id, $0) })
    }
}

// MARK: - 미리보기 / 개발용 목업

extension SessionStore {
    /// 훅을 설치하기 전에도 UI를 볼 수 있게 하는 샘플 데이터.
    /// `swift run AgentPulse --demo` 로 켭니다.
    static func demo() -> SessionStore {
        // 데모는 저장 파일을 건드리지 않습니다.
        let store = SessionStore(notifier: Notifier(enabled: false), persists: false)
        let now = Date()
        let samples: [AgentEvent] = [
            AgentEvent(agent: .claudeCode, sessionKey: "s1", state: .needsApproval,
                       title: "agent-pulse-os", cwd: "/Users/me/dev/agent-pulse-os",
                       detail: "Bash: rm -rf build/", timestamp: now.addingTimeInterval(-1_260)),
            AgentEvent(agent: .codex, sessionKey: "s2", state: .running,
                       title: "pandas-money", cwd: "/Users/me/dev/pandas-money",
                       detail: "테스트 실행 중", timestamp: now.addingTimeInterval(-180)),
            AgentEvent(agent: .claudeWeb, sessionKey: "s3", state: .completed,
                       title: "마켓 리서치 정리", detail: "응답 완료",
                       returnTarget: "https://claude.ai/chat/abc", timestamp: now.addingTimeInterval(-95)),
            AgentEvent(agent: .chatgptWeb, sessionKey: "s4", state: .running,
                       title: "SwiftUI 레이아웃 질문",
                       returnTarget: "https://chatgpt.com/c/def", timestamp: now.addingTimeInterval(-30)),
            AgentEvent(agent: .claudeCode, sessionKey: "s5", state: .failed,
                       title: "html-anything", cwd: "/Users/me/dev/html-anything",
                       detail: "빌드 실패 — exit 1", timestamp: now.addingTimeInterval(-600)),
        ]
        for e in samples { store.ingest(e) }
        return store
    }
}
