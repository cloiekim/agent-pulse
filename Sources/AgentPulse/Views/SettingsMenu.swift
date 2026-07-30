import SwiftUI
import AppKit

/// 디자인 5a — 톱니를 눌렀을 때 뜨는 216px 드롭다운.
///
/// ⚠️ SwiftUI `Menu` 를 쓰지 않는 이유:
/// macOS 에서 `Menu` 의 label 은 시스템이 NSMenuItem 처럼 재조립합니다.
/// `HStack` + `Spacer` 로 짠 행 레이아웃이 통째로 무너지고, 아이콘이 왼쪽으로
/// 튀거나 오른쪽 내용이 사라집니다. 그래서 하위 메뉴도 직접 만듭니다.
struct SettingsMenu: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    // ⚠️ Environment 로 받으면 안 됩니다 — 팝오버는 뜰 때의 environment 를
    //    붙들고 있어서, 언어를 바꿔도 이미 열려 있는 화면에 반영되지 않습니다.
    private var loc: Loc { AppSettings.shared.loc }

    @Bindable private var settings = AppSettings.shared
    @State private var showingLicense = false
    @State private var pairing = false

    private var menuBarStyle: MenuBarStyle { settings.menuBarStyle }
    private var language: AppLanguage { settings.language }
    private var license: License.Info? { settings.license }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            PickerRow(
                title: loc("Menu bar", "메뉴바"),
                selection: Binding(
                    get: { settings.menuBarStyle.rawValue },
                    set: { settings.menuBarStyle = MenuBarStyle(rawValue: $0) ?? .text }
                ),
                options: MenuBarStyle.allCases.map {
                    PickerOption(value: $0.rawValue,
                                 label: $0.displayName(loc),
                                 sample: $0.sample(loc))
                },
                showsPulseIcon: true
            )

            PickerRow(
                title: loc("Appearance", "화면 모드"),
                selection: Binding(
                    get: { settings.appearance.rawValue },
                    set: { settings.appearance = Appearance(rawValue: $0) ?? .system }
                ),
                options: Appearance.allCases.map {
                    PickerOption(value: $0.rawValue, label: $0.displayName(loc), sample: "")
                },
                showsPulseIcon: false
            )

            PickerRow(
                title: loc("Language", "언어"),
                selection: Binding(
                    get: { settings.language.rawValue },
                    set: { settings.language = AppLanguage(rawValue: $0) ?? .english }
                ),
                options: AppLanguage.allCases.map {
                    PickerOption(value: $0.rawValue, label: $0.displayName, sample: "")
                },
                showsPulseIcon: false
            )

            ToggleRow(title: loc("Notifications", "알림"), isOn: $settings.notificationsEnabled)

            // 알림을 켠 경우에만 종류를 고릅니다. 꺼져 있으면 의미가 없으니 숨깁니다.
            if settings.notificationsEnabled {
                KindRow(title: loc("Needs approval", "승인 대기"),
                        kind: .approval, settings: settings)
                KindRow(title: loc("Failed", "실패"),
                        kind: .failure, settings: settings)
                KindRow(title: loc("Done", "완료"),
                        kind: .completed, settings: settings)
            }
            // 실제 시스템 등록까지 합니다. 값만 저장하고 마는 스위치는
            // 켰다고 믿게 만들고 배신하므로, 실패하면 되돌립니다.
            ActionRow(title: pairing
                      ? loc("Waiting for the extension…", "확장을 기다리는 중…")
                      : loc("Connect Chrome extension", "크롬 확장 연결")) {
                LocalEventServer.beginPairing()
                pairing = true
                SetupActions.run("browser")
                // 창이 닫히면 라벨을 되돌립니다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { pairing = false }
            }

            ToggleRow(title: loc("Accept remote agents", "원격 에이전트 허용"),
                      isOn: $settings.allowRemoteAgents)

            // 켜면 다른 기기에서 훅을 걸 주소를 알려줍니다.
            // 이걸 안 알려주면 사용자가 시스템 설정을 뒤지다 포기합니다.
            if settings.allowRemoteAgents {
                if let ip = LocalAddress.lan() {
                    Text(loc("On the other Mac: ./install-claude-hooks.sh --host \(ip)",
                             "다른 Mac 에서: ./install-claude-hooks.sh --host \(ip)"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 4)
                } else {
                    Text(loc("Restart the app to apply.", "앱을 다시 시작해야 적용됩니다."))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 4)
                }
            }

            ToggleRow(title: loc("Launch at login", "로그인 시 실행"),
                      isOn: $settings.launchAtLogin,
                      enabled: LaunchAtLogin.isSupported) { wanted in
                if !LaunchAtLogin.set(wanted) {
                    settings.launchAtLogin = !wanted
                }
            }

            Rectangle().fill(theme.divider).frame(height: 1).padding(.vertical, 4)

            if License.uiEnabled {
            ActionRow(title: license == nil
                      ? loc("Enter license key", "라이선스 키 입력")
                      : loc("Remove license", "라이선스 해제")) {
                if license == nil {
                    showingLicense.toggle()
                } else {
                    License.deactivate()
                    settings.license = nil
                }
            }

            // ⚠️ 팝오버 안에 또 팝오버를 띄우지 않습니다.
            //    메뉴바 팝오버에서는 중첩이 불안정하고, TextEditor 는 그 안에서
            //    앱을 통째로 죽입니다. 제자리에서 펼치는 게 안전합니다.
            if showingLicense, license == nil {
                LicenseEntry { info in
                    settings.license = info
                    showingLicense = false
                }
            }
            }

            ActionRow(title: loc("Quit Agent Pulse", "Agent Pulse 종료"), trailing: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(6)
        .frame(width: 216)
        .background(theme.popover)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(License.uiEnabled ? (license?.email ?? "Agent Pulse") : "Agent Pulse")
                .font(Theme.supporting(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            // 라이선스 UI 가 꺼져 있으면 "로컬에서만 돈다" 는 사실만 말합니다.
            // 이게 이 앱에서 사람들이 실제로 궁금해하는 유일한 것이기도 합니다.
            Text(License.uiEnabled && license != nil
                 ? loc("Pro · up to \(license!.devices) Macs", "Pro · 최대 \(license!.devices)대")
                 : loc("Runs entirely on this Mac", "이 Mac 에서만 실행됩니다"))
                .font(Theme.supporting())
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - 선택지

struct PickerOption: Identifiable {
    var id: String { value }
    let value: String
    let label: String
    /// 비어 있으면 미리보기를 그리지 않습니다.
    let sample: String
}

// MARK: - 행 종류

// MARK: - 선택 행

/// 클릭하면 **제자리에서 펼쳐지는** 선택 행.
///
/// ⚠️ 절대 팝오버를 중첩하지 마세요.
///
/// 설정 메뉴 자체가 이미 `MenuBarExtra` 팝오버입니다. 그 안에서 또 팝오버를 띄우면
/// macOS 에서 조용히 망가집니다 — 열리긴 하는데 **버튼 클릭이 전달되지 않습니다.**
/// 에러도 안 나고 로그도 없어서, 사용자 눈에는 "눌러도 아무 일이 없다" 로만 보입니다.
///
/// 실제로 메뉴바 모드와 언어 선택이 둘 다 이것 때문에 한 번도 동작한 적이 없었고,
/// 라이선스 입력은 같은 이유로 앱을 죽였습니다.
private struct PickerRow: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let title: String
    @Binding var selection: String
    let options: [PickerOption]
    /// 미리보기에 메뉴바 파형 아이콘을 같이 그릴지.
    let showsPulseIcon: Bool

    @State private var expanded = false
    @State private var hovering = false

    private var current: PickerOption? {
        options.first { $0.value == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.supporting())
                        .foregroundStyle(theme.textPrimary)

                    Spacer(minLength: 8)

                    if let current {
                        if current.sample.isEmpty {
                            Text(current.label)
                                .font(Theme.supporting())
                                .foregroundStyle(theme.textSecondary)
                        } else {
                            SamplePreview(text: current.sample, showsIcon: showsPulseIcon)
                        }
                    }

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(hovering ? theme.subtleBg : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if expanded {
                ForEach(options) { option in
                    OptionRow(option: option,
                              isSelected: option.value == selection,
                              showsPulseIcon: showsPulseIcon) {
                        selection = option.value
                        expanded = false
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
}

private struct OptionRow: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let option: PickerOption
    let isSelected: Bool
    let showsPulseIcon: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 10)

                Text(option.label)
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 8)

                if !option.sample.isEmpty {
                    SamplePreview(text: option.sample, showsIcon: showsPulseIcon)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hovering ? theme.subtleBg : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 메뉴바를 축소해서 흉내낸 칩.
private struct SamplePreview: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let text: String
    let showsIcon: Bool

    var body: some View {
        HStack(spacing: 3) {
            if showsIcon {
                Image(nsImage: PulseIcon.menuBar)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 11, height: 11)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.subtleBg, in: Capsule())
        .fixedSize()
    }
}

/// 켜고 끄는 행.
private struct ToggleRow: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let title: String
    @Binding var isOn: Bool
    /// false 면 흐리게 표시하고 클릭을 막습니다.
    var enabled: Bool = true
    /// 값이 바뀐 뒤 호출됩니다. 실패하면 여기서 되돌리세요.
    var onChange: ((Bool) -> Void)?

    @State private var hovering = false

    var body: some View {
        Button {
            guard enabled else { return }
            isOn.toggle()
            onChange?(isOn)
        } label: {
            HStack {
                Text(title)
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .opacity(isOn ? 1 : 0)
            }
            .opacity(enabled ? 1 : 0.4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovering && enabled ? theme.subtleBg : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(enabled ? "" : "make-app.sh 로 .app 을 만들어 실행하면 사용할 수 있습니다")
    }
}

/// 누르면 뭔가 실행되는 행.
private struct ActionRow: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let title: String
    var trailing: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Text(trailing)
                    .font(Theme.supporting())
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovering ? theme.subtleBg : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}


/// 라이선스 키 입력. 설정 메뉴 안에서 제자리에 펼쳐집니다.
///
/// ⚠️ `TextEditor` 를 쓰면 안 됩니다 — 메뉴바 팝오버 안에서 앱이 죽습니다.
///    `TextField` 는 가볍고 붙여넣기도 잘 됩니다.
///
/// 서버에 물어보지 않습니다 — 앱에 박힌 공개키로 그 자리에서 검증합니다.
/// 비행기 안에서도 되고, 우리 서버가 죽어도 사용자는 영향받지 않습니다.
private struct LicenseEntry: View {
    // ⚠️ Environment 로 받으면 팝오버에서 갱신이 안 됩니다 (언어에서 겪은 문제).
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }
    private var loc: Loc { AppSettings.shared.loc }

    var onActivated: (License.Info) -> Void

    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(loc("Paste key", "키 붙여넣기"), text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(theme.subtleBg,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit(activate)

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.errorText)
            } else {
                Text(loc("Checked on this Mac — nothing is sent.",
                         "이 Mac 에서 확인하며 전송하지 않습니다."))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: activate) {
                Text(loc("Activate", "활성화"))
                    .font(Theme.supporting(.semibold))
                    .foregroundStyle(theme.accentFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(theme.accentBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(key.isEmpty)
            .opacity(key.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func activate() {
        if let info = License.activate(key) {
            onActivated(info)
            return
        }
        // 무엇이 잘못됐는지 말해줍니다. "유효하지 않음" 만으로는 못 고칩니다.
        switch License.inspect(key) {
        case .empty:
            error = loc("Paste your key first.", "키를 먼저 붙여넣으세요.")
        case .wrongShape:
            error = loc("That doesn't look like a license key — it should have a dot in the middle.",
                        "라이선스 키가 아닌 것 같습니다 — 가운데에 점(.)이 있어야 합니다.")
        case .badSignature:
            error = loc("This key isn't valid for Agent Pulse.",
                        "Agent Pulse 용 키가 아닙니다.")
        case .none:
            error = nil
        }
    }
}


/// 알림 종류 하나를 켜고 끄는 행. 본 스위치 아래에 들여써서 종속 관계를 보여줍니다.
private struct KindRow: View {
    @Environment(\.colorScheme) private var systemScheme
    private var theme: Theme { AppSettings.shared.theme(for: systemScheme) }

    let title: String
    let kind: NotificationKinds
    let settings: AppSettings

    @State private var hovering = false

    private var isOn: Bool { settings.notificationKinds.contains(kind) }

    var body: some View {
        Button {
            if isOn {
                settings.notificationKinds.remove(kind)
            } else {
                settings.notificationKinds.insert(kind)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 10)

                Text(title)
                    .font(Theme.supporting())
                    .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(hovering ? theme.subtleBg : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
