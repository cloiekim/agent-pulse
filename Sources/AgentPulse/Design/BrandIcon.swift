import SwiftUI
import AppKit

/// 에이전트 로고 + 표면 배지가 합쳐진 28×28 아바타.
///
/// 디자인 4a 의 행 왼쪽 요소입니다:
/// - 28×28 라운드 타일(radius 8)에 브랜드 로고 15×15
/// - 우하단에 13×13 표면 배지 — 터미널이면 `❯`, 브라우저면 `▢`
///
/// 표면 배지가 중요한 이유: 같은 "Claude" 라도 Claude Code(터미널)와
/// claude.ai(브라우저)는 완전히 다른 세션입니다. 로고만으로는 구분이 안 됩니다.
struct AgentAvatar: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let agent: AgentKind
    var size: CGFloat = Theme.avatarSize

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                .fill(theme.avatarTile)
                .frame(width: size, height: size)
                .overlay {
                    BrandMark(agent: agent)
                        .frame(width: size * 15 / 28, height: size * 15 / 28)
                }

            SurfaceBadge(surface: agent.surface)
                .offset(x: 4, y: 4)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(agent.displayName), \(agent.surface == .terminal ? "터미널" : "브라우저")")
    }
}

/// 브랜드 로고 하나.
///
/// SVG path 를 코드에서 직접 그립니다 — 이유는 `BrandPaths.swift` 주석 참고.
/// (요약: SwiftPM 이 `.xcassets` 를 컴파일하지 않아 `NSImage(named:)` 가 항상 nil)
struct BrandMark: View {
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: ColorScheme {
        AppSettings.shared.appearance.resolved(system: systemScheme)
    }
    let agent: AgentKind

    var body: some View {
        BrandShape(pathData: pathData)
            .fill(tint)
            .aspectRatio(1, contentMode: .fit)
    }

    private var pathData: String {
        switch agent {
        case .claudeCode, .claudeWeb: BrandPaths.claude
        case .codex, .chatgptWeb:     BrandPaths.openai
        }
    }

    /// Claude 오렌지는 라이트/다크 공용입니다 (브랜드 규정).
    /// OpenAI 마크는 단색이라 배경에 맞춰 뒤집습니다.
    private var tint: Color {
        switch agent {
        case .claudeCode, .claudeWeb:
            .hex(0xD97757)
        case .codex, .chatgptWeb:
            scheme == .dark ? .hex(0xECECEF) : .hex(0x1C1E22)
        }
    }
}

/// 아바타 우하단의 작은 사각 배지. 터미널 `❯` / 브라우저 `▢`.
struct SurfaceBadge: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    let surface: AgentKind.Surface

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(theme.surfaceBadgeBg)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(theme.surfaceBadgeBorder, lineWidth: 1)
            }
            .overlay {
                Text(surface == .terminal ? "❯" : "▢")
                    .font(Theme.mono(8))
                    .foregroundStyle(theme.surfaceBadgeFg)
            }
            .frame(width: Theme.badgeSize, height: Theme.badgeSize)
    }
}
