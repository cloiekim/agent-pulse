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
    /// 확장이 보내주는 제품 이름(`Claude Design` 등).
    /// 같은 claude.ai 라도 마크를 다르게 그리기 위해 받습니다.
    var product: String? = nil
    var size: CGFloat = Theme.avatarSize

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                .fill(theme.avatarTile)
                .frame(width: size, height: size)
                .overlay {
                    BrandMark(agent: agent, product: product)
                        .frame(width: size * 15 / 28, height: size * 15 / 28)
                }

            // ⚠️ 배지는 **헷갈릴 때만** 그립니다.
            //
            //    Claude Design 은 브라우저에만 있습니다. 팔레트가 이미 그걸
            //    말하는데 위에 "브라우저" 배지까지 얹으면 아무 정보도 더하지
            //    않으면서 아이콘만 지저분해집니다.
            //
            //    배지가 필요한 건 같은 로고가 두 표면에 다 있는 경우입니다 —
            //    Claude Code(터미널)와 claude.ai(브라우저)처럼요.
            //    항상 그리지 않으니, 배지가 보이면 "구분이 필요한 놈" 이라는
            //    뜻이 되어 오히려 더 잘 읽힙니다.
            if showsSurfaceBadge {
                SurfaceBadge(surface: agent.surface)
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(product ?? agent.displayName), \(agent.surface == .terminal ? "터미널" : "브라우저")")
    }

    /// 표면 배지를 그릴지.
    ///
    /// 터미널 버전이 없는 표면(Design·Cowork)은 배지가 정보를 안 줍니다.
    private var showsSurfaceBadge: Bool {
        switch product {
        case "Claude Design", "Claude Cowork": false
        default: true
        }
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
    var product: String? = nil

    var body: some View {
        if let symbol = productSymbol {
            // 같은 Claude 라도 Design 은 채팅이 아닙니다.
            // 부제목에 "Claude Design" 이라고 쓰여 있긴 하지만, 행이 여러 개일 때
            // 글자를 읽기 전에 눈으로 먼저 갈라져야 해서 마크를 바꿉니다.
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fontWeight(.medium)
                .foregroundStyle(tint)
        } else {
            BrandShape(pathData: pathData)
                .fill(tint)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    /// 브랜드 벡터 대신 SF Symbol 을 쓰는 제품들.
    ///
    /// ⚠️ 이건 **Anthropic 공식 마크가 아닙니다.** 팔레트 모양의 시스템
    /// 심볼입니다. 실제 Claude Design 벡터가 생기면 `BrandPaths` 에
    /// path 를 넣고 여기 분기를 지우면 됩니다.
    private var productSymbol: String? {
        switch product {
        case "Claude Design": "paintpalette.fill"
        default:              nil
        }
    }

    private var pathData: String {
        switch agent {
        case .claudeCode, .claudeWeb: BrandPaths.claude
        case .codex, .chatgptWeb:     BrandPaths.openai
        // 브랜드 벡터가 아직 없어 Claude 마크를 임시로 씁니다.
        // (SessionRow 는 symbolName 을 쓰므로 실제 화면에는 거의 안 나옵니다)
        case .antigravity:            BrandPaths.claude
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
        case .antigravity:
            .hex(0x4285F4)   // Google 파랑
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
