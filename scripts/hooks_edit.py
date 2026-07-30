#!/usr/bin/env python3
"""
~/.claude/settings.json 에 Agent Pulse 훅을 넣고 빼는 도구.

⚠️ 왜 jq 가 아니라 Python 인가:
   jq 는 macOS 기본 탑재가 아닙니다. 설치 스크립트가 "brew install jq" 를
   시키는 순간, Homebrew 가 없는 사람은 거기서 멈춥니다.
   설치 단계 하나가 늘어날 때마다 테스터를 잃습니다.

   python3 는 macOS 에 기본으로 들어 있습니다. 의존성이 0 이 됩니다.

사용법:
    hooks_edit.py install   <settings> <url> <token>
    hooks_edit.py uninstall <settings>
"""
import json
import sys

# 우리가 구독하는 이벤트.
#
# PreToolUse / PostToolUse 를 둘 다 받는 이유는 승인 대기 보정 때문입니다.
# (지금은 Notification 훅이 주 신호이고, 타이머는 꺼진 보조 장치입니다 —
#  PendingToolTracker.swift 참고)
EVENTS = [
    "SessionStart", "UserPromptSubmit",
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "Notification", "Stop", "StopFailure", "SessionEnd",
]

MARKER = "/hook/claude"


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def strip_ours(groups, predicate):
    """우리 항목만 걷어내고, 빈 그룹은 지웁니다."""
    kept = []
    for group in groups:
        inner = [h for h in group.get("hooks", []) if not predicate(h.get("url", ""))]
        if inner:
            kept.append({**group, "hooks": inner})
    return kept


def install(path, url, token):
    data = load(path)
    hooks = data.setdefault("hooks", {})

    for event in EVENTS:
        # 같은 URL 의 기존 항목을 먼저 제거해 중복 설치를 막습니다.
        hooks[event] = strip_ours(hooks.get(event, []), lambda u: u == url)
        hooks[event].append({
            "matcher": "",
            "hooks": [{
                "type": "http",
                "url": url,
                "headers": {"X-Agent-Pulse-Token": token},
                "async": True,
                "timeout": 5,
            }],
        })

    save(path, data)


def uninstall(path):
    data = load(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return

    for event in list(hooks):
        remaining = strip_ours(hooks[event], lambda u: MARKER in u)
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]

    if not hooks:
        data.pop("hooks", None)
    save(path, data)


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["install", settings, url, token]:
            install(settings, url, token)
        case ["uninstall", settings]:
            uninstall(settings)
        case _:
            print(__doc__, file=sys.stderr)
            sys.exit(2)
