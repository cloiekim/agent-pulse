import Foundation

/// 터미널 세션의 제목을 트랜스크립트 첫 프롬프트에서 만듭니다.
///
/// ⚠️ 왜 필요한가:
/// 데스크톱 앱 세션은 제목이 있지만 **터미널 세션은 없습니다.**
/// Claude Code CLI 는 대화에 이름을 안 붙이거든요.
/// 그래서 작업 폴더명으로 떨어지는데, 홈 디렉터리에서 여러 개 띄우면
/// 전부 `~` 로 똑같아져서 **어느 게 어느 건지 구분이 안 됩니다.**
/// 실제로 목록에 같은 이름이 열 개 넘게 쌓인 걸 봤습니다.
///
/// 훅이 `transcript_path` 를 같이 보내주므로, 거기서 사용자가 처음 친 말을
/// 꺼내 제목으로 씁니다. `"Firebase 연동 좀 해줘"` 가 `~` 보다 훨씬 낫습니다.
enum TranscriptTitles {

    /// 세션당 한 번만 읽습니다. 훅은 초당 여러 번 올 수 있습니다.
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// 제목으로 쓸 길이. 너무 길면 어차피 잘립니다.
    private static let maxLength = 60

    static func title(sessionID: String, transcriptPath: String?) -> String? {
        lock.lock()
        if let cached = cache[sessionID] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()

        let found = read(transcriptPath) ?? ""
        // 진단용 — 제목이 폴더명으로 떨어지는 이유를 알아야 고칠 수 있습니다.
        if found.isEmpty {
            apLog("트랜스크립트 제목 못 찾음: path=\(transcriptPath ?? "(없음)")")
        }

        lock.lock()
        cache[sessionID] = found      // 빈 문자열도 저장 — 매번 다시 읽지 않도록
        lock.unlock()

        return found.isEmpty ? nil : found
    }

    // MARK: - 읽기

    private static func read(_ path: String?) -> String? {
        guard let path, !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        // 첫 사용자 메시지는 파일 맨 앞에 있습니다. 통째로 읽을 이유가 없습니다.
        guard let head = try? handle.read(upToCount: 256 * 1024),
              let text = String(data: head, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  row["type"] as? String == "user",
                  let message = row["message"] as? [String: Any]
            else { continue }

            guard let prompt = extractText(from: message["content"]) else { continue }
            guard let cleaned = clean(prompt) else { continue }
            return cleaned
        }
        return nil
    }

    /// content 는 문자열이거나 블록 배열입니다.
    private static func extractText(from content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks where block["type"] as? String == "text" {
            if let text = block["text"] as? String { return text }
        }
        return nil
    }

    /// 제목으로 쓸 수 없는 것들을 걸러냅니다.
    ///
    /// 첫 메시지가 항상 사람이 친 말은 아닙니다 — 슬래시 명령, 시스템 안내,
    /// 붙여넣은 파일 내용일 수 있습니다. 그런 건 제목이 되면 안 됩니다.
    private static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // `<command-name>`, `<system-reminder>` 같은 태그로 시작하면 사람 말이 아닙니다.
        if text.hasPrefix("<") { return nil }
        // 슬래시 명령도 제목으로는 의미가 없습니다.
        if text.hasPrefix("/") { return nil }

        // 첫 줄만 씁니다. 여러 줄을 이어붙이면 읽기 어렵습니다.
        if let firstLine = text.split(separator: "\n").first {
            text = String(firstLine).trimmingCharacters(in: .whitespaces)
        }
        guard text.count >= 2 else { return nil }

        if text.count > maxLength {
            text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    /// 세션이 끝나면 캐시에서 뺍니다.
    static func forget(sessionID: String) {
        lock.lock(); cache[sessionID] = nil; lock.unlock()
    }
}
