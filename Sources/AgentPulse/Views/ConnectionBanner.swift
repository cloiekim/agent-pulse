import SwiftUI

/// 끊긴 연결을 팝오버 맨 위에 한 줄로 알립니다.
///
/// ⚠️ 왜 필요한가:
/// 크롬이 업데이트되면서 확장이 통째로 사라진 적이 있습니다. 훅이 지워진 것도
/// 봤고요. 두 경우 다 **앱은 아무 말도 하지 않았습니다.** 평소처럼 조용했고,
/// 목록만 비어 있었습니다. 만든 사람조차 로그를 뒤지고 엉뚱한 명령을 쳐가며
/// 한참을 찾았습니다. 남이라면 그냥 지웠을 겁니다.
///
/// "아무 일도 안 일어남" 과 "보고 있지 않음" 은 화면에서 똑같이 생겼습니다.
/// 그 둘을 구별해주는 게 이 줄의 유일한 일입니다.
///
/// ⚠️ 그래서 **확실할 때만** 나타납니다:
///   · 한 번도 안 쓴 도구는 세지 않습니다 (Codex 안 쓰는 사람에게 잔소리 금지)
///   · 크롬이 꺼져 있으면 확장 침묵을 문제로 보지 않습니다 (정상이니까)
/// 틀린 경고는 침묵보다 나쁩니다. 한 번 속으면 다음부터 안 봅니다.
struct ConnectionBanner: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    let broken: [ConnectionStatus.Surface]
    @State private var expanded = false

    var body: some View {
        if !broken.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.attentionFg)

                        Text(headline)
                            .font(Theme.supporting(.medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(broken) { surface in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(surface.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .fixedSize()
                                // 무엇을 하면 되는지가 없으면 경고는 불평일 뿐입니다.
                                if let hint = surface.hint {
                                    Text(hint)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .background(theme.attentionRowBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
        }
    }

    /// ⚠️ 숫자를 앞세우지 않습니다. 하나뿐이면 **무엇이** 끊겼는지 바로 말하는 게
    ///    훨씬 쓸모 있습니다. `1개 연결 끊김` 은 결국 한 번 더 누르게 만듭니다.
    private var headline: String {
        if broken.count == 1 {
            return loc("\(broken[0].name) is disconnected",
                       "\(broken[0].name) 연결 끊김")
        }
        let names = broken.map(\.name).joined(separator: ", ")
        return loc("Disconnected — \(names)", "연결 끊김 — \(names)")
    }
}
