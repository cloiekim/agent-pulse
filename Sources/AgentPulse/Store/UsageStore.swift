import Foundation
import Observation

/// 사용량 데이터를 모으는 곳.
///
/// 출처가 둘입니다:
///   1. **로컬** — Claude Code 세션 로그 (1분마다 직접 읽음)
///   2. **크롬 확장** — claude.ai / ChatGPT 가 브라우저에 보내주는 한도 정보
///
/// 2번이 더 정확합니다. 제공자가 직접 준 숫자니까요.
/// 1번은 우리가 세는 거라 절대량만 알고 한도는 모릅니다.
@Observable
@MainActor
final class UsageStore {

    private(set) var groups: [UsageGroup] = []

    /// 이 시간이 지난 데이터는 신뢰하지 않고 버립니다.
    private let staleAfter: TimeInterval = 30 * 60

    private var quotas: [String: UsageQuota] = [:]   // id -> quota
    private var timer: Timer?

    /// 보여줄 게 하나도 없으면 UI 에서 블록 자체를 숨깁니다.
    var isEmpty: Bool { groups.isEmpty }

    func start() {
        refreshLocal()
        lastFullRefresh = Date()
        // 로그를 읽는 비용이 있으므로 평소엔 1분이면 충분합니다.
        //
        // ⚠️ 다만 5시간 구간이 넘어가는 순간엔 1분이 너무 깁니다.
        //    그 사이 화면엔 지난 구간의 숫자와 `resets in 0m` 이 남습니다.
        //    그래서 경계가 가까우면 15초로 좁힙니다.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
    }

    private var lastFullRefresh = Date.distantPast

    /// 15초마다 불리지만, 실제로 다시 읽는 건 필요할 때만입니다.
    private func tick() {
        let now = Date()

        // 구간 경계가 2분 안으로 다가왔거나 이미 지났으면 바로 다시 읽습니다.
        let nearBoundary = quotas.values.contains { quota in
            guard let resetsAt = quota.resetsAt else { return false }
            return resetsAt.timeIntervalSince(now) < 120
        }

        if nearBoundary || now.timeIntervalSince(lastFullRefresh) >= 60 {
            lastFullRefresh = now
            refreshLocal()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 입력

    /// 크롬 확장이 보내온 값.
    func ingest(_ quota: UsageQuota) {
        quotas[quota.id] = quota
        rebuild()
    }

    /// Claude Code 로컬 로그에서 직접 읽기.
    private func refreshLocal() {
        // 파일 I/O 는 메인 스레드에서 하면 안 됩니다.
        Task.detached(priority: .utility) {
            let claude = ClaudeCodeUsage.currentBlock()
            let codex = CodexUsage.currentBlock()

            await MainActor.run {
                // 진단용 — 왜 안 보이는지 알아야 고칠 수 있습니다.
                apLog("사용량 읽기: Claude Code=\(claude.map { "\($0.measure)" } ?? "없음"), Codex=\(codex.map { "\($0.measure)" } ?? "없음")")

                // 최근 활동이 없으면 줄 자체를 없앱니다 — 0 을 보여주면
                // "안 쓰고 있다" 와 "못 읽었다" 를 구분할 수 없습니다.
                self.apply(claude, fallbackID: "claudeCode:5h block")
                self.apply(codex, fallbackID: "codex:5h block")
                self.rebuild()
            }
        }
    }

    private func apply(_ quota: UsageQuota?, fallbackID: String) {
        if let quota {
            quotas[quota.id] = quota
        } else {
            quotas.removeValue(forKey: fallbackID)
        }
    }

    // MARK: - 정리

    private func rebuild() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        quotas = quotas.filter { $0.value.readAt > cutoff }

        groups = UsageQuota.Provider.allCases.compactMap { provider in
            let items = quotas.values
                .filter { $0.provider == provider }
                .sorted { $0.label < $1.label }
            return items.isEmpty ? nil : UsageGroup(provider: provider, quotas: items)
        }
    }
}
