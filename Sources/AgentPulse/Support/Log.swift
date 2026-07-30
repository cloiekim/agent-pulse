import Foundation

/// 파일에 남기는 로그.
///
/// ⚠️ `NSLog` 만으로는 부족합니다.
/// ad-hoc 서명된 앱의 `NSLog` 출력은 macOS 통합 로깅에 안 올라가는 경우가 있어서,
/// `log show` 로 아무것도 못 봅니다. 실제로 알림 클릭이 되는지 확인하려다
/// 로그가 통째로 비어서 진단이 막혔습니다.
///
/// 그래서 항상 파일에도 씁니다:
///
///     tail -f ~/.agent-pulse/debug.log
///
/// 남편분처럼 다른 사람이 테스트할 때도 이 파일 하나만 받으면 됩니다.
func apLog(_ message: String) {
    let line = "\(Log.stamp()) \(message)\n"
    NSLog("[AgentPulse] \(message)")
    Log.append(line)
}

enum Log {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-pulse/debug.log")
    }

    /// 로그가 무한히 커지지 않게 하는 상한.
    private static let maxBytes = 512 * 1024

    private static let queue = DispatchQueue(label: "agentpulse.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func stamp() -> String { formatter.string(from: Date()) }

    static func append(_ line: String) {
        queue.async {
            let url = fileURL
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)

            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }

            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }

            // 너무 커지면 앞부분을 버리고 다시 시작합니다.
            if let size = try? handle.seekToEnd(), size > maxBytes {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
