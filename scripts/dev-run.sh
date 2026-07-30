#!/usr/bin/env bash
#
# Agent Pulse — 개발용 재실행
#
# 기존 인스턴스를 죽이고, 새로 빌드하고, 백그라운드로 띄웁니다.
# 터미널 탭을 점유하지 않으므로 같은 탭에서 계속 명령어를 칠 수 있습니다.
#
# 사용법:  ./scripts/dev-run.sh
# 로그 보기: tail -f /tmp/agent-pulse.log
# 끄기:     killall AgentPulse

set -uo pipefail
cd "$(dirname "$0")/.."

LOG=/tmp/agent-pulse.log

echo "▸ 기존 인스턴스 종료..."
killall AgentPulse 2>/dev/null && sleep 1 || echo "  (돌고 있는 게 없었습니다)"

# 포트가 풀릴 때까지 잠깐 기다립니다.
for _ in 1 2 3 4 5; do
  lsof -nP -iTCP:8787 -sTCP:LISTEN >/dev/null 2>&1 || break
  sleep 1
done

echo "▸ 빌드..."
if ! swift build; then
  echo "❌ 빌드 실패 — 위 에러를 확인하세요."
  exit 1
fi

echo "▸ 실행 (백그라운드)..."
nohup ./.build/debug/AgentPulse > "$LOG" 2>&1 &
sleep 2

if pgrep -x AgentPulse >/dev/null; then
  echo
  echo "✓ 실행 중 (PID $(pgrep -x AgentPulse))"
  echo
  echo "  로그 보기 :  tail -f $LOG"
  echo "  끄기      :  killall AgentPulse"
  echo
  echo "── 최근 로그 ──"
  tail -5 "$LOG"
else
  echo "❌ 실행 실패. 로그를 확인하세요: $LOG"
  tail -20 "$LOG"
  exit 1
fi
