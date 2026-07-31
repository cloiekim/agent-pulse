#!/usr/bin/env python3
"""
Antigravity 의 hooks.json 에 Agent Pulse 훅을 넣고 뺍니다.

⚠️ jq 를 쓰지 않는 이유는 hooks_edit.py 와 같습니다 —
   macOS 기본 탑재가 아니라 설치 단계가 하나 늘어납니다.

사용법:
    hooks_edit_antigravity.py install   <hooks.json> <bridge.sh>
    hooks_edit_antigravity.py uninstall <hooks.json>
"""
import json
import sys

# 승인 대기를 알려주는 훅은 없습니다. 있는 것만 구독합니다.
EVENTS = ["PreToolUse", "PostToolUse", "PreInvocation", "PostInvocation", "Stop"]
MARKER = "agent-pulse-antigravity.sh"


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


def strip_ours(handlers):
    """우리 항목만 걷어냅니다. 남의 훅은 그대로 둡니다."""
    return [h for h in handlers if MARKER not in str(h.get("command", ""))]


def install(path, bridge):
    data = load(path)
    hooks = data.setdefault("hooks", {})

    for event in EVENTS:
        handlers = strip_ours(hooks.get(event, []))
        handlers.append({
            # 훅 이름을 인자로 넘겨야 브릿지가 무슨 일이 일어났는지 압니다.
            "command": f'"{bridge}" {event}',
            "timeout": 5,
        })
        hooks[event] = handlers

    save(path, data)


def uninstall(path):
    data = load(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event in list(hooks):
        remaining = strip_ours(hooks[event])
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]
    if not hooks:
        data.pop("hooks", None)
    save(path, data)


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["install", path, bridge]:
            install(path, bridge)
        case ["uninstall", path]:
            uninstall(path)
        case _:
            print(__doc__, file=sys.stderr)
            sys.exit(2)
