import Foundation

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

    static func all(_ loc: Loc) -> [Surface] {
        [
            Surface(id: "claudeCode",
                    name: "Claude Code",
                    connected: claudeCodeHooksInstalled,
                    hint: loc("run install-claude-hooks.sh", "install-claude-hooks.sh 실행 필요")),
            Surface(id: "codex",
                    name: "Codex",
                    connected: codexNotifyInstalled,
                    hint: loc("run install-codex-notify.sh", "install-codex-notify.sh 실행 필요")),
            Surface(id: "browser",
                    name: loc("Browser tabs", "브라우저 탭"),
                    connected: browserExtensionSeen,
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

    /// 크롬 확장에서 이벤트를 **한 번이라도** 받아본 적이 있는가.
    ///
    /// 확장은 설치 여부를 파일로 알 수 없으므로, 실제로 통신이 있었는지로 판단합니다.
    /// 이게 더 정확하기도 합니다 — 설치돼 있어도 토큰이 틀리면 무용지물이니까요.
    static var browserExtensionSeen: Bool {
        UserDefaults.standard.bool(forKey: browserSeenKey)
    }

    static func markBrowserSeen() {
        guard !browserExtensionSeen else { return }
        UserDefaults.standard.set(true, forKey: browserSeenKey)
        apLog("크롬 확장 연결 확인됨")
    }

    private static let browserSeenKey = "browserExtensionSeen"

    private static func contains(path: String, needle: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(needle)
    }
}
