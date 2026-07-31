import SwiftUI
import AppKit  // CTFontManagerCopyAvailableFontFamilyNames

/// Astryx Neutral 디자인 토큰.
///
/// 디자인 파일(`Menubar MVP — Turn 4a`)의 하드코딩된 hex 를 전부 여기로 모았습니다.
/// 색을 바꿀 일이 생기면 이 파일 한 곳만 고치면 됩니다.
///
/// 라이트/다크는 `@Environment(\.colorScheme)` 로 갈라집니다.
struct Theme {
    let scheme: ColorScheme
    var isDark: Bool { scheme == .dark }

    // MARK: 표면

    /// 팝오버 배경. radius-container 16.
    var popover: Color        { isDark ? .hex(0x1B1B1B) : .hex(0xFFFFFF) }
    var popoverBorder: Color  { isDark ? .white.opacity(0.10) : .hex(0xEBEBEB) }
    var divider: Color        { isDark ? .white.opacity(0.08) : .hex(0xEBEBEB) }
    /// 하단 usage 블록 배경.
    var footer: Color         { isDark ? .white.opacity(0.02) : .hex(0xFAFAFA) }
    /// 로고 아바타 타일. radius-inner 8.
    var avatarTile: Color     { isDark ? .hex(0x262626) : .hex(0xF1F1F1) }
    /// 행 hover 배경.
    var rowHover: Color       { isDark ? .white.opacity(0.04) : .black.opacity(0.03) }

    // MARK: 잉크

    var textPrimary: Color    { isDark ? .hex(0xFAFAFA) : .hex(0x171717) }
    var textSecondary: Color  { isDark ? .hex(0xA3A3A3) : .hex(0x737373) }

    // MARK: 상태 토큰 (blue / yellow / green / red — muted 배경 + 진한 텍스트)

    var runningBg: Color      { isDark ? Color.hex(0x3FA35F).opacity(0.24) : .hex(0xCFEEDA) }
    var runningFg: Color      { isDark ? .hex(0x8FD6A6) : .hex(0x1C6537) }
    // ⚠️ 상태 색은 **의도적으로 서열이 있습니다.**
    //    running(초록)은 attention(앰버)보다 채도를 두 단계 낮게 잡아,
    //    돌고 있는 게 승인 대기보다 시끄러워지지 않게 합니다.
    //    파랑(#2F6FED)은 이제 **동작에만** 씁니다 — 상태를 나타내지 않습니다.
    var runningDot: Color     { .hex(0x3FA35F) }

    var attentionBg: Color    { isDark ? Color.hex(0xFDCF4F).opacity(0.22) : .hex(0xFBE6B2) }
    var attentionFg: Color    { isDark ? .hex(0xFDCF4F) : .hex(0x6B5200) }
    /// 승인 대기 행 전체에 깔리는 옅은 노란 배경.
    var attentionRowBg: Color { isDark ? Color.hex(0xDEB433).opacity(0.10) : Color.hex(0xF8DA9D).opacity(0.25) }
    /// 승인 대기 행의 두 번째 줄 텍스트.
    var attentionText: Color  { isDark ? .hex(0xFDCF4F) : .hex(0x745B00) }

    var errorBg: Color        { isDark ? Color.hex(0xD94F4A).opacity(0.24) : .hex(0xFBD9D7) }
    var errorText: Color      { isDark ? .hex(0xFF9A95) : .hex(0x8F2B27) }

    /// 대기 — 색 예산 없음. 중립으로만 표시합니다.
    var waitingBg: Color      { isDark ? Color.white.opacity(0.10) : .hex(0xEEEEEE) }
    var waitingFg: Color      { isDark ? .hex(0xE5E5E5) : .hex(0x404040) }

    // Done 은 색 예산을 안 씁니다. 초록을 한 번 더 채우면 위계가 뭉개집니다.
    // 중립 배경 + 초록 점만 씁니다.
    var doneBg: Color         { isDark ? Color.white.opacity(0.08) : .hex(0xF2F2F2) }
    var doneFg: Color         { isDark ? .hex(0xA3A3A3) : .hex(0x737373) }

    var neutralPillBg: Color  { isDark ? .white.opacity(0.10) : .hex(0xE5E5E5) }
    var neutralPillFg: Color  { isDark ? .hex(0xE5E5E5) : .hex(0x262626) }

    // MARK: 액션 (monochrome accent)

    /// 주 버튼 — Approve. 다크에선 밝게, 라이트에선 어둡게(반전).
    // ⚠️ 파랑은 **동작에만** 씁니다 (버튼, 선택된 메뉴 행).
    //    예전엔 상태와 동작을 같은 파랑으로 칠해서 눈이 어디로 가야 할지
    //    알 수 없었습니다. 이제 상태는 초록·앰버·빨강, 동작은 파랑입니다.
    var accentBg: Color       { .hex(0x2F6FED) }
    var accentFg: Color       { .white }
    /// 보조 버튼 — Retry.
    var subtleBg: Color       { isDark ? .white.opacity(0.10) : .black.opacity(0.06) }
    var subtleFg: Color       { isDark ? .hex(0xFAFAFA) : .hex(0x171717) }

    // MARK: 표면 배지 (아바타 우하단의 ❯ / ▢)

    var surfaceBadgeBg: Color     { isDark ? .hex(0x333338) : .hex(0xFFFFFF) }
    var surfaceBadgeBorder: Color { isDark ? .hex(0x525252) : .hex(0xD4D4D4) }
    var surfaceBadgeFg: Color     { isDark ? .hex(0xA3A3A3) : .hex(0x525252) }

    // MARK: 프로그레스 바 (neutral 트랙 + accent 채움)

    var trackBg: Color        { isDark ? .white.opacity(0.10) : .black.opacity(0.06) }
    var trackFill: Color      { isDark ? .hex(0xEBEBEB) : .hex(0x262626) }

    // MARK: 지오메트리

    /// 디자인 스펙 344px. 예전엔 좌우 마진을 뺀 328 을 썼는데,
    /// 스펙의 344 는 팝오버 자체의 폭입니다.
    static let popoverWidth: CGFloat  = 344
    // ⚠️ Astryx 기본값은 큰 화면용입니다. 344px 팝오버 안에서는 과합니다.
    //    스펙: container 16 → 12, row 12 → 8, 행 높이 40 → 32, 본문 14 → 13.
    static let containerRadius: CGFloat = 12
    static let innerRadius: CGFloat = 8       // 행 반경
    static let rowHeight: CGFloat = 32        // Astryx 40 → 32
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 10
    static let avatarSize: CGFloat = 28
    static let badgeSize: CGFloat = 13

    // MARK: 타이포 (Figtree 14 / 12)
    //
    // ⚠️ `Font.custom("Figtree", size:).weight(...)` 를 폰트가 없는 상태에서 쓰면
    // SwiftUI 가 폴백 디스크립터에 weight 를 못 실어서 매 프레임 경고를 뱉습니다:
    //   "Unable to update Font Descriptor's weight ... please file a bug report"
    //
    // 그래서 설치 여부를 한 번만 확인하고, 없으면 시스템 폰트로 깔끔히 떨어집니다.
    //
    // Figtree 설치:  brew install --cask font-figtree
    // 배포 시:       .ttf 를 Resources/Fonts/ 에 넣으면
    //                make-app.sh 의 ATSApplicationFontsPath 가 자동 등록합니다.

    /// 폰트 목록 조회는 비싸므로 프로세스당 한 번만 합니다.
    private static func isInstalled(_ family: String) -> Bool {
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return families.contains(family)
    }

    /// 번들 등록 후에도 못 찾으면 시스템 폰트로 갑니다.
    static let hasFigtree: Bool = isInstalled("Figtree-Regular")
    static let hasJetBrainsMono: Bool = isInstalled("JetBrains Mono")

    /// ⚠️ 폰트는 **앱 번들에 들어 있습니다** (FontLoader 참고).
    ///    예전엔 시스템에 설치돼 있을 때만 쓰고 아니면 조용히 시스템 폰트로
    ///    떨어졌는데, 아무도 설치하지 않아서 디자인이 한 번도 제대로 나온 적이
    ///    없었습니다.
    ///
    ///    무게별로 파일이 따로 있으므로 이름을 직접 지정합니다.
    ///    `.weight()` 로 굵기를 흉내내면 가짜 볼드가 되어 모양이 뭉갭니다.
    private static func figtree(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let face = switch weight {
        case .semibold, .bold, .heavy, .black: "Figtree-SemiBold"
        case .medium:                          "Figtree-Medium"
        default:                               "Figtree-Regular"
        }
        return hasFigtree ? .custom(face, size: size) : .system(size: size, weight: weight)
    }

    /// 본문. 스펙에서 14 → 13 으로 내렸습니다 (344px 안에서 14 는 큽니다).
    static func body(_ weight: Font.Weight = .medium) -> Font { figtree(13, weight) }
    static func supporting(_ weight: Font.Weight = .regular) -> Font { figtree(12, weight) }
    static func title() -> Font { figtree(14, .semibold) }

    /// 표면 배지의 ❯ / ▢ 글리프.
    static func mono(_ size: CGFloat) -> Font {
        hasJetBrainsMono
            ? .custom("JetBrains Mono", size: size)
            : .system(size: size, design: .monospaced)
    }
}

// MARK: - 편의

extension Color {
    /// 0xRRGGBB 정수로 색 만들기. 디자인 문서의 hex 를 그대로 옮겨 적기 위한 것.
    static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(scheme: .dark)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// 현재 colorScheme 에 맞는 Theme 를 하위 뷰에 주입합니다.
    func injectTheme(_ scheme: ColorScheme) -> some View {
        environment(\.theme, Theme(scheme: scheme))
    }
}
