import Foundation
import SwiftUI

/// 하단 usage 블록에 들어가는 한 줄.
///
/// ⚠️ 설계 원칙 — **모르는 건 모른다고 표시합니다.**
///
/// 예전 버전은 전부 `62%` 같은 가짜 퍼센트였습니다. 퍼센트를 보여주려면
/// 분모(한도)를 알아야 하는데, Anthropic 도 OpenAI 도 **숫자 한도를 공개하지 않습니다.**
/// (2025년 7월엔 공개했다가 지금은 전부 내렸습니다.)
///
/// 모르는 분모로 만든 막대는 그럴듯해 보이지만 거짓말이고,
/// 사용자가 그걸 믿고 작업 계획을 세우면 배신당합니다.
/// 그래서 퍼센트는 **제공자가 직접 준 경우에만** 씁니다.
struct UsageQuota: Identifiable, Codable, Equatable {
    var id: String { "\(provider.rawValue):\(label)" }

    let provider: Provider
    /// "5h block", "Session", "Weekly"
    let label: String
    /// 어떻게 표시할 것인가.
    let measure: Measure
    /// 리셋 시각. nil 이면 모릅니다 — 절대 추측해서 표시하지 않습니다.
    var resetsAt: Date?
    /// 사용량 구간이 시작된 시각. 라벨을 만드는 데 씁니다.
    var windowStart: Date?

    /// 어느 기간의 사용량인가.
    ///
    /// ⚠️ 숫자만 보여주면 "하루야 일주일이야?" 라는 질문이 바로 나옵니다.
    /// 기준을 모르는 숫자는 정보가 아닙니다.
    /// `UsageQuota` 가 저장되므로 `Codable` 이어야 합니다.
    /// 나중에 기준이 추가되면 예전 저장 파일이 못 읽히지 않도록
    /// 문자열 값을 명시해 둡니다.
    enum Scope: String, Codable {
        /// 리셋 시각으로 기간이 드러나는 경우 (Claude Code 의 5시간 구간).
        case window
        /// 자정부터 지금까지.
        case today
    }
    var scope: Scope = .window

    /// 프로젝트별 소비 내역. 많이 쓴 순.
    ///
    /// ⚠️ 왜 넣었나: 총량만 보면 "많이 썼네" 로 끝납니다.
    /// 어느 작업이 태웠는지 알면 다음에 어디를 아낄지 판단할 수 있습니다.
    /// 다만 **접어둡니다** — 흘긋 보는 자리에 기본으로 있으면 시끄럽습니다.
    struct Slice: Identifiable, Codable, Equatable {
        var name: String
        var tokens: Int
        var id: String { name }
    }
    var breakdown: [Slice] = []

    /// 요금제 등급. 한도 숫자는 모르지만 **어느 기준인지**는 알 수 있습니다.
    var planTier: String?
    /// 이 값을 언제 읽었는가. 오래되면 흐리게 표시합니다.
    var readAt: Date = Date()

    /// 읽은 지 오래됐는가.
    ///
    /// 브라우저에서 오는 값은 우리가 부를 수 없어서, 탭이 닫혀 있으면
    /// 갱신이 멈춥니다. 그때 옛날 숫자를 **똑같이 선명하게** 보여주면
    /// 지금 값인 줄 압니다. 흐리게 해서 "이건 좀 됐다" 를 알립니다.
    var isStale: Bool { Date().timeIntervalSince(readAt) > 20 * 60 }

    enum Measure: Codable, Equatable {
        /// 제공자가 준 진짜 퍼센트. 막대를 그립니다.
        case percent(Double)              // 0.0 ~ 1.0
        /// 우리가 센 절대량. 분모를 모르므로 막대를 안 그립니다.
        case count(used: Int, unit: String)
    }

    enum Provider: String, Codable, CaseIterable {
        case claudeCode
        case codex
        case claudeWeb
        case openai

        var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex:      "Codex"
            // ⚠️ 이 한도는 claude.ai 웹 전용이 아닙니다.
            //    `/api/organizations/<org>/usage` 는 **계정 전체** 한도를 줍니다 —
            //    Claude Code 로 쓴 것도 여기 포함됩니다.
            //    그냥 "Claude" 라고 쓰면 바로 위의 "Claude Code" 와 별개인 것처럼
            //    읽혀서, 두 섹션이 왜 따로 있는지 헷갈립니다. (실제로 그 질문이 나왔습니다.)
            case .claudeWeb:  "Claude account"
            case .openai:     "ChatGPT"
            }
        }

        /// 회사 이름. 섹션 헤더에 씁니다.
        var vendorName: String {
            switch self {
            case .claudeCode, .claudeWeb: "Claude"
            case .codex, .openai:         "OpenAI"
            }
        }

        /// 어느 회사 것인가. 화면에서 구분선을 넣는 기준입니다.
        var vendor: String {
            switch self {
            case .claudeCode, .claudeWeb: "anthropic"
            case .codex, .openai:         "openai"
            }
        }

        /// 번역이 필요한 이름.
        ///
        /// ⚠️ `displayName` 에 한국어를 그대로 박아뒀다가, 영어 설정에서도
        ///    `Claude 계정` 이 나왔습니다. 브랜드명(Claude Code, Codex)은
        ///    번역하지 않지만 **우리가 붙인 말은 번역해야 합니다.**
        func displayName(_ loc: Loc) -> String {
            switch self {
            case .claudeWeb: loc("Claude account", "Claude 계정")
            default:         displayName
            }
        }

        /// 내역 막대 색. **브랜드당 한 가지만** 씁니다.
        /// 항목마다 색을 바꾸면 색이 순위를 뜻하는 것처럼 읽혀서 거짓말이 됩니다.
        /// 길이가 이미 크기를 말하므로 색은 "누구 것인가" 만 담당합니다.
        var tint: Color {
            switch self {
            case .claudeCode, .claudeWeb: .hex(0xD97757)
            case .codex, .openai:         .hex(0x10A37F)
            }
        }

        var iconAgent: AgentKind {
            switch self {
            case .claudeCode: .claudeCode
            case .codex:      .codex
            case .claudeWeb:  .claudeWeb
            case .openai:     .chatgptWeb
            }
        }
    }

    /// 왼쪽에 보여줄 라벨.
    ///
    /// ⚠️ 두 번 실패한 자리입니다.
    ///   1차: `5h block` → "무슨 뜻이야?" (도구 용어를 그대로 가져옴)
    ///   2차: `Since 10:00 AM` → "**뭐가** 10시에 시작했다는 거야? UTC야?"
    ///
    /// 교훈: 사용자가 이 줄에서 알고 싶은 건 **얼마나 썼고 언제 초기화되나** 입니다.
    /// 구간이 언제 시작했는지는 부차적이라 툴팁으로 내렸습니다.
    func displayLabel(_ loc: Loc) -> String {
        // 브라우저에서 온 진짜 한도는 기간이 이름에 들어 있습니다.
        // ⚠️ 기간을 그대로 씁니다.
        //    `Session` 은 "무슨 세션?" 이라는 질문을 낳습니다 —
        //    `5h block` 이 무슨 뜻이냐고 물었던 것과 같은 문제입니다.
        //    두 항목이 나란히 있을 때 `5시간` / `주간` 이면 관계가 바로 읽힙니다.
        switch label {
        case "session": return loc("5-hour", "5시간")
        case "weekly":  return loc("Weekly", "주간")
        case "credits": return loc("Credits", "크레딧")
        default:        return loc("Used", "사용량")
        }
    }

    /// 마우스를 올렸을 때 나오는 자세한 설명.
    /// 시간은 전부 이 Mac 의 로컬 시간입니다.
    func tooltip(_ loc: Loc) -> String {
        if scope == .today {
            return loc("Tokens used since midnight. OpenAI removed the 5-hour window in July 2026, and the weekly reset time isn't available locally.",
                       "자정부터 지금까지 쓴 토큰입니다. OpenAI 가 2026년 7월에 5시간 창을 없앴고, 주간 리셋 시각은 로컬에서 알 수 없습니다.")
        }
        guard let windowStart, let resetsAt else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: loc.language == .korean ? "ko_KR" : "en_US")
        f.setLocalizedDateFormatFromTemplate("j:mm")
        let from = f.string(from: windowStart)
        let to = f.string(from: resetsAt)

        return loc("Usage resets every 5 hours. This window: \(from)–\(to) (local time).",
                   "사용량은 5시간마다 초기화됩니다. 이번 구간: \(from)–\(to) (현지 시간).")
    }

    /// 이 구간이 이미 끝났는가.
    ///
    /// ⚠️ 사용량은 1분마다 다시 읽지만 화면은 계속 그려집니다.
    /// 그 사이에 구간이 끝나면 `resets in 0m` 이라는 **말이 안 되는 문구**가
    /// 최대 1분 동안 남습니다. 숫자도 지난 구간 것이라 틀립니다.
    var isExpired: Bool {
        guard let resetsAt else { return false }
        return resetsAt <= Date()
    }

    /// 오른쪽에 보여줄 문자열.
    func valueText(_ loc: Loc) -> String {
        // 구간이 끝났으면 지난 숫자를 보여주지 않습니다.
        // 곧 새로 읽어올 값이 오므로 그때까지 그렇게 말해줍니다.
        if isExpired {
            return loc("starting a new window…", "새 구간 시작 중…")
        }

        var parts: [String] = []

        switch measure {
        case .percent(let f):
            // 퍼센트는 막대 옆에 붙으므로 숫자만. 리셋 시각은 툴팁에 있습니다.
            return "\(Int((f * 100).rounded()))%"
        case .count(let used, let unit):
            // ⚠️ **쓴 양인지 남은 양인지 말해줘야 합니다.**
            //    `600K tokens` 만 보면 알 수 없습니다. 실제로 그 질문이 나왔습니다.
            //    리셋 시각이 옆에 있으면 문맥으로 짐작할 수 있지만,
            //    Codex 처럼 리셋이 없으면 단서가 아예 없습니다.
            //
            //    "남은 양" 은 한도를 모르니 애초에 쓸 수 없고,
            //    우리가 아는 건 쓴 양 하나뿐이므로 그걸 분명히 밝힙니다.
            let amount = "\(Self.compact(used)) \(unit)"
            switch scope {
            case .window:
                // 옆에 붙는 `resets in …` 이 기간을 알려줍니다.
                parts.append(loc("used \(amount)", "\(amount) 사용"))
            case .today:
                // 리셋 시각이 없으니 기간을 직접 말합니다.
                parts.append(loc("used \(amount) today", "오늘 \(amount) 사용"))
            }
        }

        if let resetsAt {
            let remaining = resetsAt.timeIntervalSinceNow
            if remaining > 0 {
                let d = remaining.shortDuration(loc)
                parts.append(loc("resets in \(d)", "\(d) 후 리셋"))
            } else {
                parts.append(loc("resetting…", "리셋 중…"))
            }
        }

        return parts.joined(separator: " · ")
    }

    /// 막대는 진짜 퍼센트가 있을 때만 그립니다.
    var barFraction: Double? {
        if case .percent(let f) = measure { return max(0, min(1, f)) }
        return nil
    }

    /// 1_234_567 → "1.2M"
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     String(format: "%.0fK", Double(n) / 1_000)
        default:           "\(n)"
        }
    }
}

/// 프로바이더별로 묶은 usage.
/// 하단 사용량 블록의 한 덩어리.
///
/// ⚠️ **회사 단위**로 묶습니다. 프로바이더 단위가 아닙니다.
///
/// 예전엔 `Claude Code` 와 `Claude account` 가 따로 있었는데, 둘 다 같은
/// 계정 얘기입니다 — 계정 한도에는 Claude Code 로 쓴 것도 포함되고요.
/// 두 섹션으로 나눠 놓으니 관계가 안 보이고 자리만 두 배로 먹었습니다.
struct UsageGroup: Identifiable, Equatable {
    var id: String { vendor }
    let vendor: String
    /// 헤더에 쓸 이름과 로고.
    let provider: UsageQuota.Provider
    let quotas: [UsageQuota]

    /// 퍼센트로 오는 것 — 계정 한도. 막대로 그립니다.
    var meters: [UsageQuota] { quotas.filter { $0.barFraction != nil } }
    /// 개수로 오는 것 — 도구별 토큰 사용량.
    var counters: [UsageQuota] { quotas.filter { $0.barFraction == nil } }
}
