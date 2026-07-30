// Agent Pulse — 팝업
//
// 하는 일: 토큰 저장, 켜고 끄기, 연결 확인, 최근 이벤트 표시.

const $ = (id) => document.getElementById(id);

const setStatus = (state, text) => {
  const dot = $('dot');
  dot.className = 'dot' + (state === 'ok' ? ' ok' : state === 'bad' ? ' bad' : '');
  $('statusText').textContent = text;
};

const say = (text, kind) => {
  const el = $('message');
  el.textContent = text;
  el.className = kind || '';
};

const relative = (ms) => {
  if (!ms) return '—';
  const s = Math.round((Date.now() - ms) / 1000);
  if (s < 60) return `${s}초 전`;
  if (s < 3600) return `${Math.round(s / 60)}분 전`;
  return `${Math.round(s / 3600)}시간 전`;
};

const ping = () => {
  chrome.runtime.sendMessage({ type: 'ping-app' }, (res) => {
    if (!res) { setStatus('bad', '오류'); return; }
    if (res.ok) {
      setStatus('ok', '연결됨');
      say('앱과 통신됩니다.', 'ok');
    } else if (res.reason === 'bad-token') {
      setStatus('bad', '토큰 불일치');
      say('토큰이 맞지 않습니다. 터미널에서 다시 복사해주세요.', 'bad');
    } else {
      setStatus('bad', '앱 없음');
      say('Agent Pulse 앱이 떠 있는지 확인해주세요.', 'bad');
    }
  });
};

const load = async () => {
  const { token = '', enabled = true, lastEvent } =
    await chrome.storage.local.get(['token', 'enabled', 'lastEvent']);

  $('token').value = token;
  $('enabled').checked = enabled;

  if (lastEvent) {
    const target = lastEvent.site === 'claude.ai' ? 'lastClaude' : 'lastGpt';
    $(target).textContent = `${lastEvent.state} · ${relative(lastEvent.at)}`;
  }

  if (!token) {
    setStatus('bad', '토큰 필요');
    say('아래에 토큰을 붙여넣어 주세요.');
  } else {
    ping();
  }
};

// 토큰은 입력하는 즉시 저장합니다 (저장 버튼을 따로 두면 잊어버립니다).
$('token').addEventListener('input', async (e) => {
  const token = e.target.value.trim();
  await chrome.storage.local.set({ token });
  if (token) ping();
});

$('enabled').addEventListener('change', async (e) => {
  await chrome.storage.local.set({ enabled: e.target.checked });
  say(e.target.checked ? '감시를 켰습니다.' : '감시를 껐습니다.');
});

$('test').addEventListener('click', () => {
  say('확인 중…');
  ping();
});

/// 사용량 탐색 결과 렌더링.
/// 한도 정보가 **어떤 모양으로** 오는지 확인하는 게 목적이라,
/// 경로와 값을 있는 그대로 보여줍니다.
const renderFindings = async () => {
  const { discoveries = [] } = await chrome.storage.local.get('discoveries');
  const box = $('discoverBox');
  const list = $('findings');

  // ⚠️ 값이 없는 항목은 보여주지 않습니다.
  //
  //    처음엔 이름에 limit/usage 가 들어간 필드를 전부 나열했는데,
  //    ChatGPT 는 `project_file_limits: null` 같은 걸 수십 개 돌려줍니다.
  //    화면이 null 로 가득 차서 **뭔가 고장난 것처럼 보입니다.**
  //    실제로 첫 테스터 화면이 그랬습니다.
  //
  //    쓸모 있는 건 숫자입니다. 나머지는 잡음이라 버립니다.
  const useful = discoveries
    .map((f) => ({
      ...f,
      // ⚠️ 숫자만 남기면 안 됩니다.
      //    한도 정보는 `2026-07-29T21:00:00Z` 같은 **시각**으로 오기도 하고,
      //    헤더 값은 대개 문자열입니다. 숫자만 통과시키면 정작 찾던 걸 버립니다.
      //    걸러야 할 건 값이 아예 없는 것(null)뿐입니다.
      fields: f.fields.filter((x) =>
        x.value !== null && x.value !== undefined && x.value !== '' && x.value !== 'null'),
    }))
    .filter((f) => f.fields.length);

  if (!useful.length) { box.hidden = true; return; }
  box.hidden = false;

  list.innerHTML = useful.map((f) => `
    <div class="finding">
      <div class="src">${f.source}</div>
      ${f.fields.map((x) => `
        <div class="field"><b>${x.path}</b><i>${String(x.value).slice(0, 40)}</i></div>
      `).join('')}
    </div>
  `).join('');
};

$('copyFindings').addEventListener('click', async () => {
  const { discoveries = [] } = await chrome.storage.local.get('discoveries');
  await navigator.clipboard.writeText(JSON.stringify(discoveries, null, 2));
  say('복사했습니다. 대화에 붙여넣으세요.', 'ok');
});

load();
renderFindings();


// ── 자동 연결 ────────────────────────────────────────────────
//
// 앱에서 "크롬 확장 연결" 을 누르면 60초 동안 토큰을 내주는 창이 열립니다.
// 그 사이 여기서 받아오면 사용자는 아무것도 복사하지 않아도 됩니다.
$('pair')?.addEventListener('click', () => {
  const msg = $('message');
  msg.textContent = '앱에 물어보는 중…';
  msg.className = '';

  chrome.runtime.sendMessage({ type: 'auto-pair' }, (res) => {
    if (res?.ok) {
      const input = $('token');
      if (input) input.value = res.token;
      msg.textContent = '연결됐습니다.';
      msg.className = 'ok';
      ping();
    } else if (res?.reason === 'window-closed') {
      msg.textContent = '앱에서 "크롬 확장 연결" 을 먼저 눌러주세요 (60초 안에).';
      msg.className = 'warn';
    } else {
      msg.textContent = '앱을 찾지 못했습니다. Agent Pulse 가 실행 중인지 확인해주세요.';
      msg.className = 'warn';
    }
  });
});
