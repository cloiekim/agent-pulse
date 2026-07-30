import SwiftUI

/// 세션의 라이브 상태.
///
/// 이 enum 이 제품의 심장입니다. 마켓 분석 결과 "쿼터 게이지"는 이미
/// 무료로 포화됐고, 비어 있는 건 바로 이 상태 축입니다.
///
/// `priority` 순서가 곧 메뉴 정렬 순서이자 메뉴바 아이콘이 무엇을
/// 표시할지 결정하는 기준입니다. 사용자가 알아야 할 가장 급한 것이 위로.
enum SessionState: String, Codable, CaseIterable {
    /// 도구 승인을 기다리며 멈춰 있음. 가장 비싼 상태 — 에이전트가 놀고 있음.
    /// 디자인 4a 의 노란색 강조 행.
    case needsApproval
    /// 에러로 멈춤. 디자인의 "network error → Retry" 행.
    case failed
    /// 질문에 대한 답을 기다림 (승인 프롬프트는 아님).
    case waitingInput
    /// 실행 중. 디자인의 파란 "Running" 필 + 맥동하는 점.
    case running
    /// 큐에 걸려 아직 시작 안 함. 디자인의 회색 "Waiting" 필.
    case queued
    /// 방금 끝남.
    case completed
    /// 세션은 살아 있지만 아무 일도 안 일어남.
    case idle

    /// 낮을수록 급함. 정렬과 메뉴바 배지 결정에 씀.
    var priority: Int {
        switch self {
        case .needsApproval: 0
        case .failed:        1
        case .waitingInput:  2
        case .running:       3
        case .queued:        4
        case .completed:     5
        case .idle:          6
        }
    }

    /// 사용자를 실제로 방해해도 되는 상태인가.
    /// (running/queued/idle 로 알림을 보내면 앱이 바로 꺼집니다.)
    var deservesNotification: Bool {
        switch self {
        case .needsApproval, .waitingInput, .completed, .failed: true
        case .running, .queued, .idle: false
        }
    }

    /// 사용자의 개입이 있어야만 진행되는 상태.
    /// 메뉴바 아이콘이 "주의" 모드(노란 점)로 바뀌는 조건.
    var blocksProgress: Bool {
        switch self {
        case .needsApproval, .waitingInput, .failed: true
        default: false
        }
    }

    /// 헤더의 "3 running" / "1 needs you" 칩 계산용.
    var isActive: Bool { self == .running }

    /// 행 오른쪽에 붙는 라벨.
    ///
    /// ⚠️ 디자인은 `Approve` / `Retry` 였지만 **그렇게 부르면 거짓말입니다.**
    /// 훅은 도구 호출을 *차단*할 수는 있어도, 이미 떠 있는 대화형 프롬프트에
    /// 외부 프로세스가 "yes" 를 밀어넣을 수 없습니다. 실제로 하는 일은
    /// "그 터미널/탭으로 데려다주기" 뿐이므로 그렇게 씁니다.
    ///
    /// 진짜 원격 승인은 Claude Code 를 자체 PTY 로 감싸야 가능하고,
    /// 그건 "얇은 레이어" 라는 제품 원칙을 버리는 일입니다. README §4 참고.
    func pillLabel(_ loc: Loc) -> String {
        switch self {
        case .needsApproval: loc("Jump", "이동")
        case .failed:        loc("Jump", "이동")
        case .waitingInput:  loc("Jump", "이동")
        case .running:       loc("Running", "실행 중")
        case .queued:        loc("Waiting", "대기")
        case .completed:     loc("Done", "완료")
        case .idle:          loc("Idle", "유휴")
        }
    }

    /// 행 두 번째 줄 끝에 붙는 상태 설명. "Claude Code · my-repo — tool approval"
    func subtitleSuffix(_ loc: Loc) -> String? {
        switch self {
        case .needsApproval: loc("tool approval", "도구 승인 대기")
        case .waitingInput:  loc("needs input", "입력 대기")
        case .failed:        loc("error", "오류")
        case .queued:        loc("queued", "대기열")
        default:             nil
        }
    }

    /// 오른쪽 요소가 버튼(누를 수 있음)인지 상태 표시(읽기 전용)인지.
    /// 디자인상 Approve/Retry 만 버튼입니다.
    var hasPrimaryAction: Bool {
        self == .needsApproval || self == .failed || self == .waitingInput
    }
}
