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
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                // ⚠️ 항목이 하나뿐이면 헤더를 따로 두지 않습니다.
                //    "Claude Code" 한 줄 + 값 한 줄 = 두 줄인데, 묶을 게 없는
                //    헤더는 자리만 먹습니다. 여러 항목일 때만 헤더가 일을 합니다.
                if group.quotas.count == 1, let quota = group.quotas.first,
                   quota.barFraction == nil {
                    CompactRow(provider: group.provider, quota: quota)
                        .padding(.top, index == 0 ? 0 : 2)
                } else {
                    HStack(spacing: 6) {
                        BrandMark(agent: group.provider.iconAgent)
                            .frame(width: 12, height: 12)
                        Text(group.provider.displayName)
                            .font(Theme.supporting(.semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.top, index == 0 ? 0 : 2)

                    ForEach(group.quotas) { quota in
                        QuotaRow(quota: quota)
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

/// 로고 + 이름 + 값을 한 줄에.
private struct CompactRow: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let provider: UsageQuota.Provider
    let quota: UsageQuota

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    BrandMark(agent: provider.iconAgent)
                        .frame(width: 12, height: 12)

                    Text(provider.displayName)
                        .font(Theme.supporting(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize()

                    // 요금제 등급. 한도 숫자는 모르지만 **기준**은 알려줍니다.
                    // 조용한 회색 알약으로 — 정보이지 경고가 아닙니다.
                    if let tier = quota.planTier {
                        Text(tier)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.subtleBg, in: Capsule())
                            .fixedSize()
                    }

                    Spacer(minLength: 8)

                    Text(quota.valueText(loc))
                        .font(Theme.supporting())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        // 한국어는 같은 뜻이 더 길어서 좁은 화면에선 살짝 줄입니다.
                        .minimumScaleFactor(0.85)

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
                BreakdownList(slices: quota.breakdown, tint: provider.tint)
            }
        }
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
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Text(slice.name)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 96, alignment: .leading)

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
            }
        }
        .padding(.leading, 18)
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
                HStack {
                    Text(quota.displayLabel(loc))
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(quota.valueText(loc))
                        .foregroundStyle(theme.textPrimary)
                        .fontWeight(.medium)
                }
                .font(Theme.supporting())

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.trackBg)
                        Capsule()
                            .fill(theme.trackFill)
                            .frame(width: fraction * geo.size.width)
                    }
                }
                .frame(height: 5)
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
        .accessibilityLabel("\(quota.provider.displayName): \(quota.valueText(loc))")
    }
}
