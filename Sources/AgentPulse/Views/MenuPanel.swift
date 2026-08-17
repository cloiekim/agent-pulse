import SwiftUI

/// 메뉴바를 클릭했을 때 열리는 팝오버 전체.
///
/// 디자인 4a 구조:
///   헤더 (제목 + 요약 칩 + 톱니)
///   ├ 세션 행들 (최대 6개)
///   ├ "Show N more · 1 waiting · 3 done ⌄"
///   └ usage 블록
///
/// 상태에 따라 4a(목록) / 5b(빈 상태) / 5c(온보딩)로 갈립니다.
struct MenuPanel: View {
    /// 목록 내용의 실제 높이. ScrollView 에 넘겨줄 값입니다.
    @State private var listHeight: CGFloat = 0

    @Environment(\.colorScheme) private var systemScheme

    @Bindable var store: SessionStore
    let usage: UsageStore
    @Binding var isOnboarded: Bool

    @Bindable private var settings = AppSettings.shared
    private var language: AppLanguage { settings.language }
    private var loc: Loc { settings.loc }

    @State private var expanded = false
    @State private var showingSettings = false

    /// 접었을 때 보여주는 최대 행 수. 디자인 4a 는 6행 + 더보기.
    /// ⚠️ 첫 화면에 보이는 개수. 보관을 24시간으로 늘리면서 6 → 5 로 줄였습니다.
    ///    쌓이는 양이 많아졌으니 접힌 뒤가 길어지는 건 괜찮지만,
    ///    **첫 화면은 짧아야** 합니다. 지금 벌어지는 일이 먼저 보여야 하니까요.
    private let collapsedLimit = 5

    /// ⚠️ 파일을 읽는 검사라 매번 하면 낭비입니다. 팝오버가 열릴 때 한 번만
    ///    갱신합니다 — 어차피 사용자가 볼 수 있는 건 그 순간뿐입니다.
    @State private var brokenSurfaces: [ConnectionStatus.Surface] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            // ⚠️ 헤더 **바로 아래**입니다. 목록 위에 두면 "아무것도 안 돌고 있음" 과
            //    "보고 있지 않음" 이 같은 자리에서 경쟁합니다.
            //    끊긴 게 없으면 아무것도 그리지 않습니다.
            ConnectionBanner(broken: brokenSurfaces)

            // ⚠️ 온보딩은 **관문이 아니라 빈 화면의 한 종류**입니다.
            //
            // 처음엔 `!isOnboarded` 를 최우선으로 뒀는데, 그러면 터미널 세션이
            // 멀쩡히 들어와도 "Install extension" 화면에 가려집니다.
            // 실제 상태를 보여주는 게 이 앱의 존재 이유이므로 세션이 항상 이깁니다.
            if !store.sessions.isEmpty {
                // ⚠️ `ScrollView` 는 **자체 높이가 없습니다.**
                //    부모가 주는 만큼만 차지하는데, VStack 은 내용에 맞추려 하니
                //    서로 미루다 높이가 0 이 됩니다. `maxHeight` 는 상한만 정하고
                //    높이를 주지 않습니다.
                //    실제로 이 때문에 **목록이 통째로 안 보였습니다** (헤더와 사용량만 남음).
                //    그래서 내용 높이를 직접 재서 넘깁니다.
                ScrollView {
                    sessionList
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { listHeight = geo.size.height }
                                    .onChange(of: geo.size.height) { _, new in
                                        listHeight = new
                                    }
                            }
                        )
                }
                .frame(height: min(max(listHeight, 1), Self.maxListHeight))
                .scrollBounceBehavior(.basedOnSize)

                // 읽어온 게 하나도 없으면 블록 자체를 숨깁니다.
                // 빈 껍데기를 보여주느니 없는 게 낫습니다.
                if !usage.isEmpty {
                    UsageFooter(groups: usage.groups)
                }
            } else if !isOnboarded {
                OnboardingView(onSkip: { isOnboarded = true })
            } else {
                EmptyStateView()

                // ⚠️ 아무것도 안 돌고 있어도 **사용량은 봅니다.**
                //    오히려 그때가 "지금 시작해도 되나?" 를 확인하는 순간입니다.
                //    한도가 다 찼는데 그걸 모르고 시작하면 바로 막힙니다.
                if !usage.isEmpty {
                    UsageFooter(groups: usage.groups)
                }
            }
        }
        // 팝오버가 열려 있는 동안은 메뉴바 캡슐을 단색으로 바꿉니다.
        // 시스템 하이라이트와 색이 겹치면 탁해집니다.
        .onAppear {
            MenuBarPresenter.shared.menuOpen = true
            brokenSurfaces = ConnectionStatus.broken(loc)
        }
        .onDisappear { MenuBarPresenter.shared.menuOpen = false }
        .frame(width: Theme.popoverWidth)
        .background(theme.popover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.containerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.containerRadius, style: .continuous)
                .strokeBorder(theme.popoverBorder, lineWidth: 1)
        }
        .injectTheme(scheme)
        // 시스템 컨트롤(SF Symbol 등)도 같은 모드를 따르게 합니다.
        .environment(\.colorScheme, scheme)
    }

    private var scheme: ColorScheme { settings.appearance.resolved(system: systemScheme) }
    private var theme: Theme { Theme(scheme: scheme) }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 6) {
            Text("Agent Pulse")
                .font(Theme.title())
                .foregroundStyle(theme.textPrimary)

            Spacer(minLength: 8)

            // 요약 칩은 0이 아닐 때만 나타납니다.
            if !store.running.isEmpty {
                CountChip(kind: .running, count: store.running.count)
            }
            if !store.needsAttention.isEmpty {
                CountChip(kind: .needsYou, count: store.needsAttention.count)
            }

            Button { showingSettings.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                SettingsMenu()
                    .injectTheme(scheme)
                    .environment(\.colorScheme, scheme)
        // 시스템 컨트롤(SF Symbol 등)도 같은 모드를 따르게 합니다.
        .environment(\.colorScheme, scheme)
                        }
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    // MARK: 목록

    /// ⚠️ `idle` 은 접힌 쪽으로 보냅니다.
    ///
    ///    `idle` 은 "세션은 살아 있는데 아무 일도 안 함" 입니다.
    ///    그게 첫 화면에 있어서 도움이 된 순간이 없었고, 실제로는
    ///    같은 이름 다섯 개로 목록을 도배했습니다.
    ///    돌고 있는 것·끝난 것이 먼저 보여야 합니다.
    private var frontRunners: [AgentSession] {
        store.sessions.filter { $0.state != .idle }
    }

    private var idlers: [AgentSession] {
        store.sessions.filter { $0.state == .idle }
    }

    private var visible: [AgentSession] {
        if expanded { return frontRunners + idlers }
        return Array(frontRunners.prefix(collapsedLimit))
    }

    private var hidden: [AgentSession] {
        if expanded { return [] }
        return Array(frontRunners.dropFirst(collapsedLimit)) + idlers
    }

    /// 목록에 같은 제목이 두 개 이상 있는 것들.
    private var duplicatedTitles: Set<String> {
        var seen: Set<String> = []
        var dupes: Set<String> = []
        for session in store.sessions {
            if !seen.insert(session.title).inserted { dupes.insert(session.title) }
        }
        return dupes
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(visible) { session in
                SessionRow(
                    session: session,
                    onPrimaryAction: { primaryAction(for: session) },
                    onOpen: { DeepLink.open(session) },
                    duplicateTitle: duplicatedTitles.contains(session.title),
                    onDismiss: { store.dismiss(session) }
                )
            }

            if !hidden.isEmpty || expanded {
                overflowRow
            }
        }
    }

    /// ⚠️ 목록이 화면보다 길어지면 안 됩니다.
    ///    실제로 세션 14개가 쌓여서 팝오버가 화면을 넘어갔고,
    ///    스크롤도 안 돼서 아래쪽(사용량)이 잘렸습니다.
    private static let maxListHeight: CGFloat = 380

    /// "Show 4 more · 1 waiting · 3 done ⌄"  /  펼친 뒤엔 "접기 ⌃"
    ///
    /// ⚠️ 펼치기만 되고 접는 방법이 없었습니다.
    ///    한 번 펼치면 되돌릴 수 없는 UI 는 사용자를 가둡니다.
    private var overflowRow: some View {
        Button { withAnimation(.snappy(duration: 0.18)) { expanded.toggle() } } label: {
            HStack(spacing: 6) {
                if expanded {
                    Text(loc("Show less", "접기"))
                        .font(Theme.supporting(.medium))
                        .foregroundStyle(theme.textPrimary)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text(loc("Show \(hidden.count) more", "\(hidden.count)개 더 보기"))
                        .font(Theme.supporting(.medium))
                        .foregroundStyle(theme.textPrimary)
                    // 요약할 게 없으면 가운뎃점만 남아 이상해 보입니다.
                    if case let text = summary(of: hidden), !text.isEmpty {
                        Text("· " + text)
                            .font(Theme.supporting())
                            .foregroundStyle(theme.textSecondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.rowPaddingH)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private func summary(of sessions: [AgentSession]) -> String {
        let waiting = sessions.filter { $0.state == .queued || $0.state == .waitingInput }.count
        let done = sessions.filter { $0.state == .completed }.count
        // `idle` 도 세어야 합니다. 안 세면 숨긴 게 전부 idle 일 때
        // "5개 더 보기 ·" 처럼 요약이 비어버립니다.
        let idle = sessions.filter { $0.state == .idle }.count
        var parts: [String] = []
        if waiting > 0 { parts.append(loc("\(waiting) waiting", "\(waiting)개 대기")) }
        if done > 0 { parts.append(loc("\(done) done", "\(done)개 완료")) }
        if idle > 0 { parts.append(loc("\(idle) idle", "\(idle)개 대기 중")) }
        return parts.joined(separator: " · ")
    }

    // MARK: 액션

    /// ⚠️ 여기가 MVP 의 가장 큰 미해결 지점입니다. README 의 "승인 버튼" 섹션을 읽으세요.
    ///
    /// 훅은 도구 호출을 **차단**할 수는 있어도, 이미 떠 있는 대화형 프롬프트에
    /// 외부 프로세스가 "yes" 를 밀어넣을 수는 없습니다.
    /// MVP 에서는 "해당 터미널/탭으로 이동"으로 동작합니다.
    private func primaryAction(for session: AgentSession) {
        DeepLink.open(session)
    }
}
