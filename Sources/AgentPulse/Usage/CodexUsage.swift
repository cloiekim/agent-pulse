import Foundation

/// Codex CLI 의 실제 토큰 사용량을 로컬 rollout 로그에서 읽습니다.
///
/// 출처: `~/.codex/sessions/YYYY/MM/DD/rollout-<시각>-<uuid>.jsonl`
///
/// 실제 구조 (직접 확인함):
/// ```
/// {"timestamp":"2026-07-27T16:03:03.068Z","type":"event_msg","payload":{
///    "info":{
///      "total_token_usage":{"input_tokens":21434,"cached_input_tokens":21248,
///                           "cache_write_input_tokens":0,"output_tokens":97,
///                           "reasoning_output_tokens":0,"total_tokens":21531},
///      "last_token_usage":{...}
///    }}}
/// ```
///
/// `total_token_usage` 는 **세션 누적**이라 블록 계산에 못 씁니다
/// (세션이 블록 경계를 넘나들면 이중 계산됩니다).
/// `last_token_usage` 는 **그 턴만**이라 타임스탬프로 거른 뒤 더하면 정확합니다.
enum CodexUsage {

    private static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    static func currentBlock() -> UsageQuota? {
        var turns: [(Date, Int)] = []
        let decoder = JSONDecoder()

        UsageBlock.scanRecentLines(root: sessionsRoot,
                                   modifiedWithin: UsageBlock.duration * 2) { line in
            guard let row = try? decoder.decode(Row.self, from: line),
                  row.type == "event_msg",
                  let tokens = row.payload?.info?.last_token_usage?.total_tokens,
                  tokens > 0,
                  let ts = UsageBlock.date(from: row.timestamp) else { return }
            turns.append((ts, tokens))
        }

        guard !turns.isEmpty else { return nil }

        // ⚠️ 기준은 **오늘(자정부터)** 입니다.
        //
        //    처음엔 5시간 구간으로 잘랐습니다. 그런데 OpenAI 가 2026-07-12 에
        //    5시간 창을 없애서(주간 한도만 남김) 그 구간에 아무 근거가 없어졌습니다.
        //    리셋 표시만 지우고 계산은 5시간으로 남겨뒀더니, **기준을 알 수 없는
        //    숫자**가 됐습니다. "이게 하루야 일주일이야?" 라는 질문이 바로 나왔습니다.
        //
        //    주간 한도의 시작 시각은 로컬 로그로 알 수 없습니다.
        //    그래서 설명할 수 있는 단위를 씁니다 — 오늘 자정부터 지금까지.
        let dayStart = Calendar.current.startOfDay(for: Date())
        let today = turns.filter { $0.0 >= dayStart }
        let total = today.reduce(0) { $0 + $1.1 }
        apLog("Codex: 항목 \(turns.count)개 중 오늘 \(today.count)개, \(total) 토큰")
        guard total > 0 else { return nil }

        return UsageQuota(
            provider: .codex,
            label: "today",   // displayLabel 이 있으면 이 값은 안 쓰입니다
            measure: .count(used: total, unit: "tokens"),
            // ⚠️ Codex 는 리셋 시각을 표시하지 않습니다.
            //
            //    OpenAI 가 2026-07-12 에 5시간 창을 없앴습니다 (주간 한도만 남김).
            //    그런데 우리 코드는 "Anthropic·OpenAI 모두 5시간" 이라고 박아두고
            //    Codex 에도 5시간을 적용해서, `1시간 8분 후 리셋` 같은
            //    **우리가 지어낸 숫자**를 보여주고 있었습니다.
            //
            //    주간 한도의 시작 시각은 로컬 로그로 알 수 없습니다.
            //    모르는 걸 지어내지 않습니다 — 사용량만 보여줍니다.
            resetsAt: nil,
            windowStart: nil,
            scope: .today
        )
    }

    // MARK: - 스키마 (필요한 부분만)

    private struct Row: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?

        struct Payload: Decodable { let info: Info? }
        struct Info: Decodable { let last_token_usage: Tokens? }
        struct Tokens: Decodable { let total_tokens: Int? }
    }
}
