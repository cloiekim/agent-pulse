import Foundation

/// Claude 데스크톱 앱이 남기는 세션 정보를 읽습니다.
///
/// 출처: `~/Library/Application Support/Claude/claude-code-sessions/<a>/<b>/local_<uuid>.json`
///
/// 실제 구조 (직접 확인함):
/// ```
/// { "sessionId": "local_4e93…",
///   "cliSessionId": "e4a4183d-205b-410e-86b2-01edad34351a",   ← 훅의 session_id 와 같음
///   "cwd": "/Users/…/pandas-money",
///   "title": "Set up Firebase Firestore integration",         ← 사람이 읽는 제목
///   "lastActivityAt": 1785221045146 }
/// ```
///
/// 이 파일이 두 가지 문제를 동시에 풉니다:
///
/// 1. **제목** — 훅은 제목을 안 줍니다. 그래서 폴더명(`interactive-deck-template`)을
///    쓰고 있었는데, 사용자가 데스크톱 앱에서 보는 제목과 달라 혼란스럽습니다.
///
/// 2. **Jump 목적지** — 데스크톱 앱에서 시작한 세션인데 터미널을 띄우면 엉뚱한 곳입니다.
///    여기 있는 세션이면 Claude 앱으로 보내야 합니다.
enum ClaudeDesktopSessions {

    struct Entry {
        let title: String?
        let cwd: String?
        /// 같은 `cliSessionId` 를 가진 파일이 여러 개일 때 최신 것을 고르는 기준.
        let lastActivityAt: Date
    }

    private static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    // 파일을 매번 훑으면 비쌉니다. 짧게 캐시합니다.
    private static let lock = NSLock()
    private static var cache: [String: Entry] = [:]
    private static var cachedAt = Date.distantPast
    private static let ttl: TimeInterval = 20

    /// 훅의 `session_id` 로 데스크톱 세션 정보를 찾습니다.
    static func lookup(cliSessionId: String) -> Entry? {
        refreshIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return cache[cliSessionId]
    }

    /// 이 세션이 데스크톱 앱에서 시작됐는가.
    static func isFromDesktop(_ cliSessionId: String) -> Bool {
        lookup(cliSessionId: cliSessionId) != nil
    }

    private static func refreshIfNeeded() {
        lock.lock()
        let stale = Date().timeIntervalSince(cachedAt) > ttl
        lock.unlock()
        guard stale else { return }

        var fresh: [String: Entry] = [:]
        let fm = FileManager.default

        if let walker = fm.enumerator(at: root,
                                      includingPropertiesForKeys: nil,
                                      options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                guard url.lastPathComponent.hasPrefix("local_"),
                      url.pathExtension == "json",
                      let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cliID = json["cliSessionId"] as? String
                else { continue }

                let activity = (json["lastActivityAt"] as? Double).map {
                    Date(timeIntervalSince1970: $0 / 1000)
                } ?? .distantPast

                let entry = Entry(
                    title: (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    cwd: json["cwd"] as? String,
                    lastActivityAt: activity
                )

                // ⚠️ 같은 cliSessionId 를 가진 파일이 여러 개일 수 있습니다.
                //    아무거나 덮어쓰면 **엉뚱한 대화의 제목**이 붙습니다.
                //    (`interactive-deck-template` 프로젝트에 다른 프로젝트의
                //     제목이 붙는 걸 실제로 봤습니다.)
                if let existing = fresh[cliID], existing.lastActivityAt > activity { continue }
                fresh[cliID] = entry
            }
        }

        lock.lock()
        cache = fresh
        cachedAt = Date()
        lock.unlock()
    }
}
