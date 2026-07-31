import AppKit

/// 연결 안 된 항목을 **눌러서 바로 연결**하게 해줍니다.
///
/// ⚠️ 왜 필요한가:
/// 빈 화면에 "run install-codex-notify.sh" 라고 적어뒀는데, 그걸 보고 사용자는
/// 터미널을 열고, 파일을 찾고, 경로를 맞춰야 합니다. **읽을 수는 있지만
/// 손이 안 가는 안내**입니다.
///
/// 설치 마찰은 테스터를 잃는 가장 흔한 이유고, 여기가 그 마찰이 제일 큰 자리입니다.
enum SetupActions {

    /// 배포 패키지의 루트. `.app` 과 스크립트들이 같이 풀린 폴더입니다.
    ///
    /// 개발 중에는 `.app` 이 `dist/` 안에 없으므로 소스 트리의 `scripts/` 도 봅니다.
    private static var packageRoot: URL? {
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("scripts"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func find(_ name: String) -> URL? {
        // ⚠️ 앱이 /Applications 로 옮겨지면 옆에 스크립트가 없습니다.
        //    그래서 압축을 푼 흔한 위치들도 같이 뒤집니다.
        //    못 찾으면 버튼 대신 "복사" 를 보여줍니다 — 아무것도 못 하는 것보단 낫습니다.
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots: [URL] = []
        if let packageRoot { roots.append(packageRoot) }
        roots += [
            home.appendingPathComponent("Downloads/AgentPulse-test"),
            home.appendingPathComponent("Downloads/AgentPulse"),
            home.appendingPathComponent("code/AgentPulse"),
        ]

        for root in roots {
            for dir in [root, root.appendingPathComponent("scripts")] {
                let url = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    // MARK: - 각 항목의 동작

    static func run(_ surfaceID: String) {
        switch surfaceID {
        case "codex":      installCodex()
        case "antigravity": runScript("install-antigravity-hooks.sh")
        case "claudeCode": installClaudeHooks()
        case "browser":    openExtensionSetup()
        default:           break
        }
    }

    /// 그 항목을 눌러서 해결할 수 있는가. 없으면 버튼으로 만들지 않습니다.
    static func isActionable(_ surfaceID: String) -> Bool {
        switch surfaceID {
        case "codex":      find("install-codex-notify.sh") != nil
        case "antigravity": find("install-antigravity-hooks.sh") != nil
        case "claudeCode": find("install-claude-hooks.sh") != nil
        case "browser":    true
        default:           false
        }
    }

    private static func installCodex() { runScript("install-codex-notify.sh") }

    private static func runScript(_ name: String) {
        guard let script = find(name) else { return }
        runInTerminal(script)
    }

    private static func installClaudeHooks() {
        guard let script = find("install-claude-hooks.sh") else { return }
        runInTerminal(script)
    }

    /// 크롬 확장은 자동 설치가 불가능합니다 (크롬 정책).
    /// 대신 **두 단계를 동시에 열어줍니다** — 설정 페이지와 폴더.
    /// 그러면 사용자가 할 일은 폴더를 끌어다 놓는 것뿐입니다.
    private static func openExtensionSetup() {
        if let folder = find("chrome-extension") {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }

        // ⚠️ `NSWorkspace.open(URL(string: "chrome://extensions"))` 은 동작하지 않습니다.
        //    macOS 는 `chrome://` 스킴을 아무 앱에도 연결해두지 않아서
        //    **조용히 아무 일도 안 일어납니다.** 사용자 눈엔 버튼이 고장난 걸로 보입니다.
        //    크롬을 직접 지정해서 인자로 넘겨야 합니다.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Google Chrome", "chrome://extensions/"]
        do {
            try task.run()
            apLog("확장 설치 안내 열기")
        } catch {
            apLog("크롬 열기 실패: \(error.localizedDescription)")
        }
    }

    /// 눌러서 해결이 안 될 때 사용자가 복사해 갈 명령.
    static func command(for surfaceID: String) -> String? {
        switch surfaceID {
        case "codex":      "./install-codex-notify.sh"
        case "antigravity": "./install-antigravity-hooks.sh"
        case "claudeCode": "./install-claude-hooks.sh"
        default:           nil
        }
    }

    /// 스크립트를 터미널에서 **보이게** 실행합니다.
    ///
    /// 조용히 백그라운드로 돌리면 사용자는 뭐가 일어났는지 모르고,
    /// 실패해도 알 수 없습니다. 스크립트가 물어보는 것도 있고요.
    private static func runInTerminal(_ script: URL) {
        let source = """
        tell application "Terminal"
            activate
            do script "bash \\"\(script.path)\\""
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            apLog("스크립트 실행 실패: \(error)")
            // 자동화 권한이 없을 수 있으므로 폴더라도 열어줍니다.
            NSWorkspace.shared.activateFileViewerSelecting([script])
        } else {
            apLog("터미널에서 실행: \(script.lastPathComponent)")
        }
    }
}
