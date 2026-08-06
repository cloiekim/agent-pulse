import AppKit
import Observation

/// 메뉴바에 지금 무엇을 보여줄지 결정합니다.
///
/// 세 가지를 여기서 처리합니다:
///
/// 1. **디바운스** — 상태가 빠르게 튀면 메뉴바가 깜빡입니다.
///    특히 `PreToolUse` → `PostToolUse` 가 100ms 안에 오가면 눈이 아픕니다.
///    올라갈 때는 빠르게(0.3초), 내려갈 때는 느리게(1.0초) 반영합니다.
///    급한 걸 늦게 보여주는 것보다, 끝난 걸 조금 오래 보여주는 게 낫습니다.
///
/// 2. **메뉴 열림** — 팝오버가 열리면 메뉴바 항목이 시스템 강조색으로 하이라이트됩니다.
///    그 위에 앰버 캡슐이 겹치면 탁해집니다. 열려 있는 동안은 단색으로 바꿉니다.
///
/// 3. **라이트/다크** — 채워진 캡슐은 템플릿이 아니라 자동 반전이 안 됩니다.
///    시스템 외관을 관찰해서 자산 쌍을 직접 갈아끼웁니다.
@Observable
@MainActor
final class MenuBarPresenter {

    static let shared = MenuBarPresenter()

    /// 화면에 실제로 보이는 상태. 디바운스를 거친 값입니다.
    private(set) var shown: Snapshot = .idle
    /// 팝오버가 열려 있는가.
    var menuOpen = false

    // ⚠️ 표시 설정을 **여기에 들고 있습니다.**
    //
    // `MenuBarExtra` 라벨 안에서는 `AppSettings.shared` 관찰이 안 걸립니다.
    // `@AppStorage` → Environment → `onChange` → body 직접 읽기까지 네 번
    // 시도했는데 전부 실패했습니다.
    //
    // 반면 **이 객체의 프로퍼티는 확실히 전파됩니다** — `shown` 이 바뀔 때마다
    // 메뉴바가 다시 그려지는 게 그 증거입니다.
    // 그래서 설정이 바뀌면 AppSettings 가 여기로 밀어 넣습니다.
    var style: MenuBarStyle = AppSettings.shared.menuBarStyle
    var language: AppLanguage = AppSettings.shared.language

    var loc: Loc { Loc(language: language) }

    struct Snapshot: Equatable {
        var approvals = 0
        var failures = 0
        var running = 0

        static let idle = Snapshot()

        /// 급한 순서. 이 순서가 메뉴바가 무엇을 말할지 정합니다.
        var urgency: Int {
            if approvals > 0 { return 3 }
            if failures > 0 { return 2 }
            if running > 0 { return 1 }
            return 0
        }
    }

    // MARK: - 파형 애니메이션
    //
    // ⚠️ **실행 중일 때만** 돕니다. 유휴·승인 대기·실패에서는 타이머가 아예
    //    안 돕니다. 애니메이션이 필요한 건 "지금 뭔가 돌고 있다" 를 말할 때뿐이고,
    //    나머지 상태에서 도는 건 배터리만 쓰는 일입니다.
    //
    //    비용: 0.1초마다 **이미 그려둔** NSImage 하나를 갈아 끼웁니다.
    //    (MenuBarRenderer 가 위상별로 캐시합니다. 매번 새로 그리지 않습니다.)
    private(set) var phase: Int = 0
    private var animator: Task<Void, Never>?
    private var screensAsleep = false

    /// 지금 파형이 흘러야 하는가.
    private var shouldAnimate: Bool {
        shown.urgency == 1 && !screensAsleep
    }

    private func syncAnimation() {
        if shouldAnimate {
            guard animator == nil else { return }
            animator = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, !Task.isCancelled else { return }
                    self.phase = (self.phase + 1) % MenuBarRenderer.frameCount
                }
            }
        } else {
            animator?.cancel()
            animator = nil
            // 멈출 때는 시작 위상으로 돌려놓습니다.
            // 어중간한 데서 멈춰 있으면 정지 아이콘이 매번 달라 보입니다.
            if phase != 0 { phase = 0 }
        }
    }

    /// 화면이 잠들면 멈춥니다. 아무도 안 보는 그림을 그릴 이유가 없습니다.
    func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screensAsleep = true
                self?.syncAnimation()
            }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screensAsleep = false
                self?.syncAnimation()
            }
        }
    }

    private var pending: Task<Void, Never>?

    /// 마지막으로 **요청받은** 값. `shown` 과 다릅니다.
    ///
    /// ⚠️ 이게 없으면 메뉴바가 옛 상태에 얼어붙습니다.
    ///    `MenuBarExtra` 라벨은 SwiftUI 가 수시로 파괴하고 다시 만듭니다.
    ///    다시 만들어질 때마다 `onAppear` 가 같은 값으로 `update()` 를 부르는데,
    ///    예전 코드는 `shown` 하고만 비교해서 **매번 타이머를 다시 걸었습니다.**
    ///    재생성 간격이 디바운스(1초)보다 짧으면 타이머가 영영 안 끝나고,
    ///    실제로 `1 failed` 가 12분 넘게 남아 있었습니다 (실행 중인데도).
    ///
    ///    라벨이 다시 만들어지면 `onChange` 는 기준값을 잃어서 안 불립니다.
    ///    즉 모든 갱신이 `onAppear` 로만 들어옵니다. 같은 요청을 무시하는 게
    ///    선택이 아니라 필수입니다.
    private var requested: Snapshot = .idle

    /// 새 상태를 반영합니다. 디바운스를 거칩니다.
    func update(to next: Snapshot) {
        // 같은 요청이 또 들어오면 진행 중인 타이머를 **건드리지 않습니다.**
        guard next != requested else { return }
        requested = next

        pending?.cancel()
        pending = nil

        // 이미 그 값이 보이고 있으면 기다릴 이유가 없습니다.
        guard next != shown else { return }

        // 더 급해지면 빨리, 덜 급해지면 천천히.
        let delay: Duration = next.urgency > shown.urgency
            ? .milliseconds(300)
            : .seconds(1)

        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.shown = next
            self?.syncAnimation()
        }
    }

    // MARK: - 그릴 것

    /// ⚠️ 설정 값을 **밖에서 받습니다.**
    ///
    /// 안에서 `AppSettings.shared` 를 읽으면 `MenuBarExtra` 라벨에서 관찰이
    /// 안 걸립니다. `onChange` 도 마찬가지로 안 통합니다 — 라벨은 일반 View
    /// 계층 밖이라 그렇습니다. (언어 설정에서 이미 한 번 겪은 문제입니다.)
    ///
    /// 호출부가 `body` 안에서 값을 읽어 넘기면 그때 의존성이 등록됩니다.
    var image: NSImage {
        MenuBarRenderer.image(spec(style: style, loc: loc))
    }

    private func spec(style: MenuBarStyle, loc: Loc) -> MenuBarRenderer.Spec {

        // ⚠️ 문구는 **숫자가 먼저** 오고 두 단어를 넘지 않습니다.
        //    `1 needs approval` 은 130px 를 넘겨 시계를 밀어냅니다.
        //    메뉴바에서 폭은 예산이고, 두 단어가 그 예산입니다.
        let label: String
        let fill: NSColor?
        let content: NSColor

        switch shown.urgency {
        case 3:
            label = loc("\(shown.approvals) approve", "\(shown.approvals) 승인")
            fill = .attentionFill
            content = .attentionContent
        case 2:
            label = loc("\(shown.failures) failed", "\(shown.failures) 실패")
            fill = .failedFill
            content = .failedContent
        case 1:
            label = loc("\(shown.running) running", "\(shown.running) 실행")
            fill = nil
            content = .labelColor
        default:
            // 조용할 때는 맨 글리프. 아이콘만 모드가 아니어도 마찬가지입니다 —
            // 보고할 게 없으면 자리를 가장 적게 먹어야 합니다.
            return .init(kind: .bare(dot: nil), isTemplate: true, phase: phase)
        }

        // ⚠️ 모드에 따라 **내용**을 먼저 정합니다.
        //    예전엔 팝오버가 열릴 때 색만 빼려다 내용까지 전체 텍스트로
        //    갈아치워서, `숫자` 모드인데 클릭하면 `1 running` 으로 넓어졌습니다.
        //    색과 내용은 별개로 다뤄야 합니다.
        let count = shown.approvals > 0 ? shown.approvals
                  : shown.failures > 0 ? shown.failures : shown.running

        switch style {
        case .icon:
            // 아이콘만 — 상태는 6px 점으로만. 열려 있으면 점도 뺍니다.
            return menuOpen
                ? .init(kind: .bare(dot: nil), isTemplate: true, phase: phase)
                : .init(kind: .bare(dot: fill ?? .runningDotColor), isTemplate: false, phase: phase)

        case .count, .text:
            let text = style == .count ? "\(count)" : label

            // 팝오버가 열려 있는 동안은 단색 테두리로.
            // 시스템 하이라이트와 색이 겹치면 탁해집니다. **내용은 그대로 둡니다.**
            if menuOpen || fill == nil {
                return .init(kind: .outline(text: text), isTemplate: true, phase: phase)
            }
            return .init(kind: .filled(text: text, background: fill!, foreground: content),
                         isTemplate: false, phase: phase)
        }
    }
}

// MARK: - 메뉴바 전용 색
//
// ⚠️ 팝오버 색과 **다릅니다.** 메뉴바는 벽지 위에 얹히므로 대비 조건이 달라서,
//    디자인에서 별도 값을 줬습니다. 여기서만 씁니다.
private extension NSColor {
    static var isMenuBarDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static var attentionFill: NSColor {
        isMenuBarDark ? .init(srgbRed: 0.992, green: 0.812, blue: 0.310, alpha: 1)   // #FDCF4F
                      : .init(srgbRed: 0.910, green: 0.706, blue: 0.122, alpha: 1)   // #E8B41F
    }
    static var attentionContent: NSColor {
        isMenuBarDark ? .init(srgbRed: 0.200, green: 0.150, blue: 0.000, alpha: 1)   // #332600
                      : .init(srgbRed: 0.169, green: 0.125, blue: 0.000, alpha: 1)   // #2B2000
    }
    static var failedFill: NSColor {
        isMenuBarDark ? .init(srgbRed: 0.851, green: 0.310, blue: 0.290, alpha: 1)   // #D94F4A
                      : .init(srgbRed: 0.788, green: 0.251, blue: 0.231, alpha: 1)   // #C9403B
    }
    static var failedContent: NSColor {
        .init(srgbRed: 1.0, green: 0.941, blue: 0.937, alpha: 1)                     // #FFF0EF
    }
    static var runningDotColor: NSColor {
        .init(srgbRed: 0.247, green: 0.639, blue: 0.373, alpha: 1)                   // #3FA35F
    }
}
