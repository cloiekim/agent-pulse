import Foundation
import Network

/// 127.0.0.1 에서만 듣는 아주 작은 HTTP 서버.
///
/// 왜 HTTP 인가:
/// - Claude Code 훅이 `"type": "http"` 를 네이티브로 지원합니다. 중간 스크립트 없이 바로 꽂힙니다.
/// - Codex 는 프로그램을 실행하므로 curl 한 줄짜리 셸 스크립트면 됩니다.
/// - 크롬 확장은 fetch() 로 바로 쏩니다. Native Messaging 설정이 필요 없습니다.
///
/// 세 표면이 전부 같은 문 하나로 들어오므로, 붙일 게 늘어나도
/// 서버 코드는 그대로입니다.
///
/// 보안:
/// - 기본은 루프백(127.0.0.1)에만 바인딩합니다. 외부에서 접근 불가입니다.
/// - 모든 요청에 대해 로컬 파일(0600)에 저장된 토큰을 검사합니다.
///
/// ## 원격 에이전트 지원
///
/// 처음엔 "에이전트와 앱이 같은 Mac 에 있다" 고 가정했습니다. **틀렸습니다.**
/// 첫 테스터가 맥북에어에서 맥북프로로 SSH 해서 Claude Code 를 돌리고 있었는데,
/// 훅은 프로의 로컬호스트로 쏘고 앱은 에어에 있어서 **아무것도 안 보였습니다.**
/// 원격 개발(SSH·devcontainer·클라우드 VM)은 개발자들 사이에서 드물지 않습니다.
///
/// 그래서 설정에서 켜면 LAN 에서도 받습니다. 켤 때만 열리고, 토큰 검사는
/// 그대로라 아는 사람만 들어올 수 있습니다.
final class LocalEventServer {

    static let defaultPort: UInt16 = 8787

    private var listener: NWListener?
    private let port: UInt16
    private let token: String
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let onUsage: @Sendable (UsageQuota) -> Void

    init(port: UInt16 = LocalEventServer.defaultPort,
         token: String = LocalEventServer.loadOrCreateToken(),
         onEvent: @escaping @Sendable (AgentEvent) -> Void,
         onUsage: @escaping @Sendable (UsageQuota) -> Void = { _ in }) {
        self.port = port
        self.token = token
        self.onEvent = onEvent
        self.onUsage = onUsage
    }

    // MARK: - 확장 페어링
    //
    // ⚠️ 왜 필요한가:
    // 예전엔 사용자가 터미널로 `cat ~/.agent-pulse/token` 해서 복사한 뒤
    // 확장에 붙여넣어야 했습니다. 일반 사용자에겐 그냥 벽입니다.
    // 실제로 첫 테스터가 그 화면에서 멈췄습니다 (zsh 의 `%` 표시까지 겹쳐서).
    //
    // 대신 사용자가 앱에서 버튼을 누르면 **60초 동안만** 토큰을 내주는 창을 엽니다.
    // 그 사이 확장이 로컬호스트로 물어보면 받아갑니다.
    //
    // 안전 장치 셋:
    //   · 사용자가 직접 눌러야만 열립니다 (스스로 열리지 않음)
    //   · 60초 뒤 자동으로 닫힙니다
    //   · **루프백 요청만** 받습니다. 원격 허용을 켜뒀어도 LAN 에서는 못 가져갑니다.

    private static let pairingWindow: TimeInterval = 60
    nonisolated(unsafe) private static var pairingUntil = Date.distantPast

    static func beginPairing() {
        pairingUntil = Date().addingTimeInterval(pairingWindow)
        apLog("확장 페어링 창 열림 (\(Int(pairingWindow))초)")
    }

    static var isPairing: Bool { pairingUntil > Date() }

    /// LAN 에서도 받을지. 기본은 꺼짐입니다.
    static var allowsRemote: Bool {
        UserDefaults.standard.bool(forKey: "allowRemoteAgents")
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        if Self.allowsRemote {
            // 모든 인터페이스에서 받습니다. 토큰이 유일한 문지기가 됩니다.
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.any),
                                                     port: NWEndpoint.Port(rawValue: port)!)
        } else {
            // 루프백에만 바인딩. 외부에서는 접근 자체가 불가능합니다.
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: NWEndpoint.Port(rawValue: port)!)
        }

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                apLog("listener 실패: \(error)")
            }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener

        apLog("\(Self.allowsRemote ? "0.0.0.0" : "127.0.0.1"):\(port) 에서 수신 대기 중" + (Self.allowsRemote ? " (원격 허용)" : ""))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - 연결 처리

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receive(on: conn, buffer: Data())
    }

    /// 이 연결이 이 Mac 안에서 온 것인가.
    /// 페어링(토큰 발급)은 여기서만 허용합니다.
    private static func isLoopback(_ conn: NWConnection) -> Bool {
        guard case let .hostPort(host, _)? = conn.currentPath?.remoteEndpoint else {
            // 알 수 없으면 안전한 쪽으로 — 거부합니다.
            return false
        }
        switch host {
        case .ipv4(let v4): return v4.isLoopback
        case .ipv6(let v6): return v6.isLoopback
        default:            return false
        }
    }

    /// TCP 는 요청을 여러 조각으로 쪼개 보낼 수 있습니다.
    /// 헤더의 Content-Length 만큼 본문이 다 모일 때까지 계속 읽습니다.
    /// (한 번만 읽으면 큰 페이로드에서 JSON 이 잘려 이벤트가 조용히 유실됩니다.)
    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { conn.cancel(); return }

            var buffer = buffer
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }

            if error != nil {
                conn.cancel()
                return
            }

            // 요청이 아직 다 안 왔고 연결도 안 끊겼으면 더 읽습니다.
            if !isComplete, !Self.isRequestComplete(buffer), buffer.count < 1_000_000 {
                self.receive(on: conn, buffer: buffer)
                return
            }

            let response = self.process(request: buffer,
                                        isLoopback: Self.isLoopback(conn))
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    /// 헤더가 끝났고, Content-Length 만큼 본문이 도착했는지.
    private static func isRequestComplete(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return false }

        let head = String(text[..<headerEnd.lowerBound])
        let body = String(text[headerEnd.upperBound...])

        let declared = head
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }

        guard let declared else { return true }   // 본문 없는 요청
        return body.utf8.count >= declared
    }

    /// 아주 좁은 범위의 HTTP 만 지원합니다.
    /// 우리가 직접 쏘는 요청만 받으면 되므로 완전한 HTTP 구현은 필요 없습니다.
    private func process(request: Data, isLoopback: Bool) -> Data {
        guard let text = String(data: request, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else {
            return Self.reply(status: "400 Bad Request")
        }

        let head = text[..<headerEnd.lowerBound]
        let body = String(text[headerEnd.upperBound...])
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)

        guard let requestLine = lines.first else { return Self.reply(status: "400 Bad Request") }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "POST" else {
            return Self.reply(status: "405 Method Not Allowed")
        }
        let path = String(parts[1])

        // 페어링 요청은 토큰 없이 받습니다 — 토큰을 받으러 오는 거니까요.
        // 대신 창이 열려 있어야 하고, 루프백에서만 가능합니다.
        if path == "/pair" {
            guard Self.isPairing else {
                return Self.reply(status: "403 Forbidden",
                                  body: #"{"error":"pairing window closed"}"#)
            }
            guard isLoopback else {
                apLog("페어링 거부: 루프백이 아님")
                return Self.reply(status: "403 Forbidden",
                                  body: #"{"error":"loopback only"}"#)
            }
            ConnectionStatus.markBrowserSeen()
            apLog("확장 페어링 성공")
            let escaped = token.replacingOccurrences(of: "\"", with: "")
            let lang = AppSettings.shared.language == .korean ? "ko" : "en"
            return Self.reply(status: "200 OK",
                              body: "{\"token\":\"\(escaped)\",\"lang\":\"\(lang)\"}")
        }

        // 토큰 검사 — 같은 머신의 다른 프로세스가 임의로 이벤트를 넣지 못하게.
        let authorized = lines.contains { line in
            let lowered = line.lowercased()
            guard lowered.hasPrefix("x-agent-pulse-token:") else { return false }
            let value = line.dropFirst("x-agent-pulse-token:".count)
                .trimmingCharacters(in: .whitespaces)
            return value == token
        }
        guard authorized else { return Self.reply(status: "401 Unauthorized") }

        // ⚠️ 확장이 **말을 걸어온 것만으로** 연결됐다고 봅니다.
        //
        //    예전엔 claude.ai / chatgpt.com 에서 실제 세션 이벤트가 와야
        //    연결됐다고 표시했습니다. 그런데 확장을 막 설치한 사람은 보통
        //    그 사이트에 돌고 있는 작업이 없습니다. **제대로 설치했는데
        //    앱은 "연결 안 됨" 이라고 말하는** 상황이 됩니다.
        //    실제로 첫 테스터가 그걸 겪었습니다.
        //
        //    토큰이 맞는 요청이 왔다는 건 설치·페어링이 다 됐다는 뜻입니다.
        //    그거면 충분합니다.
        if path.hasPrefix("/hook/browser") || path == "/hook/usage"
            || path == "/ping" || path == "/hook/ping" {
            ConnectionStatus.markBrowserSeen()
        }

        // 확장이 5분마다 보내는 살아있음 신호. 시각만 갱신하고 끝냅니다.
        // 이게 있어야 확장이 사라진 걸 앱이 알아챌 수 있습니다.
        if path == "/hook/ping" {
            return Self.reply(status: "200 OK", body: #"{"ok":true}"#)
        }

        // 확장의 "연결 확인" 버튼용. 본문이 없어도 200 을 돌려줍니다.
        if path == "/ping" {
            // ⚠️ 언어를 같이 알려줍니다.
            //    확장은 자기 힘으로 앱 설정을 알 수 없어서 한국어가 박혀
            //    있었습니다. 앱을 영어로 써도 팝업만 한국어로 나왔습니다.
            //    크롬 로케일을 쓰면 안 됩니다 — 사용자가 고른 건 **앱 설정**입니다.
            let lang = AppSettings.shared.language == .korean ? "ko" : "en"
            return Self.reply(status: "200 OK", body: "{\"ok\":true,\"lang\":\"\(lang)\"}")
        }

        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return Self.reply(status: "400 Bad Request")
        }

        // 사용량은 세션 이벤트와 성격이 달라 따로 받습니다.
        if path == "/hook/usage" {
            let parsed = EventMapper.usageQuotas(from: json)
            apLog("확장에서 사용량 수신: \(parsed.count)개 — \(parsed.map(\.label).joined(separator: ", "))")
            for quota in parsed { onUsage(quota) }
            return Self.reply(status: "200 OK", body: #"{"ok":true}"#)
        }

        let event: AgentEvent?
        switch path {
        case "/hook/claude":  event = EventMapper.fromClaudeCodeHook(json)
        case "/hook/codex":   event = EventMapper.fromCodexNotify(json)
        case "/hook/browser": event = EventMapper.fromBrowserExtension(json)
        case "/hook/antigravity": event = EventMapper.fromAntigravityHook(json)
        default:              return Self.reply(status: "404 Not Found")
        }

        if let event { onEvent(event) }

        // 훅은 절대 블로킹하면 안 됩니다. 항상 즉시 200 을 돌려줍니다.
        return Self.reply(status: "200 OK", body: #"{"ok":true}"#)
    }

    private static func reply(status: String, body: String = "") -> Data {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        return Data(header.utf8) + payload
    }

    // MARK: - 토큰

    /// 훅 스크립트와 크롬 확장이 읽어갈 수 있도록 파일에 둡니다. 권한 0600.
    static var tokenPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-pulse/token")
    }

    static func loadOrCreateToken() -> String {
        let path = tokenPath
        if let existing = try? String(contentsOf: path, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let token = UUID().uuidString
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // ⚠️ 마지막에 개행을 넣습니다.
        //    없으면 `cat` 했을 때 zsh 가 "줄바꿈 없음" 표시로 `%` 를 붙여서,
        //    토큰 끝에 `%` 가 있는 것처럼 보입니다. 실제로 테스터가 그걸 보고
        //    "토큰 뒤에 % 가 오면 안 되는데" 라고 물었습니다.
        //    읽을 때 어차피 공백을 떼므로 개행이 있어도 무해합니다.
        try? (token + "\n").write(to: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: path.path)
        return token
    }
}
