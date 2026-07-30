import Foundation

/// 이 Mac 의 LAN 주소.
///
/// 원격 기기에서 훅을 걸 때 필요합니다. 사용자가 직접 시스템 설정을 뒤져
/// 찾게 하면 거기서 대부분 포기합니다.
enum LocalAddress {

    /// 예: "192.168.0.12". 못 찾으면 nil.
    static func lan() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var best: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard ptr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(ptr.pointee.ifa_addr,
                              socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let address = String(cString: host)
            let name = String(cString: ptr.pointee.ifa_name)

            // Wi-Fi(en0) 를 가장 선호합니다. 그다음이 유선입니다.
            if name == "en0" { return address }
            if best == nil { best = address }
        }
        return best
    }
}
