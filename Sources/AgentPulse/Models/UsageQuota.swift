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
            case .claudeWeb:  "Claude"
            case .openai:     "ChatGPT"
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
        loc("Used", "사용량")
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
            parts.append("\(Int((f * 100).rounded()))%")
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
struct UsageGroup: Identifiable, Equatable {
    var id: String { provider.rawValue }
    let provider: UsageQuota.Provider
    let quotas: [UsageQuota]
}
