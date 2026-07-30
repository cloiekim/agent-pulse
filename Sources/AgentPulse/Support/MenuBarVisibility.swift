import AppKit

/// 메뉴바 아이템이 실제로 보이는지 확인하고, 안 보이면 알려줍니다.
///
/// ⚠️ 왜 필요한가 — 실제로 겪은 일입니다:
/// macOS 는 메뉴바가 꽉 차면 새 상태 아이템을 **조용히 잘라냅니다.**
/// 에러도, 로그도, 아무 신호도 없습니다.
///
/// 사용자 입장에서는 최악의 첫인상입니다:
/// 설치했는데 아무것도 안 보이고 → 앱이 켜졌는지도 모르고 → 원인도 알 수 없고
/// → 삭제합니다. 우리 잘못이 아닌데 우리가 손해를 봅니다.
///
/// 특히 기본값이 텍스트 모드(`Working`, `Needs approval`)라 폭을 많이 먹어서
/// 아이콘만 있을 때보다 잘릴 확률이 높습니다.
enum MenuBarVisibility {

    /// 메뉴바 아이템이 화면 안에 그려졌는가.
    ///
    /// SwiftUI `MenuBarExtra` 는 NSStatusItem 을 감춰두고 안 내주므로
    /// 창 목록에서 상태바 창을 찾아 위치를 봅니다.
    /// 확실히 판단할 수 없으면 `true`(보인다)로 답합니다 —
    /// 잘못된 경고로 사람을 귀찮게 하는 것보다 낫습니다.
    static func isLikelyVisible() -> Bool {
        guard let screen = NSScreen.main else { return true }

        let statusWindows = NSApp.windows.filter {
            $0.className.contains("StatusBar") || $0.className.contains("MenuBarExtra")
        }

        // 상태바 창을 아예 못 찾았으면 판단 불가 → 보인다고 간주.
        guard !statusWindows.isEmpty else { return true }

        return statusWindows.contains { window in
            let f = window.frame
            guard f.width > 1, f.height > 1 else { return false }
            // 화면 밖으로 밀려났으면 잘린 것입니다.
            return f.minX >= screen.frame.minX && f.maxX <= screen.frame.maxX
        }
    }

    /// 실행 후 한 번 확인합니다.
    ///
    /// 첫 실행에는 보이든 안 보이든 안내를 보냅니다 —
    /// "설치했는데 아무 일도 안 일어나는" 순간을 없애는 게 목적이라
    /// 감지 정확도에 기대지 않습니다.
    @MainActor
    static func checkAfterLaunch(notifier: Notifier) {
        // 메뉴바가 자리를 잡을 시간을 줍니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let firstRun = !UserDefaults.standard.bool(forKey: "hasSeenMenuBarNotice")
            let visible = isLikelyVisible()

            apLog("메뉴바 아이템 감지: \(visible ? "보임" : "안 보임")")

            guard firstRun || !visible else { return }

            UserDefaults.standard.set(true, forKey: "hasSeenMenuBarNotice")
            notifier.notifyMenuBarNotice(seemsHidden: !visible)
        }
    }

    /// 표시를 가장 좁은 모드로 바꿉니다. 알림 버튼이 호출합니다.
    static func compact() {
        UserDefaults.standard.set(MenuBarStyle.icon.rawValue, forKey: "menuBarStyle")
        apLog("메뉴바를 아이콘만 모드로 바꿨습니다.")
    }
}
