import SwiftUI
import Observation

/// 앱 설정의 단일 진실 공급원.
///
/// ⚠️ 왜 `@AppStorage` 를 안 쓰는가:
/// `MenuBarExtra` 의 label 은 일반 View 계층 밖에 있어서 `@AppStorage` 변경이
/// **안정적으로 전달되지 않습니다.** 설정을 바꿔도 메뉴바가 그대로 있다가,
/// 다른 이유로 갱신될 때에야 뒤늦게 반영됩니다.
///
/// `@Observable` 객체 하나를 모두가 같이 보게 하면 그 문제가 사라집니다.
/// 저장은 여전히 UserDefaults 에 하므로 기존 값이 그대로 이어집니다.
@Observable
@MainActor
final class AppSettings {

    static let shared = AppSettings()

    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    /// 어떤 종류의 알림을 받을지.
    var notificationKinds: NotificationKinds {
        didSet { defaults.set(notificationKinds.rawValue, forKey: Keys.notificationKinds) }
    }

    /// 다른 기기에서 도는 에이전트도 받을지.
    /// 켜면 앱을 다시 시작해야 반영됩니다 (포트를 다시 열어야 하므로).
    var allowRemoteAgents: Bool {
        didSet { defaults.set(allowRemoteAgents, forKey: Keys.allowRemote) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// 라이선스는 별도 모듈이 관리하지만, 화면 갱신을 위해 여기에 미러링합니다.
    var license: License.Info?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let menuBarStyle = "menuBarStyle"
        static let appearance = "appearance"
        static let language = "language"
        static let notifications = "notificationsEnabled"
        static let notificationKinds = "notificationKinds"
        static let allowRemote = "allowRemoteAgents"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Keys.menuBarStyle) ?? "") ?? .text
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        notificationKinds = (defaults.object(forKey: Keys.notificationKinds) as? Int)
            .map(NotificationKinds.init(rawValue:)) ?? .default
        allowRemoteAgents = defaults.object(forKey: Keys.allowRemote) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        license = License.current
    }

    /// 뷰에서 자주 쓰는 번역기.
    var loc: Loc { Loc(language: language) }

    /// 시스템 모드를 받아 실제 적용할 테마를 돌려줍니다.
    ///
    /// ⚠️ 뷰마다 `@Environment(\.theme)` 로 받으면 안 됩니다 —
    /// 팝오버는 뜰 때의 environment 를 붙들고 있어서, 모드를 바꿔도
    /// 이미 열려 있는 화면에는 반영되지 않습니다. (언어에서 겪은 그 문제)
    func theme(for system: ColorScheme) -> Theme {
        Theme(scheme: appearance.resolved(system: system))
    }
}
