import SwiftUI

/// 앱 언어.
///
/// 기본값은 English 입니다 — 배포 대상이 전 세계 개발자이고,
/// 마켓 분석의 SAM 추정도 영어권 기준이었습니다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case korean

    var id: String { rawValue }

    /// 설정 메뉴에 보이는 이름. 각 언어를 그 언어로 표기합니다 (관례).
    var displayName: String {
        switch self {
        case .english: "English"
        case .korean:  "한국어"
        }
    }

    var next: AppLanguage {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    /// 뷰가 아닌 곳(Notifier 등)에서 현재 언어를 읽을 때.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "")
            ?? .english
    }
}

/// 아주 작은 번역기.
///
/// `.strings` 파일 대신 인라인 쌍을 쓰는 이유:
/// - SPM 실행 파일에서 번들 로컬라이제이션 설정이 번거롭습니다
/// - 키 레지스트리를 따로 관리할 필요가 없습니다
/// - **영어 원문이 코드에 그대로 보여서** 읽는 사람이 맥락을 잃지 않습니다
///
/// 문자열이 200개를 넘어가면 그때 `.strings` 로 옮기세요.
struct Loc {
    let language: AppLanguage

    /// `loc("Needs approval", "승인 대기")` 처럼 씁니다.
    func callAsFunction(_ en: String, _ ko: String) -> String {
        language == .korean ? ko : en
    }
}

private struct LocKey: EnvironmentKey {
    static let defaultValue = Loc(language: .english)
}

extension EnvironmentValues {
    var loc: Loc {
        get { self[LocKey.self] }
        set { self[LocKey.self] = newValue }
    }
}

extension View {
    func injectLanguage(_ language: AppLanguage) -> some View {
        environment(\.loc, Loc(language: language))
    }
}
