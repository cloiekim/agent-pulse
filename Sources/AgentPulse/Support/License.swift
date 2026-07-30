import Foundation
import CryptoKit

/// 라이선스 키.
///
/// ⚠️ 왜 계정이 아니라 키인가:
/// 계정을 만들면 서버·DB·비밀번호 재설정·이메일 발송·세션 관리·보안 책임이
/// 전부 따라옵니다. 몇 주가 사라지는데, 지금 그걸로 얻는 건 결제뿐입니다.
/// 결제는 키 한 줄로 됩니다.
///
/// 그리고 이 앱의 셀링 포인트 중 하나가 **"서버가 없습니다"** 입니다.
/// 계정을 붙이는 순간 그 문장을 지워야 합니다.
/// (Bartender, CleanShot X, iStat Menus 전부 계정이 없습니다.)
///
/// ## 키 구조
///
///     base64url(payload).base64url(signature)
///
/// payload 는 JSON:
///
///     {"e":"이메일","t":"pro","i":발급시각,"d":기기수}
///
/// Ed25519 로 서명하고 **앱에 박힌 공개키로 오프라인 검증**합니다.
/// 서버가 필요 없고, 네트워크가 없어도 되고, 위조가 불가능합니다.
/// 키 발급은 Paddle/Lemon Squeezy 웹훅에서 개인키로 서명해 보내주면 됩니다.
enum License {

    /// 라이선스 UI 를 보여줄지.
    ///
    /// ⚠️ 지금은 **꺼둡니다.** 검증 구조(Ed25519 오프라인)는 다 만들어놨지만
    /// **가둘 유료 기능이 하나도 없습니다.** 키를 넣어도 헤더 글자만 바뀝니다.
    ///
    /// 쓸모없는 설정 항목은 그냥 자리만 차지하는 게 아니라 해롭습니다 —
    /// 테스터가 "돈 내야 하나?" 하고 멈칫하거나, 뭘 넣어야 하는지 몰라 헤맵니다.
    /// 실제로 테스트 빌드를 보내기 직전에 그 질문이 나왔습니다.
    ///
    /// 유료 기능이 생기면 이 한 줄만 `true` 로 바꾸면 됩니다.
    static let uiEnabled = false


    /// 앱에 박히는 공개키. 개인키는 절대 여기 두지 마세요.
    private static let publicKeyBase64URL = "kvmxuVL99ip0yCWuLgr5xWjjBPQNSz2517NC3O68FH0"

    private static let storageKey = "licenseKey"

    // MARK: - 상태

    struct Info: Equatable {
        let email: String
        let tier: String     // "pro"
        let devices: Int
        let issued: Date
    }

    /// 현재 저장된 라이선스. 없거나 위조면 nil.
    static var current: Info? {
        guard let key = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return verify(key)
    }

    static var isPro: Bool { current?.tier == "pro" }

    // MARK: - 저장

    /// 키를 검증하고 저장합니다. 실패하면 아무것도 바꾸지 않습니다.
    @discardableResult
    static func activate(_ key: String) -> Info? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let info = verify(trimmed) else { return nil }
        UserDefaults.standard.set(trimmed, forKey: storageKey)
        apLog("라이선스 활성화: \(info.tier) · \(info.email)")
        return info
    }

    static func deactivate() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        apLog("라이선스 해제됨")
    }

    // MARK: - 검증

    /// 왜 실패했는지. 사용자에게 다음 행동을 알려주기 위한 것입니다.
    ///
    /// ⚠️ "유효하지 않은 키입니다" 한 줄로는 아무도 못 고칩니다.
    /// 실제로 개인키(서명용)를 붙여넣고 왜 안 되는지 몰라 헤맨 일이 있었습니다.
    /// 세 종류의 키가 전부 base64 라 눈으로 구분이 안 되거든요.
    enum Failure {
        case empty
        case wrongShape     // 점으로 나뉜 두 부분이 아님 — 다른 키를 붙여넣은 경우
        case badSignature   // 모양은 맞는데 서명이 안 맞음 — 위조이거나 손상
    }

    static func inspect(_ key: String) -> Failure? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.split(separator: ".").count != 2 { return .wrongShape }
        return verify(trimmed) == nil ? .badSignature : nil
    }

    static func verify(_ key: String) -> Info? {
        let parts = key.split(separator: ".")
        guard parts.count == 2,
              let body = base64URLDecode(String(parts[0])),
              let signature = base64URLDecode(String(parts[1])),
              let publicKeyData = base64URLDecode(publicKeyBase64URL),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else { return nil }

        guard publicKey.isValidSignature(signature, for: body) else {
            apLog("라이선스 서명이 유효하지 않습니다")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let email = json["e"] as? String,
              let tier = json["t"] as? String
        else { return nil }

        return Info(
            email: email,
            tier: tier,
            devices: (json["d"] as? Int) ?? 1,
            issued: Date(timeIntervalSince1970: (json["i"] as? Double) ?? 0)
        )
    }

    /// base64url 은 표준 base64 와 문자 두 개가 다르고 패딩이 없습니다.
    private static func base64URLDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}
