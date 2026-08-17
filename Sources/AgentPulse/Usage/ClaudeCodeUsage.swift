import Foundation

/// Claude Code 의 실제 토큰 사용량을 로컬 로그에서 읽습니다.
///
/// 출처: `~/.claude/projects/<인코딩된-경로>/<세션uuid>.jsonl`
///
/// 실제 구조 (직접 확인함):
/// ```
/// {"type":"assistant","timestamp":"2026-07-27T...","message":{"usage":{
///    "input_tokens":123,"output_tokens":45,
///    "cache_creation_input_tokens":0,"cache_read_input_tokens":678}}}
/// ```
///
/// ⚠️ 왜 퍼센트가 아니라 절대량인가:
/// Anthropic 은 플랜별 한도를 **숫자로 공개하지 않습니다.** 2025년 7월에 잠깐
/// 공개했다가 전부 내렸습니다. 분모를 모르는 채로 만든 퍼센트는 추측이지 정보가 아닙니다.
enum ClaudeCodeUsage {

    private static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    static func currentBlock() -> UsageQuota? {
        // (시각, 토큰, 프로젝트)
        var turns: [(Date, Int, String)] = []
        let decoder = JSONDecoder()

        UsageBlock.scanRecentLines(root: projectsRoot,
                                   modifiedWithin: UsageBlock.duration * 2) { line, url in
            guard let row = try? decoder.decode(Row.self, from: line),
                  let usage = row.message?.usage,
                  let ts = UsageBlock.date(from: row.timestamp) else { return }
            let tokens = usage.total
            guard tokens > 0 else { return }
            // cwd 가 있으면 그걸 씁니다 — 유추가 아니라 사실입니다.
            let project = row.cwd.flatMap { AgentSession.projectName(from: $0) }
                ?? projectName(of: url)
            turns.append((ts, tokens, project))
        }

        guard !turns.isEmpty else {
            apLog("Claude Code: 최근 로그에서 사용량 항목을 찾지 못했습니다")
            return nil
        }
        guard let blockStart = UsageBlock.start(from: turns.map(\.0), anchorKey: "usageAnchor.claudeCode") else { return nil }

        let inBlock = turns.filter { $0.0 >= blockStart }
        let total = inBlock.reduce(0) { $0 + $1.1 }
        let breakdown = Self.summarize(inBlock)

        apLog("Claude Code: 항목 \(turns.count)개 중 이번 블록 \(inBlock.count)개, \(total) 토큰")

        // ⚠️ 이번 구간에 아무것도 안 썼어도 **줄은 남깁니다.**
        //    예전엔 0 이면 통째로 숨겼는데, 그러면 화면에서 Claude 가
        //    사라져서 "왜 안 보이지?" 가 됩니다.
        //    `used 0 tokens` 는 "안 썼다" 는 **정보**입니다 — 없는 것과 다릅니다.
        //    (로그를 아예 못 찾은 경우는 위에서 이미 nil 로 빠집니다.)

        return UsageQuota(
            provider: .claudeCode,
            label: "5h block",   // displayLabel 이 있으면 이 값은 안 쓰입니다
            measure: .count(used: total, unit: "tokens"),
            resetsAt: blockStart.addingTimeInterval(UsageBlock.duration),
            windowStart: blockStart,
            breakdown: breakdown,
            planTier: PlanTier.current()
        )
    }

    // MARK: - 프로젝트별 집계

    /// 폴더 이름에서 프로젝트를 유추합니다. **최후의 수단입니다.**
    ///
    /// ⚠️ 이걸로만 판단하면 안 됩니다.
    ///    Claude Code 는 경로를 `-Users-mihyunkim-code-pandas-money` 처럼
    ///    인코딩하는데 **`/` 도 `-` 로 바뀝니다.** 그래서 마지막 마디를 떼면
    ///    `pandas-money` 가 `money` 가 됩니다. 하이픈이 든 이름은 전부 잘립니다.
    ///    (실제로 화면에 `money` 라고 나왔습니다.)
    ///
    ///    로그 안에 `cwd` 가 그대로 들어 있으므로 그걸 먼저 씁니다.
    ///    이 함수는 `cwd` 가 없는 예전 로그를 위한 폴백입니다.
    private static func projectName(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().lastPathComponent
        // 마디를 쪼개지 않고, 홈 경로 접두사만 걷어냅니다.
        let user = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        let prefix = "-Users-\(user)-"
        if folder.hasPrefix(prefix) {
            let rest = String(folder.dropFirst(prefix.count))
            // `code-pandas-money` → 마지막 두 마디까지만 보여주면 대개 맞습니다.
            return rest.isEmpty ? folder : rest
        }
        return folder
    }

    /// 많이 쓴 순으로 정리합니다.
    ///
    /// ⚠️ 상위 5개까지만 남기고 나머지는 "기타" 로 접습니다.
    ///    항목이 많아지면 읽는 데 시간이 걸리고, 꼬리 쪽은 어차피 의미가 없습니다.
    private static func summarize(_ turns: [(Date, Int, String)]) -> [UsageQuota.Slice] {
        var totals: [String: Int] = [:]
        for (_, tokens, project) in turns { totals[project, default: 0] += tokens }

        let sorted = totals.map { UsageQuota.Slice(name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        guard sorted.count > 5 else { return sorted }
        let head = Array(sorted.prefix(5))
        let rest = sorted.dropFirst(5).reduce(0) { $0 + $1.tokens }
        return head + [UsageQuota.Slice(name: "…", tokens: rest)]
    }

    // MARK: - 스키마 (필요한 부분만)

    private struct Row: Decodable {
        let timestamp: String?
        let message: Message?
        /// 이 턴이 어느 폴더에서 돌았는지. 프로젝트 이름의 **정확한** 출처입니다.
        let cwd: String?

        struct Message: Decodable { let usage: Usage? }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?

            /// 캐시 읽기까지 포함합니다 — Anthropic 도 한도 계산에 넣습니다.
            var total: Int {
                // ⚠️ `cache_read_input_tokens` 는 **더하지 않습니다.**
                //
                //    캐시에서 읽은 건 앞 맥락을 다시 보낸 것입니다. 대화가 길어질수록
                //    턴마다 같은 토큰이 계속 쌓여서, 실제로 한 일보다 몇 배 큰
                //    숫자가 나옵니다. (Codex 쪽에서 하루치를 재보니 171K 중 145K 가
                //    이것이었습니다.)
                //
                //    `cache_creation` 은 더합니다 — 새로 쓴 내용이라 진짜 한 일입니다.
                (input_tokens ?? 0) + (output_tokens ?? 0)
                    + (cache_creation_input_tokens ?? 0)
            }
        }
    }
}
