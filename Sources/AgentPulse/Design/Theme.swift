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

    var runningBg: Color      { isDark ? Color.hex(0x9EB7FF).opacity(0.24) : .hex(0xC4DDFB) }
    var runningFg: Color      { isDark ? .hex(0xC7D3FF) : .hex(0x00458C) }
    var runningDot: Color     { isDark ? .hex(0x9EB7FF) : .hex(0x00458C) }

    var attentionBg: Color    { isDark ? Color.hex(0xDEB433).opacity(0.24) : .hex(0xF8DA9D) }
    var attentionFg: Color    { isDark ? .hex(0xFDCF4F) : .hex(0x584400) }
    /// 승인 대기 행 전체에 깔리는 옅은 노란 배경.
    var attentionRowBg: Color { isDark ? Color.hex(0xDEB433).opacity(0.10) : Color.hex(0xF8DA9D).opacity(0.25) }
    /// 승인 대기 행의 두 번째 줄 텍스트.
    var attentionText: Color  { isDark ? .hex(0xFDCF4F) : .hex(0x745B00) }

    var errorText: Color      { isDark ? .hex(0xFFC6C1) : .hex(0x89001A) }

    var doneBg: Color         { isDark ? Color.hex(0x7ED492).opacity(0.24) : .hex(0xC6E9CF) }
    var doneFg: Color         { isDark ? .hex(0xA7E5B8) : .hex(0x0B5323) }

    var neutralPillBg: Color  { isDark ? .white.opacity(0.10) : .hex(0xE5E5E5) }
    var neutralPillFg: Color  { isDark ? .hex(0xE5E5E5) : .hex(0x262626) }

    // MARK: 액션 (monochrome accent)

    /// 주 버튼 — Approve. 다크에선 밝게, 라이트에선 어둡게(반전).
    var accentBg: Color       { isDark ? .hex(0xEBEBEB) : .hex(0x262626) }
    var accentFg: Color       { isDark ? .hex(0x171717) : .hex(0xFFFFFF) }
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

    static let popoverWidth: CGFloat  = 328   // 디자인 344 - 좌우 마진 8
    static let containerRadius: CGFloat = 16  // radius-container
    static let innerRadius: CGFloat = 8       // radius-inner
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

    static let hasFigtree: Bool = isInstalled("Figtree")
    static let hasJetBrainsMono: Bool = isInstalled("JetBrains Mono")

    private static func figtree(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        hasFigtree
            ? .custom("Figtree", size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    static func body(_ weight: Font.Weight = .medium) -> Font { figtree(14, weight) }
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
