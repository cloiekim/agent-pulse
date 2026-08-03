import Foundation

/// 화면 여기저기서 "언제 풀리나" 를 물어볼 수 있게 하는 작은 창구.
///
/// ⚠️ 세션 행이 사용량 스토어를 직접 알 필요는 없습니다.
/// 한도에 걸렸을 때 리셋 시각 하나만 있으면 되므로, 그것만 꺼내 둡니다.
///
/// 왜 필요한가: `rate_limit` 이라는 코드만 보여주면 사용자는
/// **언제까지 못 쓰는지** 알 수 없습니다. 그게 유일하게 쓸모 있는 정보인데요.
enum UsageSnapshot {

    nonisolated(unsafe) private static var _nextReset: Date?
    private static let lock = NSLock()

    /// 지금 걸려 있는 한도 중 **가장 먼저** 풀리는 시각.
    static var nextReset: Date? {
        lock.lock(); defer { lock.unlock() }
        guard let d = _nextReset, d > Date() else { return nil }
        return d
    }

    /// 사용량이 갱신될 때마다 스토어가 알려줍니다.
    static func update(from quotas: [UsageQuota]) {
        // 이미 다 쓴 한도들 중 가장 빨리 풀리는 것.
        let blocked = quotas
            .filter { ($0.barFraction ?? 0) >= 0.99 }
            .compactMap(\.resetsAt)
            .filter { $0 > Date() }

        lock.lock()
        _nextReset = blocked.min()
        lock.unlock()
    }
}
