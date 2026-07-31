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
        case .count: "3"
        case .text:  loc("3 running", "3 실행")
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
    private var presenter: MenuBarPresenter { MenuBarPresenter.shared }

    var body: some View {
        // ⚠️ 캡슐·글리프·라벨을 **이미지 하나**로 그려서 넘깁니다.
        //    `MenuBarExtra` label 에 임의의 SwiftUI 뷰를 넣으면 폭이 0 으로 잡혀
        //    아이템이 아예 안 보일 수 있습니다. (MenuBarRenderer 주석 참고)
        //
        //    store 프로퍼티를 body 안에서 읽어야 `@Observable` 추적이 걸립니다.
        //    그래서 스냅샷 계산도 여기서 합니다.
        let snapshot = MenuBarPresenter.Snapshot(
            approvals: store.sessions.filter {
                $0.state == .needsApproval || $0.state == .waitingInput
            }.count,
            failures: store.sessions.filter { $0.state == .failed }.count,
            running: store.running.count
        )

        // ⚠️ 설정도 presenter 에서 읽습니다.
        //    `AppSettings.shared` 를 직접 읽으면 이 라벨에서는 관찰이 안 걸립니다.
        //    presenter 프로퍼티는 확실히 전파되므로 전부 그쪽으로 몰았습니다.
        Image(nsImage: presenter.image)
            .onAppear { presenter.update(to: snapshot) }
            .onChange(of: snapshot) { _, next in presenter.update(to: next) }
    }
}
