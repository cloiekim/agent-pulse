// Agent Pulse — 격리 컨텍스트(ISOLATED world) 다리
//
// inject.js 는 페이지 안에 있어서 `chrome.*` API 를 못 씁니다.
// 이 파일은 확장 컨텍스트에 있어서 `chrome.runtime` 은 쓸 수 있지만
// 페이지의 `fetch` 는 못 건드립니다.
//
// 그래서 둘로 나누고, window.postMessage 로 이어줍니다.

(() => {
  'use strict';

  window.addEventListener('message', (event) => {
    // 다른 origin 이나 다른 확장이 보낸 메시지는 버립니다.
    if (event.source !== window) return;
    if (event.origin !== location.origin) return;

    const data = event.data;
    if (!data) return;

    // 사용량 탐색 결과 — 팝업에서 보여주기 위한 것.
    if (data.source === 'agent-pulse-org' && data.orgId) {
      try { chrome.runtime.sendMessage({ type: 'org', orgId: data.orgId }); } catch { /* 무시 */ }
      return;
    }

    if (data.source === 'agent-pulse-usage' && data.payload) {
      try {
        chrome.runtime.sendMessage({ type: 'usage', payload: data.payload });
      } catch { /* 확장이 갱신 중이면 무시 */ }
      return;
    }

    if (data.source === 'agent-pulse-discovery' && data.finding) {
      try {
        chrome.runtime.sendMessage({ type: 'usage-discovery', finding: data.finding });
      } catch { /* 확장 리로드 중이면 무시 */ }
      return;
    }

    if (data.source !== 'agent-pulse' || !data.payload) return;

    // 서비스 워커가 잠들어 있어도 sendMessage 가 깨웁니다.
    try {
      chrome.runtime.sendMessage({ type: 'agent-event', payload: data.payload });
    } catch {
      // 확장이 리로드되면 컨텍스트가 무효화됩니다. 조용히 넘어갑니다.
    }
  });
})();
