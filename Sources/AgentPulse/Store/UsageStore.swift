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
    /// 로컬에서 읽는 값(Claude Code·Codex)이 이만큼 안 오면 버립니다.
    /// 이것들은 1분마다 다시 읽으므로, 30분간 없으면 진짜로 없는 겁니다.
    private let staleAfter: TimeInterval = 30 * 60

    private var quotas: [String: UsageQuota] = [:]   // id -> quota
    private var timer: Timer?

    /// 보여줄 게 하나도 없으면 UI 에서 블록 자체를 숨깁니다.
    var isEmpty: Bool { groups.isEmpty }

    func start() {
        restoreExternal()
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
        saveExternal()
        rebuild()
    }

    // MARK: - 확장이 준 값 기억하기
    //
    // ⚠️ 확장이 보내준 사용량은 메모리에만 있었습니다.
    //    앱을 다시 띄우면 사라지고, claude.ai 탭이 새로 로드될 때까지
    //    빈 자리로 남습니다. 실제로 "사용량 디자인이 없어졌다" 가 나왔습니다.
    //
    //    로컬 로그에서 읽는 값(Claude Code·Codex)은 매분 다시 읽으니 괜찮지만,
    //    브라우저에서 오는 값은 **우리가 부를 수 없습니다.** 기억해둬야 합니다.
    //
    //    다만 오래된 값은 거짓이 될 수 있으므로, 하루 지난 건 버립니다.

    private static let externalKey = "externalQuotas"
    private let externalTTL: TimeInterval = 24 * 60 * 60

    private func saveExternal() {
        // 로컬에서 읽는 것들은 저장할 필요가 없습니다.
        let external = quotas.values.filter { $0.provider == .claudeWeb || $0.provider == .openai }
        guard let data = try? JSONEncoder().encode(Array(external)) else { return }
        UserDefaults.standard.set(data, forKey: Self.externalKey)
    }

    private func restoreExternal() {
        guard let data = UserDefaults.standard.data(forKey: Self.externalKey),
              let saved = try? JSONDecoder().decode([UsageQuota].self, from: data)
        else { return }

        let now = Date()
        for quota in saved where now.timeIntervalSince(quota.readAt) < externalTTL {
            quotas[quota.id] = quota
        }
        if !saved.isEmpty { apLog("저장된 사용량 복원: \(quotas.count)개") }
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
        // ⚠️ 브라우저에서 온 값은 **다르게 다룹니다.**
        //
        //    로컬 값은 우리가 매분 다시 읽으니 오래되면 진짜 없는 겁니다.
        //    하지만 브라우저 값은 **우리가 부를 수 없습니다** — claude.ai 탭이
        //    떠 있어야 옵니다. 탭을 닫아뒀다고 한도가 사라진 게 아닌데
        //    30분 만에 지워버리면 화면에서 통째로 없어집니다.
        //    (실제로 "주간이 갑자기 안 나온다" 가 나왔습니다.)
        //
        //    저장은 24시간인데 정리는 30분이라 서로 모순이었습니다.
        //    브라우저 값은 오래돼도 남기고, 흐리게 표시해서 알립니다 (isStale).
        let localCutoff = Date().addingTimeInterval(-staleAfter)
        let externalCutoff = Date().addingTimeInterval(-externalTTL)

        quotas = quotas.filter { _, quota in
            let fromBrowser = quota.provider == .claudeWeb || quota.provider == .openai
            return quota.readAt > (fromBrowser ? externalCutoff : localCutoff)
        }

        // 회사 단위로 묶습니다. 같은 계정 얘기를 두 섹션으로 나누지 않습니다.
        let order: [UsageQuota.Provider] = [.claudeWeb, .claudeCode, .codex, .openai]
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        // 퍼센트(계정 한도)가 먼저, 그다음 개수(도구별 사용량).
        // 5시간이 주간보다 위 — 짧은 주기가 먼저입니다.
        func sortKey(_ q: UsageQuota) -> (Int, Int, Int) {
            let isMeter = q.barFraction == nil ? 1 : 0
            let period = switch q.label {
            case "session": 0
            case "weekly":  1
            case "credits": 2   // 크레딧은 마지막 방어선이라 맨 아래
            default:        3
            }
            return (isMeter, period, rank[q.provider] ?? 99)
        }

        let byVendor = Dictionary(grouping: quotas.values) { $0.provider.vendor }

        groups = byVendor
            .map { vendor, items -> UsageGroup in
                let sorted = items.sorted { sortKey($0) < sortKey($1) }
                // 헤더 로고는 그 회사에서 가장 앞선 프로바이더 것을 씁니다.
                let head = sorted.min { (rank[$0.provider] ?? 99) < (rank[$1.provider] ?? 99) }
                return UsageGroup(vendor: vendor,
                                  provider: head?.provider ?? sorted[0].provider,
                                  quotas: sorted)
            }
            .sorted { (rank[$0.provider] ?? 99) < (rank[$1.provider] ?? 99) }

        // 한도에 걸린 세션이 "언제 풀리나" 를 물어볼 수 있게 해둡니다.
        UsageSnapshot.update(from: Array(quotas.values))
    }
}
