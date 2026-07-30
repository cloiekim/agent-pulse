import SwiftUI

/// 메뉴바 표시 방식. 설정에서 사용자가 고릅니다.
///
/// 왜 선택지를 주는가:
/// 메뉴바 공간은 사람마다 사정이 다릅니다. 노치가 있는 MacBook 에서
/// 아이콘을 20개 띄워둔 사람에게 "Needs approval" 은 사치이고,
/// 반대로 `●` 하나로는 그게 무슨 뜻인지 학습이 필요합니다.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// 아이콘만. 자세한 건 팝오버에서.
    case icon
    /// 아이콘 + 숫자 + 점. (디자인 4a 기본값)
    case count
    /// 아이콘 + 상태 텍스트. 가장 명확하지만 가장 넓습니다.
    case text

    var id: String { rawValue }

    func displayName(_ loc: Loc) -> String {
        switch self {
        case .icon:  loc("Icon only", "아이콘만")
        case .count: loc("Count", "숫자")
        case .text:  loc("Text", "텍스트")
        }
    }

    /// 설정에서 "이걸 고르면 이렇게 보인다"를 보여줄 때 쓰는 예시.
    ///
    /// 실제 상태 대신 고정된 샘플을 쓰는 이유: 지금 아무 일도 안 일어나고 있으면
    /// 세 모드가 전부 똑같이 밋밋하게 보여서 비교가 안 됩니다.
    func sample(_ loc: Loc) -> String {
        switch self {
        case .icon:  ""
        case .count: "2 ●"
        case .text:  loc("Working 2", "작업 중 2")
        }
    }

    var next: MenuBarStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// 메뉴바에 실제로 앉아 있는 것.
///
/// ⚠️ `MenuBarExtra` label 제약:
/// 임의의 SwiftUI 뷰(Shape, Circle, GeometryReader 등)를 넣으면 아이템이
/// 폭 0으로 잡혀 **아예 안 보일 수 있습니다.** 안정적인 건 `Image` 와 `Text` 뿐입니다.
///
/// store 를 직접 받는 이유: `@Observable` 의 변경 추적은 **View body 안에서**
/// 프로퍼티를 읽어야 등록됩니다. App 스코프에서 값을 꺼내 넘기면
/// 상태가 바뀌어도 메뉴바가 갱신되지 않습니다.
struct MenuBarLabel: View {
    let store: SessionStore

    // ⚠️ `@AppStorage` 를 쓰면 안 됩니다 — MenuBarExtra 의 label 은 일반 View
    //    계층 밖에 있어서 변경이 안정적으로 전달되지 않습니다.
    //    설정을 바꿔도 메뉴바가 그대로 있는 버그가 그것 때문이었습니다.
    private var settings: AppSettings { AppSettings.shared }
    private var style: MenuBarStyle { settings.menuBarStyle }
    private var loc: Loc { settings.loc }

    var body: some View {
        Image(nsImage: PulseIcon.menuBar)
        if let suffix { Text(suffix) }
    }

    private var suffix: String? {
        switch style {
        case .icon:  return nil
        case .count: return countSuffix
        case .text:  return textSuffix
        }
    }

    // MARK: 숫자 모드

    /// 디자인 4a: 아이콘 + 실행 개수 + 주의 점.
    ///
    /// `activeCount` 는 승인 대기·입력 대기도 포함합니다.
    /// 승인 대기로 넘어가는 순간 숫자가 사라지면 "몇 개 돌리고 있나"에 답을 못 하니까요.
    private var countSuffix: String? {
        let n = store.activeCount
        let attention = !store.needsAttention.isEmpty

        switch (n, attention) {
        case (0, false): return nil
        case (0, true):  return " ●"
        case (let n, false): return " \(n)"
        case (let n, true):  return " \(n) ●"
        }
    }

    // MARK: 텍스트 모드

    /// 가장 급한 것 **하나만** 말합니다.
    ///
    /// 메뉴바는 대시보드가 아닙니다. "지금 네가 필요한가, 아닌가"에만 답하면 되고,
    /// 자세한 건 클릭해서 보는 겁니다. 여러 상태를 한 줄에 늘어놓으면
    /// 폭만 먹고 아무것도 전달이 안 됩니다.
    private var textSuffix: String? {
        let approvals = store.sessions.filter { $0.state == .needsApproval }.count
        let inputs    = store.sessions.filter { $0.state == .waitingInput }.count
        let failures  = store.sessions.filter { $0.state == .failed }.count
        let running   = store.running.count

        // ⚠️ 어휘는 메뉴바·헤더 칩·행 알약이 **반드시 같아야 합니다.**
        //    같은 상태를 `Working` / `1 running` / `Running` 세 가지로 부르면
        //    사용자는 서로 다른 일이 벌어지고 있다고 읽습니다.
        //    디자인 4a 가 "running" 을 쓰므로 거기에 맞춥니다.
        let attention = approvals + inputs

        if attention > 0 {
            return " " + (attention == 1
                ? loc("Needs you", "확인 필요")
                : loc("Needs you \(attention)", "확인 필요 \(attention)"))
        }
        if failures > 0 {
            return " " + (failures == 1
                ? loc("Failed", "실패")
                : loc("Failed \(failures)", "실패 \(failures)"))
        }
        if running > 0 {
            return " " + (running == 1
                ? loc("Running", "실행 중")
                : loc("Running \(running)", "실행 중 \(running)"))
        }

        // 아무 일도 없을 때도 한 마디는 합니다.
        //
        // 완전히 침묵하면 "앱이 살아있긴 한가?" 를 확인할 방법이 없어서
        // 사용자가 불안해집니다. 조용한 상태를 **명시적으로** 말해주는 편이
        // 안심되고, 아이콘만 덩그러니 있는 것보다 읽기도 쉽습니다.
        // 이것도 거슬리면 설정에서 Icon only 로 바꾸면 됩니다.
        // ⚠️ 조용할 때는 **아무 글자도 쓰지 않습니다.**
        //
        //    예전엔 `Idle` / `대기 중` 을 띄웠는데, 그건 "할 말이 없다" 를
        //    굳이 말로 하는 것입니다. 아이콘만 있으면 그게 이미 조용하다는 뜻이고,
        //    메뉴바 폭도 아낍니다 — 아이콘이 잘려서 안 보이던 문제와 직결됩니다.
        //
        //    메뉴바 항목은 **보고할 게 없을 때 가장 작아야 합니다.**
        return ""

    }
}
