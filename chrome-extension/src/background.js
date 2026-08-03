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

  // 진짜 사용량을 앱으로 넘깁니다.
  //
  // ⚠️ 상태 이벤트와 **다른 문으로** 보냅니다 (`/hook/usage`).
  //    성격이 달라서입니다 — 상태는 "지금 뭐 하나", 사용량은 "얼마나 남았나".
  //    같이 묶으면 한쪽이 바뀔 때 다른 쪽까지 흔들립니다.
  // 조직 ID 를 기억해둡니다. 탭 없이 사용량을 가져올 때 필요합니다.
  if (message?.type === 'org' && message.orgId) {
    chrome.storage.local.set({ orgId: message.orgId }).then(() => {
      // 방금 알았으니 바로 한 번 가져옵니다. 다음 알람까지 기다릴 이유가 없습니다.
      fetchUsageInBackground();
    });
    return false;
  }

  if (message?.type === 'usage' && message.payload) {
    (async () => {
      const { port, token, enabled } = await settings();
      if (!enabled || !token) return;
      try {
        await fetch(`http://127.0.0.1:${port}/hook/usage`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Agent-Pulse-Token': token,
          },
          body: JSON.stringify(message.payload),
        });
      } catch { /* 앱이 꺼져 있으면 조용히 넘어갑니다 */ }
    })();
    return false;
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


// ── 탭 없이 사용량 가져오기 ──────────────────────────────────
//
// ⚠️ 콘텐츠 스크립트만으로는 부족합니다.
//    claude.ai 탭이 열려 있어야만 돌기 때문에, 탭을 닫아두면 사용량이
//    갱신되지 않습니다. 그런데 탭을 안 열어두는 시간이 훨씬 깁니다.
//
//    서비스 워커는 탭 없이도 돌고, claude.ai 쿠키를 그대로 씁니다.
//    (manifest 의 host_permissions 에 claude.ai 를 넣은 이유입니다.)
//
//    MV3 서비스 워커는 놀고 있으면 잠들기 때문에 `alarms` 로 깨웁니다.
//    `setInterval` 은 잠든 사이 멈춥니다.

const USAGE_ALARM = 'agent-pulse-usage';

// ⚠️ `periodInMinutes` 만 주면 **첫 발화가 10분 뒤**입니다.
//    설치 직후엔 화면이 비어 있는데 10분을 기다려야 하죠.
//    `delayInMinutes` 로 곧바로 한 번 당겨옵니다.
chrome.alarms.create(USAGE_ALARM, { delayInMinutes: 0.2, periodInMinutes: 10 });

// 서비스 워커가 깨어날 때도 한 번. (확장 새로고침·브라우저 시작)
fetchUsageInBackground();

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === USAGE_ALARM) fetchUsageInBackground();
});

// 확장이 깨어날 때 한 번 시도합니다 (브라우저 시작 직후 등).
chrome.runtime.onStartup?.addListener(fetchUsageInBackground);

async function fetchUsageInBackground() {
  const { orgId } = await chrome.storage.local.get('orgId');
  const { port, token, enabled } = await settings();
  if (!orgId || !token || !enabled) return;

  try {
    const res = await fetch(`https://claude.ai/api/organizations/${orgId}/usage`, {
      credentials: 'include',
    });
    // 로그아웃 상태면 401/403 — 조용히 넘어갑니다.
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
    if (!quotas.length) return;

    await fetch(`http://127.0.0.1:${port}/hook/usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Agent-Pulse-Token': token },
      body: JSON.stringify({ provider: 'claudeWeb', quotas }),
    });
  } catch { /* 네트워크·앱 꺼짐 — 다음 알람에 다시 시도합니다 */ }
}
