// Agent Pulse — 서비스 워커
//
// 하는 일은 하나: 페이지에서 올라온 이벤트를 로컬 앱으로 전달.
//
// 이 확장은 **밖으로 나가는 통신이 전혀 없습니다.** 목적지는 127.0.0.1 뿐이고,
// 대화 내용은 절대 읽지도 보내지도 않습니다 — 상태와 제목만 다룹니다.

const DEFAULTS = {
  port: 8787,
  token: '',
  enabled: true,
};

/// 같은 상태를 반복해서 보내지 않기 위한 기억.
/// (스트림 하나에 generating 이 여러 번 뜰 수 있습니다.)
const lastState = new Map();

const settings = async () => {
  const stored = await chrome.storage.local.get(DEFAULTS);
  return { ...DEFAULTS, ...stored };
};

const setBadge = (ok) => {
  chrome.action.setBadgeText({ text: ok ? '' : '!' });
  chrome.action.setBadgeBackgroundColor({ color: ok ? '#0CA30C' : '#D03B3B' });
};

const send = async (payload) => {
  const { port, token, enabled } = await settings();
  if (!enabled) return { ok: false, reason: 'disabled' };
  if (!token) {
    setBadge(false);
    return { ok: false, reason: 'no-token' };
  }

  const key = `${payload.site}:${payload.conversationId}`;
  if (lastState.get(key) === payload.state) {
    return { ok: true, reason: 'duplicate' };
  }

  try {
    const res = await fetch(`http://127.0.0.1:${port}/hook/browser`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Agent-Pulse-Token': token,
      },
      body: JSON.stringify({
        site: payload.site,
        conversationId: payload.conversationId,
        state: payload.state,
        title: payload.title,
        detail: payload.detail,
        url: payload.url,
      }),
    });

    const ok = res.ok;
    setBadge(ok);
    if (ok) {
      lastState.set(key, payload.state);
      await chrome.storage.local.set({
        lastEvent: { ...payload, at: Date.now() },
      });
    }
    return { ok, status: res.status };
  } catch (e) {
    // 앱이 안 떠 있으면 여기로 옵니다. 조용히 실패하고 배지만 바꿉니다.
    setBadge(false);
    return { ok: false, reason: 'unreachable' };
  }
};

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  // 사용량 탐색 결과를 쌓아둡니다. 팝업이 읽어갑니다.
  if (message?.type === 'usage-discovery') {
    chrome.storage.local.get({ discoveries: [] }).then(({ discoveries }) => {
      const key = (f) => f.source + '|' + f.fields.map((x) => x.path).join(',');
      const existing = new Set(discoveries.map(key));
      if (!existing.has(key(message.finding))) {
        discoveries.unshift(message.finding);
        chrome.storage.local.set({ discoveries: discoveries.slice(0, 20) });
      }
    });
    return false;
  }

  if (message?.type === 'agent-event') {
    send(message.payload).then(sendResponse);
    return true; // 비동기 응답
  }

  // 앱의 페어링 창이 열려 있으면 토큰을 직접 받아옵니다.
  //
  // ⚠️ 예전엔 사용자가 터미널에서 토큰을 복사해 붙여넣어야 했습니다.
  //    일반 사용자에겐 벽이고, 실제로 첫 테스터가 거기서 멈췄습니다.
  if (message?.type === 'auto-pair') {
    (async () => {
      const { port } = await settings();
      try {
        const res = await fetch(`http://127.0.0.1:${port}/pair`, { method: 'POST' });
        if (!res.ok) {
          sendResponse({ ok: false, reason: 'window-closed' });
          return;
        }
        const { token } = await res.json();
        await chrome.storage.local.set({ token });
        sendResponse({ ok: true, token });
      } catch {
        sendResponse({ ok: false, reason: 'no-app' });
      }
    })();
    return true;
  }

  if (message?.type === 'ping-app') {
    // 팝업의 "연결 확인" 버튼용.
    (async () => {
      const { port, token } = await settings();
      try {
        const res = await fetch(`http://127.0.0.1:${port}/hook/browser`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Agent-Pulse-Token': token,
          },
          // state 를 안 넣으면 앱이 무시합니다 — 부작용 없는 확인용 요청.
          body: JSON.stringify({ site: 'claude.ai', conversationId: 'ping' }),
        });
        setBadge(res.status !== 401);
        sendResponse({
          ok: res.status !== 401,
          status: res.status,
          reason: res.status === 401 ? 'bad-token' : 'connected',
        });
      } catch {
        setBadge(false);
        sendResponse({ ok: false, reason: 'unreachable' });
      }
    })();
    return true;
  }
});
