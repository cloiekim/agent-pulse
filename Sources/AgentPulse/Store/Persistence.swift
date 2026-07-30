import Foundation

/// 앱을 껐다 켜도 기록이 남게 합니다.
///
/// 저장 위치: `~/.agent-pulse/state.json` (권한 0600)
///
/// ⚠️ 설계 원칙 — **살아있는 세션은 복원하지 않습니다.**
///
/// 앱이 꺼져 있는 동안 실제 Claude Code 프로세스가 어떻게 됐는지 알 방법이 없습니다.
/// `running` 이던 세션을 그대로 되살리면 "돌고 있다"는 거짓말이 되고,
/// 이 앱의 유일한 가치(지금 상태를 정확히 말해주는 것)가 무너집니다.
///
/// 그래서 복원 대상은 **이미 끝난 것**(completed / failed)과 활동 피드뿐입니다.
/// 진행 중이던 것은 버립니다. 새 이벤트가 오면 다시 잡힙니다.
enum Persistence {

    /// 이 기간이 지난 기록은 불러오지 않습니다.
    /// MVP 24시간 / Pro 30일 (PRD 참고).
    static let retention: TimeInterval = 24 * 60 * 60

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-pulse/state.json")
    }

    struct Snapshot: Codable {
        var sessions: [AgentSession]
        var feed: [AgentEvent]
        var savedAt: Date
    }

    // MARK: - 저장

    static func save(sessions: [AgentSession], feed: [AgentEvent]) {
        // 끝난 것만 남깁니다. 위 주석 참고.
        let keepable = sessions.filter { $0.state == .completed || $0.state == .failed }

        let snapshot = Snapshot(
            sessions: Array(keepable.prefix(100)),
            feed: Array(feed.prefix(500)),
            savedAt: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)

            let url = fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: url.path)
        } catch {
            apLog("저장 실패: \(error)")
        }
    }

    // MARK: - 불러오기

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var snapshot = try decoder.decode(Snapshot.self, from: data)

            let cutoff = Date().addingTimeInterval(-retention)
            snapshot.sessions = snapshot.sessions.filter { $0.lastEventAt > cutoff }
            snapshot.feed = snapshot.feed.filter { $0.timestamp > cutoff }

            apLog("복원: 세션 \(snapshot.sessions.count)개, 피드 \(snapshot.feed.count)개")
            return snapshot
        } catch {
            // 포맷이 바뀌었거나 깨진 경우 — 조용히 버리고 새로 시작합니다.
            apLog("저장 파일을 읽지 못해 새로 시작합니다: \(error)")
            return nil
        }
    }
}
