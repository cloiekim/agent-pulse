import AppKit
import CoreText

/// 앱에 넣어둔 Figtree 를 등록합니다.
///
/// ⚠️ 왜 번들에 넣는가:
/// 처음엔 `Font.custom("Figtree", …)` 를 쓰고, 없으면 시스템 폰트로 떨어지게 했습니다.
/// 그런데 **아무도 Figtree 를 설치하지 않습니다.** 실제로 만든 사람 Mac 에도
/// 없어서, 디자인대로 안 나오는데 아무 경고도 없이 조용히 시스템 폰트로
/// 돌고 있었습니다.
///
/// 사용자에게 `brew install --cask font-figtree` 를 시키는 건 말이 안 됩니다.
/// 앱이 자기 폰트를 들고 다니는 게 맞습니다.
///
/// Figtree 는 SIL Open Font License 라 번들 배포가 허용됩니다.
enum FontLoader {

    private static let names = ["Figtree-Regular", "Figtree-Medium", "Figtree-SemiBold"]

    /// 앱 시작 시 한 번 부릅니다.
    static func registerBundledFonts() {
        var loaded = 0
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                apLog("폰트 파일을 못 찾음: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                loaded += 1
            } else {
                // 이미 등록돼 있으면 실패로 옵니다 — 문제가 아닙니다.
                let code = (error?.takeUnretainedValue() as Error?).map { String(describing: $0) } ?? "-"
                apLog("폰트 등록 실패(무시 가능): \(name) — \(code)")
            }
        }
        apLog("Figtree \(loaded)/\(names.count)개 등록됨")
    }
}
