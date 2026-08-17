import Foundation
import AppKit

/// 각 표면이 실제로 연결돼 있는지 확인합니다.
///
/// ⚠️ 왜 필요한가:
/// 예전 빈 화면은 "Open ChatGPT ↗" 버튼을 띄웠습니다. 그런데
/// **왜 하필 ChatGPT 인지 이유가 없었고**, 애초에 "아무것도 안 돌고 있음" 은
/// 고쳐야 할 문제가 아닙니다 — 조용한 게 정상입니다.
///
/// 사용자가 정말 알고 싶은 건 다른 겁니다:
/// **"이게 지금 제대로 보고 있긴 한 건가?"**
///
/// 실제로 이 앱을 만들면서도 그걸 몰라서 여러 번 헤맸습니다.
/// 그래서 빈 화면을 연결 상태 점검표로 바꿉니다.
enum ConnectionStatus {

    struct Surface: Identifiable {
        let id: String
        let name: String
        let connected: Bool
        /// 연결이 안 됐을 때 무엇을 해야 하는지.
        let hint: String?
    }

    /// 끊긴 것들만. 배너에 씁니다.
    ///
    /// ⚠️ **한 번도 안 쓴 도구는 여기 안 들어갑니다.** Codex 를 안 쓰는 사람에게
    ///    "Codex 연결 안 됨" 은 고장 신고가 아니라 잔소리입니다.
    ///    브라우저는 예전에 붙어 있었던 경우에만(`browserExtensionSeen`) 셉니다.
    static func broken(_ loc: Loc) -> [Surface] {
        surfaces(loc).filter { surface in
            guard !surface.connected else { return false }
            return surface.id == "browser" ? browserExtensionSeen : everInstalled(surface.id)
        }
    }

    /// 예전에 설치한 적이 있는가 (설정 파일이 남아 있는가).
    private static func everInstalled(_ id: String) -> Bool {
        switch id {
        case "claudeCode":  fileExists(".claude/settings.json")
        case "codex":       fileExists(".codex/config.toml")
        case "antigravity": fileExists(".gemini/config/hooks.json")
        default:            false
        }
    }

    private static func fileExists(_ path: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func all(_ loc: Loc) -> [Surface] {
        // ⚠️ 연결된 것을 위로 올립니다.
        //    안 된 것이 중간에 끼면 목록이 "고장난 것들" 처럼 읽힙니다.
        //    잘 되고 있는 걸 먼저 보여주고, 손볼 게 있으면 아래에 모읍니다.
        surfaces(loc).sorted { $0.connected && !$1.connected }
    }

    private static func surfaces(_ loc: Loc) -> [Surface] {
        [
            Surface(id: "claudeCode",
                    name: "Claude Code",
                    connected: claudeCodeHooksInstalled,
                    hint: loc("run install-claude-hooks.sh", "install-claude-hooks.sh 실행 필요")),
            Surface(id: "codex",
                    name: "Codex",
                    connected: codexNotifyInstalled,
                    hint: loc("run install-codex-notify.sh", "install-codex-notify.sh 실행 필요")),
            Surface(id: "antigravity",
                    name: "Antigravity",
                    connected: antigravityHooksInstalled,
                    hint: loc("run install-antigravity-hooks.sh", "install-antigravity-hooks.sh 실행 필요")),
            Surface(id: "browser",
                    name: loc("Browser tabs", "브라우저 탭"),
                    connected: browserConnected,
                    hint: loc("install the Chrome extension", "크롬 확장 설치 필요")),
        ]
    }

    // MARK: - 개별 점검

    /// `~/.claude/settings.json` 에 우리 훅이 들어 있는가.
    static var claudeCodeHooksInstalled: Bool {
        contains(path: ".claude/settings.json", needle: "/hook/claude")
    }

    /// `~/.codex/config.toml` 에 우리 설정이 들어 있는가.
    ///
    /// ⚠️ 설치 스크립트와 **같은 표시**를 봐야 합니다.
    ///    스크립트는 `# --- agent-pulse ---` 라는 구분선을 넣는데,
    ///    앱은 `agent-pulse-notify`(파일 이름)를 찾고 있었습니다.
    ///    경로에 그 문자열이 없으면 둘의 판정이 엇갈립니다 —
    ///    스크립트는 "이미 설치됨", 앱은 "미설치" 라고 서로 다른 말을 합니다.
    ///    실제로 그 상황이 나왔습니다.
    static var codexNotifyInstalled: Bool {
        contains(path: ".codex/config.toml", needle: "--- agent-pulse ---")
    }

    /// `~/.gemini/config/hooks.json` 에 우리 브릿지가 걸려 있는가.
    static var antigravityHooksInstalled: Bool {
        contains(path: ".gemini/config/hooks.json", needle: "agent-pulse-antigravity")
    }

    /// 크롬 확장에서 이벤트를 **한 번이라도** 받아본 적이 있는가.
    ///
    /// 확장은 설치 여부를 파일로 알 수 없으므로, 실제로 통신이 있었는지로 판단합니다.
    /// 이게 더 정확하기도 합니다 — 설치돼 있어도 토큰이 틀리면 무용지물이니까요.
    static var browserExtensionSeen: Bool {
        UserDefaults.standard.bool(forKey: browserSeenKey)
    }

    /// 마지막으로 확장에게서 무언가 받은 시각.
    static var browserLastSeen: Date? {
        let t = UserDefaults.standard.double(forKey: browserLastSeenKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// **지금** 확장이 붙어 있는가.
    ///
    /// ⚠️ 예전엔 `browserExtensionSeen` 불리언 하나만 봤습니다. 한 번 true 가
    ///    되면 영원히 true 라, 확장이 통째로 사라져도 앱은 계속 "연결됨" 이라고
    ///    믿었습니다. 실제로 크롬 업데이트에 확장이 날아갔는데 앱은 아무 말도
    ///    안 했고, "왜 안 되지" 를 사람이 직접 찾아야 했습니다.
    ///
    ///    확장은 크롬이 떠 있는 동안 5분마다 `/hook/ping` 을 보냅니다.
    ///    그래서 **크롬이 실행 중인데** 15분 넘게 조용하면 끊긴 것으로 봅니다.
    ///
    ///    크롬이 꺼져 있으면 판단하지 않습니다 — 안 들리는 게 정상이니까요.
    ///    모르는 걸 "끊겼다" 고 말하면 그게 더 나쁜 오탐입니다.
    static var browserConnected: Bool {
        guard browserExtensionSeen else { return false }
        guard chromeRunning else { return true }   // 판단 보류
        guard let last = browserLastSeen else { return false }
        return Date().timeIntervalSince(last) < browserSilenceLimit
    }

    /// 크롬이 지금 실행 중인가.
    static var chromeRunning: Bool {
        let ids = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"]
        return ids.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    }

    /// 확장의 ping 주기(5분)의 세 배. 한 번쯤 놓쳐도 성급하게 굴지 않습니다.
    private static let browserSilenceLimit: TimeInterval = 15 * 60

    static func markBrowserSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: browserLastSeenKey)
        guard !browserExtensionSeen else { return }
        UserDefaults.standard.set(true, forKey: browserSeenKey)
        apLog("크롬 확장 연결 확인됨")
    }

    private static let browserSeenKey = "browserExtensionSeen"
    private static let browserLastSeenKey = "browserLastSeenAt"

    private static func contains(path: String, needle: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(needle)
    }
}
