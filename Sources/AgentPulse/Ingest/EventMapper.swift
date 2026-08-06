import Foundation

/// 각 표면의 원본 신호를 `AgentEvent` 하나로 변환합니다.
///
/// 새 에이전트를 붙일 때 손대는 유일한 파일입니다.
enum EventMapper {

    /// 매퍼는 언어 설정을 모르므로 영어 원문만 담아둡니다.
    /// 번역은 화면에서 합니다.
    private static func loc0(_ s: String) -> String { s }


    // MARK: - Claude Code 훅

    /// Claude Code 는 `"type": "http"` 훅을 네이티브로 지원합니다.
    /// 페이로드 공통 필드: session_id, transcript_path, cwd, hook_event_name, permission_mode
    ///
    /// ⚠️ 중요한 한계 (claude-code #13024):
    /// `Notification` 훅의 `idle_prompt` 는 **60초 이상 idle + 터미널 비포커스**
    /// 일 때만 발화합니다. 즉 "지금 승인 대기 중"을 제때 못 잡습니다.
    /// 그래서 `PreToolUse` 를 승인 대기의 **선행 신호**로 함께 씁니다 —
    /// 도구가 호출됐는데 `PostToolUse` 가 안 오면 승인 프롬프트가 떠 있는 것입니다.
    /// (이 상관 로직은 `PendingToolTracker` 가 담당합니다.)
    static func fromClaudeCodeHook(_ json: [String: Any]) -> AgentEvent? {
        guard let sessionID = json["session_id"] as? String,
              let hookName = json["hook_event_name"] as? String else { return nil }

        let cwd = json["cwd"] as? String
        let toolName = json["tool_name"] as? String

        let state: SessionState
        var detail: String?

        switch hookName {
        case "SessionStart":
            state = .idle

        case "UserPromptSubmit":
            state = .running

        case "PreToolUse":
            // 아직 승인인지 자동 통과인지 모릅니다. running 으로 두고,
            // PendingToolTracker 가 타임아웃 내에 PostToolUse 를 못 보면
            // needsApproval 로 승격시킵니다.
            state = .running
            detail = toolName.map { tool in
                if let input = json["tool_input"] as? [String: Any],
                   let cmd = input["command"] as? String {
                    return "\(tool): \(cmd.prefix(48))"
                }
                return tool
            }

        case "PostToolUse", "PostToolUseFailure":
            state = .running
            detail = toolName

        case "PermissionRequest":
            // 있으면 가장 정확한 신호. 훅 버전에 따라 없을 수 있습니다.
            state = .needsApproval
            detail = toolName

        case "Notification":
            // ⚠️ 분류가 틀리면 엉뚱한 알림이 나갑니다. 원문을 남겨서 확인 가능하게.
            apLog("Notification 훅: type=\(json["notification_type"] ?? "-") message=\(json["message"] ?? "-")")
            switch json["notification_type"] as? String {
            case "permission_prompt": state = .needsApproval
            case "idle_prompt":       state = .waitingInput
            default:                  state = .waitingInput
            }
            detail = toolName

        case "Stop":
            state = .completed

        case "StopFailure":
            state = .failed
            // ⚠️ 예전엔 "API 오류로 턴 종료" 라는 **우리가 지어낸 문구**만 썼습니다.
            //    실패한 행에서 제일 중요한 건 "왜" 인데, 그걸 버리고 있었습니다.
            //    훅이 실어 보내는 이름이 버전마다 달라서 후보를 여러 개 봅니다.
            detail = ["error", "error_message", "message", "reason", "detail"]
                .compactMap { json[$0] as? String }
                .first { !$0.isEmpty }
                ?? loc0("turn ended with an API error")

        case "SessionEnd":
            TranscriptTitles.forget(sessionID: sessionID)
            state = .idle

        default:
            return nil
        }

        // 데스크톱 앱에서 시작한 세션이면 사람이 읽는 제목이 있습니다.
        // 훅은 제목을 안 주므로, 없으면 폴더명으로 떨어집니다.
        // ⚠️ 제목을 쓰기 전에 **같은 프로젝트인지 확인**합니다.
        //    세션 ID 만 믿으면 엉뚱한 대화의 제목이 붙습니다.
        //    작업 폴더가 다르면 같은 세션일 수 없으므로 그냥 폴더명으로 떨어집니다.
        let desktop = ClaudeDesktopSessions.lookup(cliSessionId: sessionID)
        // 진단: 제목이 폴더명이나 첫 프롬프트로 떨어질 때 왜인지 알아야 합니다.
        if desktop == nil, hookName == "UserPromptSubmit" {
            apLog("데스크톱 세션 못 찾음: id=\(sessionID.prefix(8))… (색인 \(ClaudeDesktopSessions.indexCount)개)")
        }

        // ⚠️ 폴더 검증은 **어긋날 때만** 거부합니다.
        //
        //    처음엔 "폴더가 같아야 제목을 쓴다" 로 만들었는데 너무 빡빡했습니다.
        //    한쪽에 cwd 가 없기만 해도 거부해서, **맞는 제목을 버리고** 트랜스크립트
        //    첫 프롬프트로 떨어졌습니다.
        //    (데스크톱 앱엔 `Set up Firebase Firestore integration` 인데
        //     우리는 `내 firebase - google analytics…` 를 보여줬습니다.)
        //
        //    세션 ID 는 이미 충분히 강한 키입니다. 폴더는 **명백히 다를 때만**
        //    반증으로 씁니다 — 있는 정보끼리 부딪힐 때만요.
        let sameProject: Bool = {
            guard let entry = desktop else { return false }
            guard let a = entry.cwd, let b = cwd else { return true }   // 모르면 믿습니다
            return URL(fileURLWithPath: a).standardizedFileURL
                == URL(fileURLWithPath: b).standardizedFileURL
        }()

        // 제목 우선순위:
        //   1. 데스크톱 앱 세션 제목 (있고, 같은 프로젝트일 때)
        //   2. 터미널 세션이면 트랜스크립트의 첫 프롬프트
        //   3. 그래도 없으면 작업 폴더명
        //
        // 2번이 없으면 홈에서 띄운 세션들이 전부 `~` 로 똑같아집니다.
        let title: String? = {
            if sameProject, let t = desktop?.title, !t.isEmpty { return t }
            if let t = TranscriptTitles.title(sessionID: sessionID,
                                              transcriptPath: json["transcript_path"] as? String) {
                return t
            }
            return AgentSession.projectName(from: cwd)
        }()

        return AgentEvent(
            agent: .claudeCode,
            sessionKey: sessionID,
            toolName: toolName,
            hookName: hookName,
            state: state,
            title: title,
            cwd: cwd,
            detail: detail,
            // 폴더까지 일치해야 데스크톱 앱 세션으로 인정합니다.
            origin: sameProject ? .claudeDesktop : .terminal,
            returnTarget: cwd.map { "agentpulse://terminal?cwd=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" },
            // PendingToolTracker 가 훅 이름으로 분기하므로 여기에 실어 보냅니다.
            raw: ["hook_event_name": hookName]
        )
    }

    /// Antigravity CLI 훅.
    ///
    /// Claude Code 와 훅 이름이 거의 같습니다 — 구글이 같은 어휘를 골랐습니다.
    /// 다만 세션 ID 필드 이름이 `conversationId` 이고,
    /// 작업 폴더는 `workspacePaths` 배열로 옵니다 (여러 폴더를 걸 수 있어서).
    ///
    /// ⚠️ 승인 대기는 **감지하지 못합니다.**
    /// Antigravity 에는 "권한이 필요하다" 는 알림 훅이 없습니다.
    /// `PreToolUse` 가 `ask`/`force_ask` 를 **반환**해서 물어보게 하는 구조라,
    /// 관찰하는 쪽에서는 그 순간을 알 수 없습니다.
    /// 실행 중·완료·실패까지만 확실하게 잡습니다.
    static func fromAntigravityHook(_ json: [String: Any]) -> AgentEvent? {
        guard let hookName = json["hook_event_name"] as? String else { return nil }

        let sessionID = (json["conversationId"] as? String)
            ?? (json["conversation_id"] as? String)
            ?? "antigravity"

        let cwd = (json["cwd"] as? String)
            ?? (json["workspacePaths"] as? [String])?.first

        let toolName = (json["toolName"] as? String) ?? (json["tool_name"] as? String)

        let state: SessionState
        var detail: String? = toolName

        switch hookName {
        case "PreInvocation", "PreToolUse", "PostToolUse":
            state = .running
        case "PostInvocation":
            state = .running
        case "Stop":
            // 오류 정보가 있으면 실패로 봅니다.
            let error = ["error", "errorMessage", "error_message"]
                .compactMap { json[$0] as? String }
                .first { !$0.isEmpty }
            state = error == nil ? .completed : .failed
            detail = error
        default:
            return nil
        }

        let title = TranscriptTitles.title(
            sessionID: sessionID,
            transcriptPath: json["transcriptPath"] as? String
        ) ?? AgentSession.projectName(from: cwd) ?? "Antigravity"

        return AgentEvent(
            agent: .antigravity,
            sessionKey: sessionID,
            toolName: toolName,
            hookName: hookName,
            state: state,
            title: title,
            cwd: cwd,
            detail: detail,
            origin: .terminal,
            returnTarget: cwd.map { "agentpulse://terminal?cwd=\($0)" }
        )
    }

    // MARK: - Codex CLI notify

    /// Codex 는 `~/.codex/config.toml` 의 `notify = [...]` 로 지정한 프로그램을
    /// 실행하고, argv[1] 에 JSON 을 넘깁니다.
    ///
    /// 이벤트 타입 (2026-07 기준 2개):
    /// - `agent-turn-complete` — 턴이 끝나고 입력 대기
    /// - `approval-requested` — 도구 실행 권한 필요
    ///
    /// `scripts/agent-pulse-notify.sh` 가 이 JSON 을 그대로 우리 서버로 전달합니다.
    static func fromCodexNotify(_ json: [String: Any]) -> AgentEvent? {
        let type = (json["type"] as? String) ?? ""
        let cwd = json["cwd"] as? String

        // turn-id 가 없으면 cwd 로 세션을 식별합니다.
        // (Codex 는 Claude Code 만큼 일관된 세션 ID 를 주지 않습니다.)
        let sessionKey = (json["turn-id"] as? String)
            ?? (json["turn_id"] as? String)
            ?? cwd
            ?? "codex-default"

        let state: SessionState
        switch type {
        case "approval-requested":   state = .needsApproval
        case "agent-turn-complete":  state = .completed
        default:                     return nil
        }

        // last-assistant-message 는 개인정보일 수 있으므로 저장하지 않고
        // 길이만 잘라 표시용으로 씁니다. 외부로 절대 전송하지 않습니다.
        let preview = (json["last-assistant-message"] as? String)
            .map { String($0.prefix(60)) }

        return AgentEvent(
            agent: .codex,
            sessionKey: sessionKey,
            state: state,
            title: AgentSession.projectName(from: cwd),
            cwd: cwd,
            detail: state == .needsApproval ? "tool approval" : preview,
            returnTarget: cwd.map { "agentpulse://terminal?cwd=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
        )
    }

    // MARK: - 크롬 확장

    /// 확장이 보내는 형식은 우리가 정합니다. 최소 필드:
    /// { site, conversationId, state, title, url }
    ///
    /// ⚠️ 확장 구현 시 반드시 지킬 것:
    /// DOM 클래스를 감시하지 마세요. 기존 ChatGPT 알림 확장들이 전멸한 이유입니다
    /// (최대 사용자 521명 · 별점 2.7 · 2023년 이후 방치).
    /// 살아남은 구현들은 전부 **네트워크 응답 / SSE 스트림**을 가로챕니다.
    /// `fetch` / `EventSource` 를 감싸서 스트림의 시작·종료를 감지하세요.
    static func fromBrowserExtension(_ json: [String: Any]) -> AgentEvent? {
        guard let site = json["site"] as? String,
              let conversationID = json["conversationId"] as? String,
              let rawState = json["state"] as? String else { return nil }

        let agent: AgentKind
        switch site {
        case "claude.ai":  agent = .claudeWeb
        case "chatgpt.com", "chat.openai.com": agent = .chatgptWeb
        default: return nil
        }

        let state: SessionState
        switch rawState {
        case "generating": state = .running
        case "complete":   state = .completed
        case "error":      state = .failed
        case "needsInput": state = .waitingInput
        case "queued":     state = .queued
        default: return nil
        }

        let url = json["url"] as? String

        return AgentEvent(
            agent: agent,
            sessionKey: conversationID,
            // 확장이 알려주면 그걸 쓰고, 없으면 주소에서 알아냅니다.
            //
            // ⚠️ 확장에만 의존하면 안 됩니다. 확장을 고쳐도 사용자가 크롬에서
            //    수동으로 리로드하기 전까진 옛 코드가 돕니다. 주소는 이미
            //    받고 있으니 여기서 판단하면 그 사이에도 맞게 나옵니다.
            product: (json["product"] as? String) ?? Self.productFromURL(url),
            state: state,
            title: json["title"] as? String,
            detail: json["detail"] as? String,
            origin: .browser,
            returnTarget: url
        )
    }

    /// claude.ai 안의 표면을 주소로 구분합니다.
    /// (`https://claude.ai/design/p/<id>` → `Claude Design`)
    private static func productFromURL(_ raw: String?) -> String? {
        guard let raw, let path = URL(string: raw)?.path else { return nil }
        if path.hasPrefix("/design") { return "Claude Design" }
        if path.hasPrefix("/cowork") { return "Claude Cowork" }
        return nil
    }
}

// MARK: - 사용량

extension EventMapper {

    /// 크롬 확장이 보내온 사용량 정보를 파싱합니다.
    ///
    /// 확장이 보내는 형식 (우리가 정합니다):
    /// ```
    /// { "provider": "claudeWeb",
    ///   "quotas": [
    ///     { "label": "Session", "percent": 0.62, "resetsAt": "2026-07-28T01:45:00Z" },
    ///     { "label": "Weekly",  "used": 38, "unit": "messages" }
    ///   ] }
    /// ```
    ///
    /// `percent` 는 **제공자가 직접 준 값일 때만** 넣어야 합니다.
    /// 우리가 추정한 값을 여기 넣으면 사용자가 그걸 믿고 계획을 세웁니다.
    static func usageQuotas(from json: [String: Any]) -> [UsageQuota] {
        guard let providerRaw = json["provider"] as? String,
              let provider = UsageQuota.Provider(rawValue: providerRaw),
              let rows = json["quotas"] as? [[String: Any]] else { return [] }

        return rows.compactMap { row in
            guard let label = row["label"] as? String else { return nil }

            let measure: UsageQuota.Measure
            if let percent = row["percent"] as? Double {
                measure = .percent(percent)
            } else if let used = row["used"] as? Int {
                measure = .count(used: used, unit: (row["unit"] as? String) ?? "")
            } else {
                return nil
            }

            var resetsAt: Date?
            if let iso = row["resetsAt"] as? String {
                resetsAt = ISO8601DateFormatter().date(from: iso)
            } else if let epoch = row["resetsAtEpoch"] as? Double {
                resetsAt = Date(timeIntervalSince1970: epoch)
            }

            return UsageQuota(provider: provider,
                              label: label,
                              measure: measure,
                              resetsAt: resetsAt)
        }
    }
}
