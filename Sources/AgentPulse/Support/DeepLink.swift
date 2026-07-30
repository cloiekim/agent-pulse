import AppKit

/// "정확히 그 자리로 돌아가기".
///
/// 마켓 분석의 결론 중 하나 — 사람들이 실제로 돈을 내는 건 **알림이 아니라 이동**입니다.
/// (CCTV 의 단축키, cmux 의 jump-to-unread, back2vibing 의 exact-surface return이
///  전부 이걸 팝니다. 알림만 하는 도구는 전부 무료이고 별이 안 붙습니다.)
///
/// 그래서 이 파일은 작지만 제품에서 가장 중요한 부분 중 하나입니다.
enum DeepLink {

    /// 알림 클릭에서 쓰는 진입점. 세션 객체 없이 origin 만으로 판단합니다.
    @MainActor
    static func open(origin: SessionOrigin, target: String?) {
        switch origin {
        case .claudeDesktop:
            activate(bundleIDs: ["com.anthropic.claudefordesktop", "com.anthropic.claude"])
        case .browser:
            if let target { open(rawTarget: target) }
        case .terminal:
            if let target { open(rawTarget: target) } else { focusTerminal(cwd: nil) }
        }
    }

    @MainActor
    static func open(_ session: AgentSession) {
        // ⚠️ 같은 Claude Code 세션이라도 시작한 곳이 다르면 돌아갈 곳도 다릅니다.
        //    구분하지 않으면 데스크톱 앱에서 띄운 세션인데 터미널이 뜹니다.
        switch session.origin {
        case .claudeDesktop:
            activate(bundleIDs: ["com.anthropic.claudefordesktop", "com.anthropic.claude"])
            return
        case .browser:
            if let target = session.returnTarget { open(rawTarget: target) }
            return
        case .terminal:
            guard let target = session.returnTarget else { return }
            open(rawTarget: target)
        }
    }

    @MainActor
    static func open(rawTarget: String) {
        // 브라우저 대화 — 그냥 URL 을 엽니다.
        // 이미 그 탭이 열려 있으면 macOS 가 기존 탭으로 전환해 줍니다.
        if rawTarget.hasPrefix("http") {
            if let url = URL(string: rawTarget) {
                apLog("이동: 브라우저 탭")
                NSWorkspace.shared.open(url)
            }
            return
        }

        // 터미널 세션 — 우리 커스텀 스킴.
        guard let url = URL(string: rawTarget),
              url.scheme == "agentpulse",
              url.host == "terminal" else { return }

        let cwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "cwd" })?.value

        focusTerminal(cwd: cwd)
    }

    /// 터미널 앱을 앞으로 가져옵니다.
    ///
    /// ⚠️ MVP 의 한계: "그 앱"까지는 가지만 "그 탭/pane"까지는 못 갑니다.
    /// 정확한 pane 복귀는 터미널마다 방법이 다릅니다:
    ///   - iTerm2: AppleScript 로 session id 지정 가능 (자동화 권한 필요)
    ///   - Terminal.app: AppleScript 로 tab 지정 가능
    ///   - tmux:  `tmux switch-client -t <pane>` (권한 불필요, 가장 깔끔)
    ///   - Ghostty / WezTerm / VS Code: 각각 별도 처리 필요
    ///
    /// V1 작업 항목: 훅에서 `$TERM_PROGRAM`, `$TMUX_PANE`, `tty` 를 같이 받아와
    /// 이 함수에서 분기하세요. 이게 경쟁 제품들이 못 하는 부분입니다.
    private static func focusTerminal(cwd: String?) {
        let found = activate(bundleIDs: [
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
        ])
        if !found {
            apLog("실행 중인 터미널을 찾지 못했습니다 (cwd: \(cwd ?? "-"))")
        }
    }

    /// 후보 중 실행 중인 첫 앱을 앞으로 가져옵니다.
    ///
    /// ⚠️ `activate(options:)` 를 쓰면 안 됩니다.
    /// macOS 14 에서 협조적 활성화(cooperative activation)로 바뀌면서
    /// `.activateAllWindows` 만으로는 앱이 앞으로 나오지 않습니다.
    /// **에러도 안 나고 그냥 아무 일도 안 일어납니다.**
    ///
    /// `NSWorkspace.openApplication` 은 이미 실행 중인 앱이면 앞으로 가져오고,
    /// 아니면 실행합니다. 두 경우 모두 우리가 원하는 동작입니다.
    @discardableResult
    private static func activate(bundleIDs: [String]) -> Bool {
        for bundleID in bundleIDs {
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first,
                  let url = app.bundleURL else { continue }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    apLog("\(bundleID) 활성화 실패: \(error.localizedDescription)")
                }
            }
            apLog("이동: \(bundleID)")
            return true
        }
        apLog("이동할 앱을 찾지 못했습니다: \(bundleIDs.joined(separator: ", "))")
        return false
    }
}
