import Foundation

/// 어느 요금제 기준으로 한도가 걸리는지.
///
/// ⚠️ 한도 **숫자**는 여전히 모릅니다.
///
/// Claude Code 는 주간 한도 경고를 띄우지만, 그 숫자와 리셋 시각을 로컬에
/// 저장하지 않습니다. API 응답에서 받아 화면에만 쓰고 버립니다.
/// 세 번 뒤져서 확인했습니다 — `stats-cache.json`, `~/.claude/`, `~/.claude.json`
/// 어디에도 없습니다.
///
/// 대신 **요금제 등급은 저장돼 있습니다**:
///   `~/.claude.json` → `oauthAccount.organizationRateLimitTier`
///
/// 이건 사실이므로 보여줄 수 있습니다. 숫자를 지어내는 것과 다릅니다.
/// "내가 Max 5x 인데 이만큼 썼다" 는 정보가, 아무 기준 없이 숫자만 보는 것보다 낫습니다.
enum PlanTier {

    /// 예: "Max 5x", "Pro". 모르면 nil — 모르는 건 표시하지 않습니다.
    static func current() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return nil }

        // 조직 등급이 먼저, 없으면 개인 등급.
        let raw = (account["organizationRateLimitTier"] as? String)
            ?? (account["userRateLimitTier"] as? String)
        return raw.flatMap(prettify)
    }

    /// `default_claude_max_5x` → `Max 5x`
    ///
    /// 모르는 형식이면 **nil 을 돌려줍니다.** 억지로 예쁘게 만들다
    /// 엉뚱한 이름을 보여주느니 아무것도 안 보여주는 게 낫습니다.
    private static func prettify(_ raw: String) -> String? {
        let s = raw.lowercased()
        if s.contains("max") {
            if s.contains("20x") { return "Max 20x" }
            if s.contains("5x")  { return "Max 5x" }
            return "Max"
        }
        if s.contains("team")       { return "Team" }
        if s.contains("enterprise") { return "Enterprise" }
        if s.contains("pro")        { return "Pro" }
        if s.contains("free")       { return "Free" }
        return nil
    }
}
