import SwiftUI

/// Agent Pulse 가 감시하는 표면(surface).
///
/// MVP 범위: 터미널 2종 + 브라우저 2종.
/// V2 에서 Cursor / Copilot / Antigravity 등을 여기에 추가하면
/// 나머지 코드는 건드릴 필요가 없도록 설계돼 있습니다.
enum AgentKind: String, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case claudeWeb
    case chatgptWeb
    /// Google Antigravity CLI. (Gemini CLI 는 여기로 통합됐습니다)
    case antigravity

    var id: String { rawValue }

    /// 메뉴에 표시할 이름.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .claudeWeb:  "Claude"
        case .chatgptWeb: "ChatGPT"
        case .antigravity: "Antigravity"
        }
    }

    /// 터미널인지 브라우저인지. 딥링크 방식이 갈립니다.
    var surface: Surface {
        switch self {
        case .claudeCode, .codex, .antigravity: .terminal
        case .claudeWeb, .chatgptWeb: .browser
        }
    }

    enum Surface: String, Codable {
        case terminal
        case browser
    }

    /// 디자인 에셋(claude.svg, gpt-dark.svg …)이 들어오면
    /// 이 프로퍼티만 Image(...) 로 교체하면 됩니다.
    var symbolName: String {
        switch self {
        case .claudeCode: "terminal"
        case .codex:      "chevron.left.forwardslash.chevron.right"
        case .claudeWeb:  "bubble.left"
        case .chatgptWeb: "bubble.left.and.bubble.right"
        // 브랜드 에셋이 없어 임시로 SF Symbol 을 씁니다.
        case .antigravity: "sparkle"
        }
    }
}
