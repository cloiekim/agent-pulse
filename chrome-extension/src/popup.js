// Agent Pulse — 팝업
//
// 하는 일: 토큰 저장, 켜고 끄기, 연결 확인, 최근 이벤트 표시.

const $ = (id) => document.getElementById(id);

// ── 언어 ─────────────────────────────────────────────────────
//
// ⚠️ 크롬 로케일(`chrome.i18n`)을 쓰면 안 됩니다.
//    사용자가 고른 건 **앱 설정**입니다. 앱을 영어로 써도 크롬이 한국어면
//    팝업만 한국어로 나옵니다. 실제로 그 상태였습니다.
//
//    그래서 앱에게 물어봅니다. `/ping` 과 `/pair` 응답에 `lang` 이 실려 옵니다.
//    앱이 꺼져 있을 때를 위해 마지막 값을 저장해 둡니다 —
//    처음 그릴 때 한국어로 깜빡였다가 영어로 바뀌면 그게 더 거슬립니다.
const STRINGS = {
  en: {
    checking: 'Checking…', pair: 'Connect from the app',
    pairHint: 'In the app&rsquo;s settings, press <b>Connect Chrome extension</b> first',
    manual: 'Enter manually', tokenPlaceholder: 'Find it in the app settings',
    test: 'Test connection',
    error: 'Error', connected: 'Connected', talking: 'Talking to the app.',
    badToken: 'Token mismatch', badTokenMsg: 'That token does not match. Copy it again from the app.',
    noApp: 'App not found', noAppMsg: 'Check that Agent Pulse is running.',
    needToken: 'Token needed', needTokenMsg: 'Paste your token below.',
    watchOn: 'Watching.', watchOff: 'Not watching.',
    asking: 'Asking the app…', paired: 'Connected.',
    pressFirst: 'Press "Connect Chrome extension" in the app first (within 60 seconds).',
    notFound: 'Could not reach the app. Check that Agent Pulse is running.',
    secAgo: (n) => `${n}s ago`, minAgo: (n) => `${n}m ago`, hourAgo: (n) => `${n}h ago`,
  },
  ko: {
    checking: '확인 중…', pair: '앱에서 자동 연결',
    pairHint: '앱 설정에서 <b>크롬 확장 연결</b>을 먼저 누르세요',
    manual: '직접 입력', tokenPlaceholder: '앱 설정에서 확인',
    test: '연결 확인',
    error: '오류', connected: '연결됨', talking: '앱과 통신됩니다.',
    badToken: '토큰 불일치', badTokenMsg: '토큰이 맞지 않습니다. 앱에서 다시 복사해주세요.',
    noApp: '앱 없음', noAppMsg: 'Agent Pulse 앱이 떠 있는지 확인해주세요.',
    needToken: '토큰 필요', needTokenMsg: '아래에 토큰을 붙여넣어 주세요.',
    watchOn: '감시를 켰습니다.', watchOff: '감시를 껐습니다.',
    asking: '앱에 물어보는 중…', paired: '연결됐습니다.',
    pressFirst: '앱에서 "크롬 확장 연결" 을 먼저 눌러주세요 (60초 안에).',
    notFound: '앱을 찾지 못했습니다. Agent Pulse 가 실행 중인지 확인해주세요.',
    secAgo: (n) => `${n}초 전`, minAgo: (n) => `${n}분 전`, hourAgo: (n) => `${n}시간 전`,
  },
};

let LANG = 'en';
const t = (key) => (STRINGS[LANG] || STRINGS.en)[key];

const applyLang = (lang) => {
  if (lang !== 'ko' && lang !== 'en') return;
  LANG = lang;
  chrome.storage.local.set({ lang });
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-html]').forEach((el) => {
    el.innerHTML = t(el.dataset.i18nHtml);
  });
  document.querySelectorAll('[data-i18n-ph]').forEach((el) => {
    el.placeholder = t(el.dataset.i18nPh);
  });
};

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
  if (s < 60) return t('secAgo')(s);
  if (s < 3600) return t('minAgo')(Math.round(s / 60));
  return t('hourAgo')(Math.round(s / 3600));
};

const ping = () => {
  chrome.runtime.sendMessage({ type: 'ping-app' }, (res) => {
    if (!res) { setStatus('bad', t('error')); return; }
    if (res.ok) {
      setStatus('ok', t('connected'));
      if (res.lang) applyLang(res.lang);
      say(t('talking'), 'ok');
    } else if (res.reason === 'bad-token') {
      setStatus('bad', t('badToken'));
      say(t('badTokenMsg'), 'bad');
    } else {
      setStatus('bad', t('noApp'));
      say(t('noAppMsg'), 'bad');
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
    setStatus('bad', t('needToken'));
    say(t('needTokenMsg'));
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
  say(e.target.checked ? t('watchOn') : t('watchOff'));
});

$('test').addEventListener('click', () => {
  say(t('checking'));
  ping();
});

// 저장해 둔 언어로 먼저 그리고, 앱이 답하면 그때 맞춥니다.
chrome.storage.local.get({ lang: 'en' }).then(({ lang }) => applyLang(lang));

load();

// ⚠️ `사용량 발견` 패널을 뺐습니다.
//
//    사용량 엔드포인트를 찾아 헤매던 시절의 **디버그 도구**였습니다.
//    `/api/organizations/<org>/usage` 로 답을 찾은 뒤로는 할 일이 없어졌는데,
//    코드는 남아서 아무 JSON 이나 주워 담고 있었습니다.
//    실제로 팝업에 `/api/directory/servers` 의 `verified_tier: community` 가
//    사용량인 것처럼 줄줄이 나왔습니다.
//
//    쓸모를 다한 디버그 UI 는 남겨두면 오해를 만듭니다. 지웁니다.


// ── 자동 연결 ────────────────────────────────────────────────
//
// 앱에서 "크롬 확장 연결" 을 누르면 60초 동안 토큰을 내주는 창이 열립니다.
// 그 사이 여기서 받아오면 사용자는 아무것도 복사하지 않아도 됩니다.
$('pair')?.addEventListener('click', () => {
  const msg = $('message');
  msg.textContent = t('asking');
  msg.className = '';

  chrome.runtime.sendMessage({ type: 'auto-pair' }, (res) => {
    if (res?.ok) {
      const input = $('token');
      if (input) input.value = res.token;
      msg.textContent = t('paired');
      msg.className = 'ok';
      if (res.lang) applyLang(res.lang);
      ping();
    } else if (res?.reason === 'window-closed') {
      msg.textContent = t('pressFirst');
      msg.className = 'warn';
    } else {
      msg.textContent = t('notFound');
      msg.className = 'warn';
    }
  });
});
