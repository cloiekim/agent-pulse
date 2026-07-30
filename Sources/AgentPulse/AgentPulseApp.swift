import SwiftUI
import AppKit
import UserNotifications

/// 앱 전역에서 하나만 존재하는 스토어.
///
/// SwiftUI 의 `MenuBarExtra` 와 `NSApplicationDelegate` 가 같은 인스턴스를
/// 봐야 하므로 여기서 한 번만 만듭니다.
@MainActor
enum AppEnvironment {
    static let isDemo = CommandLine.arguments.contains("--demo")
    static let store: SessionStore = isDemo ? .demo() : SessionStore()
    static let usage = UsageStore()
}

@main
struct AgentPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @AppStorage("isOnboarded") private var isOnboarded = false

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(store: AppEnvironment.store,
                      usage: AppEnvironment.usage,
                      isOnboarded: $isOnboarded)
        } label: {
            MenuBarLabel(store: AppEnvironment.store)
        }
        // 커스텀 SwiftUI 팝오버를 쓰기 위해 필수. (기본값 .menu 는 시스템 메뉴 모양)
        .menuBarExtraStyle(.window)
    }
}

/// 메뉴바 앱 설정 + 백그라운드 서비스 기동.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var server: LocalEventServer?
    private var tracker: PendingToolTracker?
    private var pruneTimer: Timer?
    private let notificationDelegate = NotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 없이 메뉴바에만 나타납니다.
        // (Xcode 프로젝트라면 Info.plist 의 LSUIElement = YES 와 같은 효과.
        //  SPM 실행 파일에는 Info.plist 가 없으므로 코드로 설정합니다.)
        NSApp.setActivationPolicy(.accessory)

        // .app 번들이 아니면 UNUserNotificationCenter 를 건드리는 순간 abort 합니다.
        if Notifier.isBundled {
            UNUserNotificationCenter.current().delegate = notificationDelegate
            let notifier = Notifier()
            notifier.requestAuthorization()
            // 메뉴바 아이템이 잘렸는지 확인하고, 필요하면 알려줍니다.
            MainActor.assumeIsolated {
                MenuBarVisibility.checkAfterLaunch(notifier: notifier)
            }
        }

        // 설정 값과 실제 시스템 등록 상태를 맞춥니다.
        // (사용자가 시스템 설정에서 직접 끄면 우리 체크만 남아 거짓말이 됩니다.)
        if LaunchAtLogin.isSupported {
            UserDefaults.standard.set(LaunchAtLogin.isEnabled, forKey: "launchAtLogin")
        }

        startIngest()
        startPruneTimer()

        // 사용량은 로컬 로그를 1분마다 직접 읽습니다.
        MainActor.assumeIsolated { AppEnvironment.usage.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        pruneTimer?.invalidate()
        Task { await tracker?.cancelAll() }
        // 마지막 상태를 디스크에 남깁니다.
        MainActor.assumeIsolated { AppEnvironment.store.flush() }
    }

    /// 로컬 이벤트 서버를 띄우고, 들어온 이벤트를 스토어로 흘려보냅니다.
    ///
    /// 흐름:  훅/확장 → LocalEventServer → EventMapper → PendingToolTracker → SessionStore → View
    private func startIngest() {
        // 트래커가 자체 발행하는 이벤트(승인 대기 승격)는 스토어로 직행합니다.
        let tracker = PendingToolTracker { event in
            Task { @MainActor in AppEnvironment.store.ingest(event) }
        }
        self.tracker = tracker

        let server = LocalEventServer(onEvent: { event in
            Task { @MainActor in
                AppEnvironment.store.ingest(event)
            }
            // 훅 이름은 raw 에 담아 전달됩니다 (EventMapper 참고).
            if let hookName = event.raw?["hook_event_name"] {
                Task { await tracker.observe(event, hookName: hookName) }
            }
        }, onUsage: { quota in
            Task { @MainActor in AppEnvironment.usage.ingest(quota) }
        })
        self.server = server

        do {
            try server.start()
        } catch {
            apLog("""
            서버 시작 실패: \(error)
            포트 \(LocalEventServer.defaultPort) 가 이미 사용 중인지 확인하세요:
              lsof -nP -iTCP:\(LocalEventServer.defaultPort) -sTCP:LISTEN
            """)
        }
    }

    /// 완료된 세션을 주기적으로 걷어내고, 방치된 승인 대기는 재알림합니다.
    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                AppEnvironment.store.prune()
            }
        }
    }
}
