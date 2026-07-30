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
        var turns: [(Date, Int)] = []
        let decoder = JSONDecoder()

        UsageBlock.scanRecentLines(root: projectsRoot,
                                   modifiedWithin: UsageBlock.duration * 2) { line in
            guard let row = try? decoder.decode(Row.self, from: line),
                  let usage = row.message?.usage,
                  let ts = UsageBlock.date(from: row.timestamp) else { return }
            let tokens = usage.total
            guard tokens > 0 else { return }
            turns.append((ts, tokens))
        }

        guard !turns.isEmpty else {
            apLog("Claude Code: 최근 로그에서 사용량 항목을 찾지 못했습니다")
            return nil
        }
        guard let blockStart = UsageBlock.start(from: turns.map(\.0), anchorKey: "usageAnchor.claudeCode") else { return nil }

        let inBlock = turns.filter { $0.0 >= blockStart }
        let total = inBlock.reduce(0) { $0 + $1.1 }

        apLog("Claude Code: 항목 \(turns.count)개 중 이번 블록 \(inBlock.count)개, \(total) 토큰")
        guard total > 0 else { return nil }

        return UsageQuota(
            provider: .claudeCode,
            label: "5h block",   // displayLabel 이 있으면 이 값은 안 쓰입니다
            measure: .count(used: total, unit: "tokens"),
            resetsAt: blockStart.addingTimeInterval(UsageBlock.duration),
            windowStart: blockStart
        )
    }

    // MARK: - 스키마 (필요한 부분만)

    private struct Row: Decodable {
        let timestamp: String?
        let message: Message?

        struct Message: Decodable { let usage: Usage? }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?

            /// 캐시 읽기까지 포함합니다 — Anthropic 도 한도 계산에 넣습니다.
            var total: Int {
                (input_tokens ?? 0) + (output_tokens ?? 0)
                    + (cache_creation_input_tokens ?? 0) + (cache_read_input_tokens ?? 0)
            }
        }
    }
}
