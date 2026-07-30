import Foundation

/// 어떤 알림을 받을지.
///
/// ⚠️ 왜 나눴나:
/// 예전엔 스위치 하나로 전부 켜거나 전부 껐습니다. 그런데 세 종류의 가치가
/// 완전히 다릅니다:
///
///   · 승인 대기 — **내가 안 보면 일이 멈춥니다.** 이게 이 앱의 존재 이유입니다.
///   · 실패    — 알면 좋지만 급하진 않습니다.
///   · 완료    — 내가 안 봐도 일은 이미 끝났습니다. 알림의 가치가 가장 낮습니다.
///
/// 전부 아니면 전무로 두면, 완료 알림이 시끄러운 순간 **통째로 꺼버리고
/// 다시는 안 켭니다.** 그러면 정작 중요한 승인 알림까지 잃습니다.
///
/// 그래서 기본값은 **승인 + 실패**, 완료는 꺼둡니다.
struct NotificationKinds: OptionSet, Sendable {
    let rawValue: Int

    static let approval  = NotificationKinds(rawValue: 1 << 0)
    static let failure   = NotificationKinds(rawValue: 1 << 1)
    static let completed = NotificationKinds(rawValue: 1 << 2)

    /// 완료는 기본으로 끕니다 — 셋 중 가장 안 급한데 가장 자주 옵니다.
    static let `default`: NotificationKinds = [.approval, .failure]

    func allows(_ state: SessionState) -> Bool {
        switch state {
        case .needsApproval, .waitingInput: contains(.approval)
        case .failed:                       contains(.failure)
        case .completed:                    contains(.completed)
        case .running, .queued, .idle:      false
        }
    }
}
