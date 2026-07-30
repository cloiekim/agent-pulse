import Foundation
import UserNotifications

/// 시스템 알림.
///
/// 설계 원칙 — 사용자가 앱을 끄지 않게 만드는 것이 알림 기능의 1순위 목표입니다:
///
/// 1. **상태가 바뀔 때만** 보냅니다. 같은 상태의 반복 이벤트는 무시(Store 에서 처리).
/// 2. running/queued 는 절대 알리지 않습니다.
/// 3. 같은 세션은 `threadIdentifier` 로 묶여 알림 센터에서 쌓이지 않고 갱신됩니다.
/// 4. 승인 대기는 `.timeSensitive` — 집중 모드를 뚫어야 의미가 있습니다.
///    (완료 알림은 뚫지 않습니다. 이게 켜져 있으면 사람들이 앱을 꺼버립니다.)
/// 5. 클릭하면 해당 터미널/탭으로 이동합니다 — 알림 자체보다 이게 본체입니다.
final class Notifier {

    /// ⚠️ 중요:
    /// `UNUserNotificationCenter.current()` 는 bundle identifier 가 없는
    /// 프로세스에서 **크래시**합니다 (abort). `swift run` 으로 띄운 실행 파일은
    /// .app 번들이 아니라서 bundle identifier 가 없습니다.
    ///
    /// 그래서 번들 여부를 먼저 확인하고, 아니면 알림 기능을 통째로 끕니다.
    /// UI 확인용 `--demo` 실행이 크래시 없이 돌아가야 하니까요.
    ///
    /// 실제 알림을 테스트하려면 `./scripts/make-app.sh` 로 .app 을 만들어 실행하세요.
    static let isBundled: Bool = Bundle.main.bundleIdentifier != nil

    private let enabled: Bool

    /// 지연 생성 — 번들이 아닐 때는 아예 만들지 않습니다.
    private var center: UNUserNotificationCenter? {
        Self.isBundled ? UNUserNotificationCenter.current() : nil
    }

    init(enabled: Bool = true) {
        self.enabled = enabled && Self.isBundled
        if !Self.isBundled {
            apLog(".app 번들이 아니므로 알림을 비활성화합니다. 실제 알림 테스트는 scripts/make-app.sh 를 쓰세요.")
        }
    }

    /// 알림 안에서 바로 고칠 수 있게 하는 버튼.
    /// 안내만 하고 "설정 어딘가에서 바꾸세요" 라고 하면 아무도 안 바꿉니다.
    static let compactActionID = "agentpulse.compact-menubar"
    static let menuBarCategoryID = "agentpulse.menubar-notice"

    private func registerCategories() {
        guard let center else { return }
        let compact = UNNotificationAction(
            identifier: Self.compactActionID,
            title: Loc(language: AppLanguage.current)("Show icon only", "아이콘만 표시"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.menuBarCategoryID,
            actions: [compact],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// 첫 실행 안내 — 또는 아이템이 잘린 것으로 보일 때.
    func notifyMenuBarNotice(seemsHidden: Bool) {
        guard enabled, let center else { return }
        let loc = Loc(language: AppLanguage.current)

        let content = UNMutableNotificationContent()
        content.title = loc("Agent Pulse is running", "Agent Pulse 실행 중")
        content.body = seemsHidden
            ? loc("The menu bar icon looks hidden — your menu bar may be full. You can make it narrower.",
                  "메뉴바 아이콘이 잘린 것 같습니다. 메뉴바가 꽉 찼을 수 있어요. 표시를 좁게 바꿀 수 있습니다.")
            : loc("Look for the ⌁ icon in your menu bar. Don't see it? Your menu bar may be full — you can make it narrower.",
                  "메뉴바에서 ⌁ 아이콘을 찾아보세요. 안 보이면 메뉴바가 꽉 찬 것입니다 — 표시를 좁게 바꿀 수 있습니다.")
        content.categoryIdentifier = Self.menuBarCategoryID
        content.interruptionLevel = .active

        center.add(UNNotificationRequest(identifier: "menubar-notice",
                                         content: content,
                                         trigger: nil))
    }

    func requestAuthorization() {
        guard enabled, let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { apLog("알림 권한 실패: \(error)") }
            apLog("알림 권한: \(granted)")
            if granted { DispatchQueue.main.async { self?.registerCategories() } }
        }
    }

    func notify(for session: AgentSession) {
        guard enabled, let center,
              UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        else { return }

        // 사용자가 이 종류를 끄지 않았는지 확인합니다.
        let kinds = (UserDefaults.standard.object(forKey: "notificationKinds") as? Int)
            .map(NotificationKinds.init(rawValue:)) ?? .default
        guard kinds.allows(session.state) else { return }

        let content = UNMutableNotificationContent()
        let loc = Loc(language: AppLanguage.current)

        switch session.state {
        case .needsApproval:
            content.title = loc("Needs approval — \(session.title)", "승인 필요 — \(session.title)")
            content.body = session.detail
                ?? loc("\(session.agent.displayName) is waiting for permission to run a tool",
                       "\(session.agent.displayName)가 도구 실행 권한을 기다립니다")
            content.interruptionLevel = .timeSensitive
            content.sound = .default

        case .waitingInput:
            content.title = loc("Needs input — \(session.title)", "입력 대기 — \(session.title)")
            content.body = loc("\(session.agent.displayName) is waiting for your answer",
                               "\(session.agent.displayName)가 답을 기다립니다")
            content.interruptionLevel = .timeSensitive
            content.sound = .default

        case .failed:
            content.title = loc("Failed — \(session.title)", "실패 — \(session.title)")
            content.body = session.detail
                ?? loc("\(session.agent.displayName) session ended with an error",
                       "\(session.agent.displayName) 세션이 오류로 종료됐습니다")
            content.interruptionLevel = .active

        case .completed:
            content.title = loc("Done — \(session.title)", "완료 — \(session.title)")
            content.body = session.detail
                ?? "\(session.agent.displayName) · \(session.runtime.shortDuration(loc))"
            content.interruptionLevel = .passive   // 방해하지 않음

        default:
            return
        }

        // 같은 세션의 알림은 쌓이지 않고 대체됩니다.
        content.threadIdentifier = session.id
        // ⚠️ origin 을 같이 실어야 합니다.
        //    안 그러면 데스크톱 앱에서 시작한 세션인데 터미널을 띄웁니다.
        content.userInfo = [
            "returnTarget": session.returnTarget ?? "",
            "origin": session.origin.rawValue,
        ]

        let request = UNNotificationRequest(
            identifier: session.id,        // 같은 id → 기존 알림 교체
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// 승인 대기가 계속 방치되고 있을 때의 재알림.
    /// 리서치에서 반복적으로 나온 불만 — "데스크톱 알림은 내가 보기 전에 사라진다".
    func renudge(_ session: AgentSession) {
        guard session.isStale else { return }
        notify(for: session)
    }
}

/// 알림을 눌렀을 때 해당 세션으로 이동시키는 델리게이트.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        apLog("알림 클릭: action=\(response.actionIdentifier) origin=\(info["origin"] ?? "-")")

        // 메뉴바가 잘렸을 때 뜬 알림의 "아이콘만 표시" 버튼.
        if response.actionIdentifier == Notifier.compactActionID {
            await MainActor.run { MenuBarVisibility.compact() }
            return
        }

        let target = info["returnTarget"] as? String ?? ""
        let origin = SessionOrigin(rawValue: info["origin"] as? String ?? "") ?? .terminal

        await MainActor.run {
            DeepLink.open(origin: origin, target: target.isEmpty ? nil : target)
        }
    }

    /// 앱이 떠 있어도 알림을 보여줍니다 (메뉴바 앱은 항상 "떠 있음" 상태이므로).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
