import Foundation
import ServiceManagement

/// 로그인 시 자동 실행.
///
/// ⚠️ 지금까지 설정의 "Launch at login" 체크는 **아무 일도 안 했습니다.**
/// `@AppStorage` 에 값만 저장하고 끝이었어요. 켜도 안 켜지는 스위치는
/// 없는 것만 못합니다 — 사용자는 켰다고 믿고 다음 날 앱이 없는 걸 발견하니까요.
///
/// `SMAppService` 는 **.app 번들에서만** 동작합니다.
/// `swift run` 으로 띄운 실행 파일에서는 등록이 실패하므로,
/// 그 경우엔 조용히 무시하고 UI 에서도 비활성 처리합니다.
enum LaunchAtLogin {

    /// .app 번들이 아니면 이 기능 자체가 불가능합니다.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// macOS 에 실제로 등록돼 있는가. (UserDefaults 가 아니라 시스템에게 물어봅니다.)
    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 켜고 끄기. 성공 여부를 돌려줍니다.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isSupported else {
            apLog(".app 번들이 아니라 로그인 항목 등록을 건너뜁니다. scripts/make-app.sh 를 쓰세요.")
            return false
        }

        do {
            if enabled {
                // 이미 등록돼 있으면 register 가 에러를 던지므로 상태를 먼저 봅니다.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            apLog("로그인 시 실행: \(enabled ? "켜짐" : "꺼짐")")
            return true
        } catch {
            // 사용자가 시스템 설정에서 막아둔 경우도 여기로 옵니다.
            apLog("로그인 항목 변경 실패: \(error.localizedDescription)")
            return false
        }
    }
}
