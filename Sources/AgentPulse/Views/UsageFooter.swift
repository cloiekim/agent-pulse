import SwiftUI

/// 팝오버 하단의 usage 블록.
///
/// 디자인 규칙: neutral 트랙 + accent(단색) 채움.
/// 게이지에 색을 쓰지 않는 게 포인트입니다 — 색은 위쪽 상태 축이 전부 가져갑니다.
///
/// ⚠️ 막대는 **제공자가 준 진짜 퍼센트가 있을 때만** 그립니다.
/// 우리가 센 절대량에는 분모가 없으므로 숫자만 씁니다.
struct UsageFooter: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let groups: [UsageGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                // 회사가 바뀌는 자리에만 선을 넣습니다.
                if index > 0 {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    // ── 헤더: 회사 이름 + 요금제 ──────────────────
                    HStack(spacing: 6) {
                        BrandMark(agent: group.provider.iconAgent)
                            .frame(width: 12, height: 12)
                        Text(group.provider.vendorName)
                            .font(Theme.supporting(.semibold))
                            .foregroundStyle(theme.textPrimary)

                        if let tier = group.quotas.compactMap(\.planTier).first {
                            Text(tier)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(theme.subtleBg, in: Capsule())
                                .fixedSize()
                        }
                        Spacer(minLength: 0)
                    }

                    // ── 계정 한도 (퍼센트 막대) ──────────────────
                    ForEach(group.meters) { quota in
                        QuotaRow(quota: quota)
                    }

                    // ── 도구별 사용량 (토큰 개수) ────────────────
                    ForEach(group.counters) { quota in
                        ToolRow(quota: quota)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.footer)
    }
}

/// 도구 하나의 토큰 사용량. 눌러서 프로젝트별 내역을 펼칩니다.
private struct ToolRow: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let quota: UsageQuota

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    // 로고는 회사 헤더에 이미 있으므로 여기선 안 그립니다.
                    // 대신 왼쪽 여백으로 "헤더에 속한 항목" 임을 보입니다.
                    // 이름은 조용히, 값은 또렷하게.
                    // 여기서 읽고 싶은 건 "얼마나 썼나" 지 도구 이름이 아닙니다.
                    Text(quota.provider.displayName(loc))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize()

                    Spacer(minLength: 8)

                    Text(quota.valueText(loc))
                        .font(Theme.supporting(.medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        // ⚠️ 잘리느니 작아지는 게 낫습니다.
                        //    `resets...` 처럼 끝이 잘리면 정보가 통째로 사라지지만,
                        //    글자가 조금 작아지는 건 읽는 데 지장이 없습니다.
                        //    `Max 5x` 배지가 붙으면 자리가 더 좁아져서 여유가 필요합니다.
                        // ⚠️ 가운데 생략(`tok…esets`)은 뒤 생략보다 나쁩니다.
                        //    단어가 뒤섞여서 읽을 수 없는 글자가 됩니다.
                        //
                        //    그리고 0.65 까지 줄어들게 뒀더니 **너무 작아졌습니다.**
                        //    요금제 배지를 헤더로 옮겨서 자리가 넉넉해졌으니
                        //    거의 줄이지 않아도 됩니다.
                        .minimumScaleFactor(0.92)
                        .truncationMode(.tail)

                    if !quota.breakdown.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(quota.breakdown.isEmpty)

            if expanded, !quota.breakdown.isEmpty {
                BreakdownList(slices: quota.breakdown, tint: quota.provider.tint)
            }
        }
        // ⚠️ 들여쓰기를 넣었다가 뺐습니다.
        //    막대 행(5-hour·Weekly)은 왼쪽 끝에 붙는데 이 줄만 들여쓰면
        //    **혼자 쑥 들어간 것처럼** 보입니다.
        //    같은 헤더 밑에 있는 것들은 왼쪽을 맞추는 게 낫습니다.
        .help(quota.tooltip(loc))
    }
}

/// 프로젝트별 소비량. 가로 막대 + 이름 + 값.
///
/// ⚠️ 형식을 고른 이유:
/// 하는 일이 "크기 비교(많이 쓴 순)" 이므로 가로 막대가 맞습니다.
/// 길이가 이미 크기를 말하므로 **색은 한 가지만** 씁니다 —
/// 항목마다 다른 색을 주면 색이 순위를 뜻하는 것처럼 읽혀서 거짓 정보가 됩니다.
///
/// 이름·숫자는 텍스트 색을 씁니다. 막대 색을 글자에 쓰면 대비가 무너집니다.
private struct BreakdownList: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let slices: [UsageQuota.Slice]
    let tint: Color

    private var maxTokens: Int { max(slices.first?.tokens ?? 1, 1) }

    var body: some View {
        // ⚠️ 왼쪽 세로 가이드 한 줄로 "여기부터 하위 항목" 을 말합니다.
        //
        //    트리 선(`├─`)은 쓰지 않습니다. 깊이가 1단이고 항목이 2~5개뿐인데
        //    가지를 그리면 파일 탐색기처럼 보이고, **실제로 없는 구조**를
        //    암시합니다. 어디까지가 하위인지만 알려주면 충분합니다.
        HStack(alignment: .top, spacing: 8) {
            Capsule()
                .fill(theme.divider)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        // ⚠️ 가운데 자르기를 **뒤 자르기로 바꿨습니다.**
                        //    `interacti…emplate` 은 읽을 수가 없습니다.
                        //    프로젝트 이름은 앞부분이 구분에 제일 중요하므로
                        //    앞을 남기고 뒤를 자르는 게 맞습니다.
                        Text(slice.name)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // 막대는 짧아져도 비율을 읽는 데 지장이 없습니다.
                            // 그래서 남는 폭은 이름 쪽에 줍니다.
                            .frame(width: 124, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // 막대 끝은 4px 라운드, 바닥선에 붙여 그립니다.
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tint.opacity(0.16))
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tint.opacity(0.75))
                                    .frame(width: max(3, geo.size.width
                                            * CGFloat(slice.tokens) / CGFloat(maxTokens)))
                            }
                        }
                        .frame(height: 6)

                        Text(UsageQuota.compact(slice.tokens))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    // 이름이 잘렸을 때 전체를 볼 방법은 있어야 합니다.
                    .help(slice.name)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.bottom, 2)
    }
}

private struct QuotaRow: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let quota: UsageQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // ⚠️ 막대가 있을 때만 라벨을 왼쪽·값을 오른쪽으로 갈라놓습니다.
            //
            //    디자인 4a 는 아래 진행 막대가 두 텍스트를 하나로 묶어줬습니다.
            //    그런데 진짜 퍼센트가 없어 막대를 빼고 나니, 라벨만 왼쪽에 남고
            //    값은 저 멀리 오른쪽에 붙은 이상한 모양이 됐습니다.
            //    묶어주는 게 없으면 갈라놓으면 안 됩니다.
            if let fraction = quota.barFraction {
                // ⚠️ 라벨·막대·값을 **한 줄**에 둡니다.
                //    세로로 쌓으면 항목 하나에 두 줄씩 먹어서, 344px 팝오버에
                //    두 개만 들어가도 아래 내용이 밀려납니다.
                HStack(spacing: 8) {
                    // ⚠️ 라벨은 **절대 자르지 않습니다.**
                    //    `Sessi…` `Wee…` 는 아무 정보가 없습니다.
                    //    막대는 짧아져도 비율을 읽는 데 지장이 없지만,
                    //    잘린 단어는 무슨 말인지 알 수 없습니다.
                    //    자를 게 있으면 막대를 자르지 라벨을 자르면 안 됩니다.
                    Text(quota.displayLabel(loc))
                        .font(Theme.supporting())
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize()
                        .frame(width: 52, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.trackBg)
                            Capsule()
                                // ⚠️ 색은 **행동이 갈리는 곳에만** 씁니다.
                                //    4~5단계로 나누면 40% 와 60% 가 달라 보이는데
                                //    사용자가 할 일은 똑같습니다 — 없는 경계선을
                                //    만드는 셈이고, 색은 정보가 아니라 장식이 됩니다.
                                //
                                //    실제로 갈리는 건 두 곳뿐입니다:
                                //      · 80% — 곧 막힙니다. 큰 작업을 미룰 이유가 생깁니다
                                //      · 100% — 막혔습니다. 리셋까지 할 수 있는 게 없습니다
                                .fill(quota.isExhausted ? theme.errorText
                                      : fraction >= 0.8 ? theme.attentionFg
                                      : theme.trackFill)
                                .frame(width: max(3, fraction * geo.size.width))
                        }
                    }
                    .frame(minWidth: 60, maxWidth: .infinity, minHeight: 5, maxHeight: 5)

                    Text(quota.valueText(loc))
                        .font(Theme.supporting())
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()

                    // ⚠️ 흐리게만 하면 **못 알아챕니다.**
                    //    실제로 20분 지난 값을 지금 값으로 읽고
                    //    "다 안 썼다는데 왜 막히지?" 가 나왔습니다.
                    //    흐림은 곁눈으로 놓치기 쉬우니 글자로도 말합니다.
                    if quota.isStale {
                        Text(loc("old", "옛값"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.attentionFg)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(theme.attentionBg, in: Capsule())
                            .fixedSize()
                    }
                }
                .opacity(quota.isStale ? 0.55 : 1)
                .help(quota.isStale
                      ? loc("Last seen a while ago — open a claude.ai tab to refresh",
                            "갱신된 지 좀 됐습니다 — claude.ai 탭을 열면 새로 읽습니다")
                      : quota.tooltip(loc))
            } else {
                // 막대가 없으면 한 줄로 읽히게 둡니다.
                // `Used` 는 값이 이미 "12.3M tokens" 라고 말하므로 뺍니다.
                Text(quota.valueText(loc))
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .help(quota.tooltip(loc))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quota.provider.displayName(loc)): \(quota.valueText(loc))")
    }
}
