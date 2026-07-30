import SwiftUI

/// 화면 모드. 시스템을 따라가거나, 강제로 고정합니다.
///
/// 왜 고정 옵션이 필요한가:
/// 메뉴바 앱은 아주 작은 표면이라, 시스템 전체를 라이트로 쓰면서도
/// 이것만 다크로 두고 싶은 경우가 흔합니다. 반대도 마찬가지고요.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    func displayName(_ loc: Loc) -> String {
        switch self {
        case .system: loc("Match system", "시스템 설정")
        case .light:  loc("Light", "밝게")
        case .dark:   loc("Dark", "어둡게")
        }
    }

    /// 실제로 적용할 모드. `.system` 이면 macOS 설정을 그대로 씁니다.
    func resolved(system: ColorScheme) -> ColorScheme {
        switch self {
        case .system: system
        case .light:  .light
        case .dark:   .dark
        }
    }
}
