import Foundation

/// Anthropic 의 사용량 창은 5시간 단위입니다.
///
/// ⚠️ 예전 주석은 "Anthropic·OpenAI 모두 5시간" 이라고 적혀 있었습니다.
///    **틀렸습니다.** OpenAI 는 2026-07-12 에 5시간 창을 없애고 주간 한도만
///    남겼습니다. 그걸 모르고 Codex 에도 이 규칙을 적용해서 없는 리셋 시각을
///    지어내 보여줬습니다. 지금은 Codex 는 리셋을 표시하지 않습니다.
///
///    남의 서비스 규칙을 코드에 박을 때는 근거를 같이 적어둬야 합니다.
///    규칙은 바뀌고, 바뀐 걸 알아차릴 방법이 없으면 조용히 거짓말을 하게 됩니다.
///
/// 블록 경계 규칙은 ccusage 와 맞췄습니다 — 도구마다 숫자가 다르면
/// 사용자는 둘 다 안 믿게 됩니다.
enum UsageBlock {

    static let duration: TimeInterval = 5 * 60 * 60

    /// 현재 블록의 시작 시각.
    ///
    /// ⚠️ 기준점을 **기억해야 합니다.**
    ///
    /// 처음엔 매번 "로그에서 가장 오래된 항목" 으로 다시 계산했습니다.
    /// 그런데 로그 스캔은 최근 10시간 파일만 봅니다 — 시간이 지나면 그 항목이
    /// 창을 벗어나고, **기준점이 통째로 움직입니다.** 그러면 리셋 시각이
    /// 아무 이유 없이 바뀌고, 사용자는 숫자를 믿지 않게 됩니다.
    ///
    /// 그래서 한 번 정한 기준점은 저장해두고, 블록이 끝날 때만 5시간씩 앞으로
    /// 감습니다. 앱을 껐다 켜도 유지됩니다.
    static func start(from timestamps: [Date],
                      now: Date = Date(),
                      anchorKey: String? = nil) -> Date? {

        // 저장된 기준점이 있으면 그걸 씁니다.
        if let anchorKey,
           let saved = UserDefaults.standard.object(forKey: anchorKey) as? Double {
            var start = Date(timeIntervalSince1970: saved)
            while start.addingTimeInterval(duration) <= now {
                start = start.addingTimeInterval(duration)
            }
            if start.timeIntervalSince1970 != saved {
                UserDefaults.standard.set(start.timeIntervalSince1970, forKey: anchorKey)
            }
            return start
        }

        guard let oldest = timestamps.min() else { return nil }

        // ⚠️ `date(bySetting:)` / `date(bySettingHour:)` 은 "잘라내기" 가 아니라
        //    "그 값이 되는 **다음** 시각 찾기" 입니다. 16:03 에 minute=0 을 주면
        //    16:00 이 아니라 17:00 이 나와서 블록 시작이 미래로 밀립니다.
        //    구성요소로 다시 조립하는 게 유일하게 명확한 방법입니다.
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: oldest)
        var start = cal.date(from: comps) ?? oldest

        while start.addingTimeInterval(duration) <= now {
            start = start.addingTimeInterval(duration)
        }

        // 처음 정한 기준점을 기억해둡니다.
        if let anchorKey {
            UserDefaults.standard.set(start.timeIntervalSince1970, forKey: anchorKey)
        }
        return start
    }

    /// 로그 파일을 훑을 때 쓰는 공통 규칙.
    ///
    /// - 수정 시각으로 먼저 거릅니다 (수백 MB 를 다 읽으면 안 됩니다)
    /// - 각 파일은 **뒤에서 512KB만** 읽습니다. 그보다 거슬러 올라갈 일이 없습니다.
    static func scanRecentLines(
        root: URL,
        extension ext: String = "jsonl",
        modifiedWithin seconds: TimeInterval,
        // ⚠️ 파일 경로도 같이 넘깁니다.
        //    Claude Code 는 프로젝트별로 폴더가 나뉘어 있어서,
        //    경로가 곧 "어느 프로젝트가 썼나" 에 대한 답입니다.
        handle: (Data, URL) -> Void
    ) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let fm = FileManager.default

        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in walker {
            guard url.pathExtension == ext else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified > cutoff else { continue }

            guard let file = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? file.close() }

            let size = (try? file.seekToEnd()) ?? 0
            let window: UInt64 = 512 * 1024
            try? file.seek(toOffset: size > window ? size - window : 0)
            guard let data = try? file.readToEnd(), !data.isEmpty else { continue }

            for line in data.split(separator: UInt8(ascii: "\n")) where line.count > 40 {
                handle(Data(line), url)
            }
        }
    }

    static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        return withFractional.date(from: iso) ?? plain.date(from: iso)
    }

    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
}
