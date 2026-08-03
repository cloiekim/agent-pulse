// Agent Pulse — 페이지 컨텍스트(MAIN world) 감시자
//
// ⚠️ 이 파일의 설계가 이 확장의 성패를 가릅니다.
//
// 기존 ChatGPT 알림 확장들은 전부 죽었습니다 — 현존 최대가 사용자 521명,
// 별점 2.7, 2023년 이후 방치, 여러 개는 스토어에서 삭제. 이유는 하나입니다:
// 전부 `result-streaming` 같은 **CSS 클래스를 폴링**했고, UI 개편 때마다 깨졌습니다.
//
// 반면 살아남은 것들(Claude Usage Tracker 사용자 10만 명, 별점 4.8)은
// 전부 **네트워크 계층을 가로챕니다.** DOM 은 UI 를 주입할 때만 씁니다.
//
// 그래서 여기서는 `fetch` 와 `EventSource` 만 감싸고, DOM 은 손대지 않습니다.
// 회사가 화면을 아무리 갈아엎어도 응답 스트림의 주소와 모양은 훨씬 천천히 바뀝니다.
//
// MAIN world 에서 돌아야 하는 이유: content script 의 기본 격리 환경(ISOLATED)은
// 자기만의 `fetch` 를 가집니다. 페이지의 `fetch` 를 바꾸려면 페이지 안에 있어야 합니다.

(() => {
  'use strict';

  const SITE = location.hostname.includes('claude.ai') ? 'claude.ai' : 'chatgpt.com';

  /// 응답 생성 요청인지 판별합니다.
  ///
  /// 이 목록이 깨지면 확장이 조용히 멈춥니다. 그래서 넓게 잡고,
  /// 못 알아본 요청은 그냥 무시합니다(오탐보다 미탐이 안전).
  const COMPLETION_PATTERNS = [
    /\/api\/organizations\/[^/]+\/chat_conversations\/[^/]+\/completion/, // claude.ai
    /\/api\/organizations\/[^/]+\/chat_conversations\/[^/]+\/retry_completion/,
    /\/backend-api\/conversation$/,                                       // chatgpt.com
    /\/backend-api\/f\/conversation$/,

    // Claude Design (아티팩트 편집기).
    //
    // ⚠️ 이름이 전혀 다릅니다 — `OmeletteService/Chat` 은 내부 코드명이라
    //    `conversation` 이나 `completion` 같은 단어가 안 들어갑니다.
    //    그래서 주소만 보고는 절대 못 알아냅니다.
    //
    //    `(무시됨)` 로그를 남겨둔 덕에 찾았습니다. 사이트가 새 표면을 만들 때마다
    //    이런 일이 또 있을 테니, 그 로그는 계속 남겨둡니다.
    // ⚠️ 점과 슬래시를 헷갈리지 마세요.
    //    실제 경로는 `/design/anthropic.omelette.api.v1alpha.OmeletteService/Chat` 로,
    //    `v1alpha.OmeletteService` 가 **한 덩어리**입니다 (gRPC-web 방식).
    //    처음엔 그 사이를 슬래시로 기대해서 한 번도 안 걸렸습니다.
    //    버전이 올라가도 되게 느슨하게 잡습니다.
    /\/design\/[^/]*OmeletteService\/Chat/i,
  ];

  const isCompletion = (url) => {
    if (!url) return false;
    try {
      const path = new URL(url, location.origin).pathname;
      return COMPLETION_PATTERNS.some((re) => re.test(path));
    } catch {
      return false;
    }
  };

  /// 대화 ID. 세션을 구분하는 키입니다.
  /// URL 에서 못 뽑으면 탭 단위로 묶습니다.
  const conversationId = () => {
    const m = location.pathname.match(/\/(?:chat|c)\/([0-9a-f-]{16,})/i);
    return m ? m[1] : `tab-${location.pathname}`;
  };

  /// 대화 제목. 문서 제목에서 사이트 이름을 떼어냅니다.
  const conversationTitle = () => {
    const t = (document.title || '').replace(/\s*[-–|]\s*(ChatGPT|Claude).*$/i, '').trim();
    return t || 'Untitled';
  };

  /// claude.ai 안에서도 표면이 여러 개입니다.
  ///
  /// ⚠️ 예전엔 전부 `Claude · tab` 으로만 보냈습니다. 그래서 Design 에서 만든 게
  ///    일반 채팅과 구분이 안 되고, 제목만 봐서는 어디서 온 건지 알 수 없었습니다.
  ///    (`document.title` 이 아티팩트 이름이라 더 헷갈립니다.)
  const productName = () => {
    if (SITE !== 'claude.ai') return null;
    const p = location.pathname;
    if (p.startsWith('/design')) return 'Claude Design';
    if (p.startsWith('/cowork')) return 'Claude Cowork';
    return null;   // 일반 채팅은 기본 이름을 씁니다
  };

  let sequence = 0;

  // ── 무응답 감시견 ────────────────────────────────────────────
  //
  // ⚠️ `generating` 을 쏜 뒤 완료 신호를 못 받으면 **영원히 실행 중**으로 남습니다.
  //    실제로 아무것도 안 하는 새 탭이 1분 넘게 `Running` 으로 떠 있었습니다.
  //
  //    스트림이 비정상 종료되거나, 사용자가 중간에 멈추거나, 탭을 옮기면
  //    끝을 알리는 신호가 안 옵니다. 그럴 때를 대비해 스스로 정리합니다.
  //
  //    "안 끝났는데 끝났다고 하는 것" 보다 "끝났는데 계속 돈다고 하는 것" 이
  //    더 나쁩니다. 후자는 목록을 쓰레기로 채우고 신뢰를 깎습니다.
  const STALL_MS = 90 * 1000;
  let stallTimer = null;

  const clearStall = () => {
    if (stallTimer) { clearTimeout(stallTimer); stallTimer = null; }
  };

  const emit = (state, detail) => {
    clearStall();
    if (state === 'generating') {
      stallTimer = setTimeout(() => {
        console.log('[Agent Pulse] 응답이 끊긴 것으로 보고 정리합니다');
        emit('complete');
      }, STALL_MS);
    }
    console.log('[Agent Pulse] →', state, detail || '');
    window.postMessage({
      source: 'agent-pulse',
      payload: {
        site: SITE,
        conversationId: conversationId(),
        state,                       // generating | complete | error
        title: conversationTitle(),
        product: productName() || undefined,
        detail: detail || undefined,
        url: location.href,
        seq: ++sequence,
      },
    }, location.origin);
  };

  /// 스트림이 끝날 때까지 지켜보다가 complete 를 쏩니다.
  ///
  /// 본문을 `clone()` 으로 읽는 이유: 원본 응답은 페이지가 그대로 쓰게 두어야 합니다.
  /// 새 Response 를 만들어 돌려주면 `res.url` 같은 속성이 사라져서
  /// 사이트가 오작동할 수 있습니다.
  const watchStream = async (response) => {
    try {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let bytes = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value?.length || 0;

        // 이미 스트림을 읽고 있으므로, 한도 이벤트도 공짜로 볼 수 있습니다.
        // (대화 내용은 보지 않습니다 — 한도 키가 있는 줄만 골라냅니다.)
        if (value && window.__agentPulseScanStream) {
          try {
            window.__agentPulseScanStream(decoder.decode(value, { stream: true }));
          } catch { /* 탐색은 절대 본 기능을 방해하면 안 됩니다 */ }
        }
      }
      // 한 바이트도 안 왔으면 정상 완료로 보기 어렵습니다.
      emit(bytes > 0 ? 'complete' : 'error', bytes > 0 ? undefined : 'empty response');
    } catch (e) {
      // 사용자가 중단했거나 연결이 끊긴 경우도 여기로 옵니다.
      emit('error', String(e && e.message ? e.message : e).slice(0, 80));
    }
  };

  // ── fetch 감싸기 ────────────────────────────────────────────────
  const originalFetch = window.fetch;

  window.fetch = function (...args) {
    let url;
    try {
      url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
    } catch { /* ignore */ }

    rememberOrg(url);

    if (!isCompletion(url)) {
      // 패턴이 안 맞았지만 "대화 요청처럼 생긴" 주소는 찍어둡니다.
      // 사이트가 엔드포인트를 바꾸면 여기서 바로 드러납니다.
      if (url && /conversation|completion|chat/i.test(String(url))) {
        console.log('[Agent Pulse] (무시됨) ' + new URL(url, location.origin).pathname);
      }
      return originalFetch.apply(this, args);
    }

    console.log('[Agent Pulse] ▶ generating —', new URL(url, location.origin).pathname);
    emit('generating');

    return originalFetch.apply(this, args).then(
      (response) => {
        if (!response.ok) {
          emit('error', `HTTP ${response.status}`);
          return response;
        }
        if (response.body) {
          // clone 은 원본을 건드리지 않습니다.
          watchStream(response.clone());
        } else {
          emit('complete');
        }
        return response;
      },
      (error) => {
        emit('error', String(error && error.message ? error.message : error).slice(0, 80));
        throw error;
      }
    );
  };

  // ── EventSource 감싸기 (일부 경로가 씁니다) ──────────────────────
  const OriginalEventSource = window.EventSource;
  if (OriginalEventSource) {
    window.EventSource = function (url, config) {
      const source = new OriginalEventSource(url, config);
      if (isCompletion(url)) {
        emit('generating');
        source.addEventListener('error', () => emit('error', 'stream error'));
        source.addEventListener('done', () => emit('complete'));
      }
      return source;
    };
    window.EventSource.prototype = OriginalEventSource.prototype;
  }


  // ───────────────────────────────────────────────────────────
  // 사용량 탐색 모드
  //
  // 목적: claude.ai / ChatGPT 가 한도 정보를 **어떤 모양으로** 내려주는지
  // 눈으로 확인하는 것. 공개 문서가 없으므로 추측 대신 실물을 봅니다.
  //
  // 확인이 끝나면 DISCOVER 를 false 로 바꾸고 파서를 확정합니다.
  // ───────────────────────────────────────────────────────────
  const DISCOVER = true;

  /// 한도 정보가 있을 법한 주소. 넓게 잡습니다 — 못 보는 것보다 낫습니다.
  const USAGE_URL = /(usage|limits?|rate_limit|subscription|bootstrap|account)/i;
  /// 한도처럼 생긴 키.
  const LIMIT_KEY = /(limit|quota|remaining|resets?_at|reset_at|utilization|allowance|tier)/i;
  /// 한도처럼 생긴 **응답 헤더** 이름.
  /// `anthropic-ratelimit-requests-remaining` 같은 것들입니다.
  const HEADER_KEY = /(ratelimit|rate-limit|x-usage|usage-|quota|retry-after)/i;

  const seenShapes = new Set();

  /// 객체를 훑어 한도처럼 생긴 부분만 골라냅니다.
  /// ⚠️ 대화 내용은 절대 로그에 남기지 않습니다 — 키 이름과 숫자만 봅니다.
  const findLimits = (obj, path = '', out = [], depth = 0) => {
    if (depth > 6 || obj === null || typeof obj !== 'object') return out;
    for (const [k, v] of Object.entries(obj)) {
      const here = path ? path + '.' + k : k;
      if (LIMIT_KEY.test(k)) {
        out.push([here, (v === null || typeof v !== 'object')
          ? v
          : JSON.stringify(v).slice(0, 300)]);
      } else if (typeof v === 'object') {
        findLimits(v, here, out, depth + 1);
      }
    }
    return out;
  };

  // 콘솔뿐 아니라 전역에도 쌓아둡니다.
  // 개발자 도구를 열지 않고도 밖에서 읽어갈 수 있게 하기 위해서입니다.
  window.__agentPulseFindings = window.__agentPulseFindings || [];

  const report = (source, found) => {
    if (!found.length) return;
    const key = source + '|' + found.map(function (x) { return x[0]; }).join(',');
    if (seenShapes.has(key)) return;
    seenShapes.add(key);

    const finding = {
      source: source,
      at: new Date().toISOString(),
      fields: found.map(function (x) { return { path: x[0], value: x[1] }; })
    };
    window.__agentPulseFindings.push(finding);

    // 팝업에서 볼 수 있도록 확장 쪽으로도 보냅니다.
    // (개발자 도구를 열지 않고 확인할 수 있어야 합니다.)
    window.postMessage({ source: 'agent-pulse-discovery', finding: finding }, location.origin);

    console.log(
      '%c[Agent Pulse · 사용량 발견]%c ' + source,
      'background:#0CA30C;color:#fff;padding:2px 6px;border-radius:4px;font-weight:600',
      'color:inherit'
    );
    console.table(found.map(function (x) { return { path: x[0], value: x[1] }; }));
  };

  /// 스트림 청크에서 한도 이벤트를 찾습니다. watchStream 이 호출합니다.
  window.__agentPulseScanStream = function (text) {
    if (!DISCOVER || !text) return;
    for (const line of text.split('\n')) {
      if (line.indexOf('data:') !== 0) continue;
      if (!LIMIT_KEY.test(line)) continue;
      try {
        const json = JSON.parse(line.slice(5).trim());
        report('SSE:' + (json.type || '?'), findLimits(json));
      } catch { /* 잘린 청크는 무시 */ }
    }
  };

  // 사용량 관련 엔드포인트 응답도 훑습니다.
  // (위에서 이미 fetch 를 감쌌으므로 그 위에 한 겹 더 얹습니다.)
  if (DISCOVER) {
    const beforeSniff = window.fetch;
    window.fetch = function (...args) {
      const result = beforeSniff.apply(this, args);
      let url;
      try {
        url = typeof args[0] === 'string' ? args[0] : args[0] && args[0].url;
      } catch { /* ignore */ }

      // ⚠️ 주소 필터를 너무 좁게 잡으면 정작 있는 걸 못 봅니다.
      //    claude.ai 는 엔드포인트 이름에 `usage`/`limit` 이 안 들어가도
      //    한도 정보를 실어 보낼 수 있어서, `/api/` 는 전부 훑습니다.
      const path = url ? String(url) : '';
      const worthChecking = path && (USAGE_URL.test(path) || path.indexOf('/api/') !== -1);

      // ── 진짜 사용량 ──────────────────────────────────────
      //
      // ⚠️ 여기가 유일한 출처입니다.
      //    `/api/organizations/<org>/usage` 가 퍼센트와 리셋 시각을
      //    그대로 내려줍니다:
      //      five_hour.utilization / resets_at
      //      seven_day.utilization / resets_at
      //
      //    로컬 파일(`~/.claude.json`, `stats-cache.json`)을 세 번 뒤졌지만
      //    한도는 어디에도 없었습니다. CLI 는 API 응답에서 받아 쓰고 버립니다.
      //    브라우저만이 이 값을 볼 수 있습니다.
      if (path.indexOf('/usage') !== -1) {
        result.then(function (res) {
          if (!res.ok) return;
          res.clone().json().then(function (u) {
            const quotas = [];
            const add = (key, label) => {
              const v = u && u[key];
              if (!v || typeof v.utilization !== 'number') return;
              quotas.push({
                label: label,
                // 앱은 0~1 로 받습니다. API 는 0~100 으로 줍니다.
                percent: v.utilization / 100,
                resetsAt: v.resets_at || null
              });
            };
            add('five_hour', 'session');
            add('seven_day', 'weekly');
            // ⚠️ 크레딧도 한도입니다.
            //    구독 한도를 넘으면 여기서 차감되고, 이것마저 떨어지면
            //    `You're out of usage credits` 로 **완전히 막힙니다.**
            //    5시간·주간이 여유 있어도 이게 0 이면 아무것도 못 합니다.
            add('extra_usage', 'credits');
            if (!quotas.length) return;

            window.postMessage({
              source: 'agent-pulse-usage',
              payload: { provider: 'claudeWeb', quotas: quotas }
            }, location.origin);

            console.log('%c[Agent Pulse · 사용량]%c ' +
              quotas.map(q => q.label + ' ' + Math.round(q.percent * 100) + '%').join(' · '),
              'background:#2F6FED;color:#fff;padding:2px 6px;border-radius:4px;font-weight:600',
              'color:inherit');
          }).catch(function () {});
        }).catch(function () {});
      }

      if (worthChecking) {
        result.then(function (res) {
          if (!res.ok) return;
          const where = new URL(url, location.origin).pathname;

          // ── 헤더부터 봅니다 ──────────────────────────────────
          //
          // ⚠️ 처음엔 본문만 봤습니다. **큰 실수였습니다.**
          //    Anthropic 은 한도 정보를 `anthropic-ratelimit-*` 같은
          //    **응답 헤더**로 내려주는 경우가 많습니다.
          //    본문만 뒤지면 바로 눈앞에 있는 걸 놓칩니다.
          try {
            const headerHits = [];
            res.headers.forEach(function (value, name) {
              if (HEADER_KEY.test(name)) headerHits.push([name, value]);
            });
            if (headerHits.length) report(where + ' (headers)', headerHits);
          } catch { /* ignore */ }

          // ── 그다음 본문 ─────────────────────────────────────
          const type = res.headers.get('content-type') || '';
          if (type.indexOf('json') === -1) return;
          res.clone().json()
            .then(function (json) {
              report(where, findLimits(json));
            })
            .catch(function () {});
        }).catch(function () {});
      }
      return result;
    };

    console.log(
      '%c[Agent Pulse]%c 사용량 탐색 모드 — claude.ai 에서 아무거나 물어보세요',
      'background:#0CA30C;color:#fff;padding:2px 6px;border-radius:4px;font-weight:600',
      'color:inherit'
    );
  }

  // ── 사용량 주기 갱신 ────────────────────────────────────────
  //
  // ⚠️ 지켜보기만 해서는 부족합니다.
  //    `/usage` 는 페이지가 처음 뜰 때 한 번만 호출됩니다. 그래서 탭을 새로
  //    로드하기 전까지 값이 갱신되지 않고, 앱을 다시 띄우면 아예 사라집니다.
  //    (실제로 "사용량이 없어졌다" 가 나왔습니다.)
  //
  //    그래서 우리가 직접 부릅니다. 5분마다 한 번이면 충분하고,
  //    이미 로그인된 세션이라 추가 권한도 필요 없습니다.
  const ORG_RE = /\/api\/organizations\/([0-9a-f-]{36})\//i;
  let orgId = null;

  const pollUsage = async () => {
    if (!orgId || document.hidden) return;
    try {
      const res = await originalFetch(`/api/organizations/${orgId}/usage`, {
        credentials: 'include'
      });
      if (!res.ok) return;
      const u = await res.json();
      const quotas = [];
      const add = (key, label) => {
        const v = u && u[key];
        if (!v || typeof v.utilization !== 'number') return;
        quotas.push({ label, percent: v.utilization / 100, resetsAt: v.resets_at || null });
      };
      add('five_hour', 'session');
      add('seven_day', 'weekly');
      add('extra_usage', 'credits');
      if (quotas.length) {
        window.postMessage({
          source: 'agent-pulse-usage',
          payload: { provider: 'claudeWeb', quotas }
        }, location.origin);
      }
    } catch { /* 로그아웃 등 — 조용히 넘어갑니다 */ }
  };

  // 조직 ID 는 오가는 요청에서 주워둡니다.
  const rememberOrg = (url) => {
    if (orgId || !url) return;
    const m = ORG_RE.exec(String(url));
    if (m) {
      orgId = m[1];
      // 백그라운드가 탭 없이도 쓸 수 있게 저장해둡니다.
      window.postMessage({ source: 'agent-pulse-org', orgId }, location.origin);
      setTimeout(pollUsage, 2000);
    }
  };

  setInterval(pollUsage, 5 * 60 * 1000);

  // 탭을 닫거나 다른 곳으로 가면 실행 중이던 걸 정리합니다.
  // 안 그러면 닫힌 탭이 목록에 계속 남습니다.
  window.addEventListener('pagehide', () => {
    if (stallTimer) emit('complete');
  });

  console.log('%c[Agent Pulse]%c 감시 시작 — ' + SITE,
              'background:#D97757;color:#fff;padding:2px 6px;border-radius:4px;font-weight:600',
              'color:inherit');
})();
