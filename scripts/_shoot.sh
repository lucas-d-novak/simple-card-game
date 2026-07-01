#!/usr/bin/env bash
# Screenshot the already-built web app at ?netboard=1 into $1.
# Assumes `flutter build web` already ran. Starts a detached server+Edge, shoots
# with node in the foreground (the reliable ordering), then cleans up.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
OUT="${1:-screenshots/net.png}"
URL="${2:-http://localhost:8123/?netboard=1}"
for P in 8123 9222; do for pid in $(netstat -ano 2>/dev/null | grep ":${P} " | grep LISTENING | awk '{print $NF}' | sort -u); do taskkill //F //PID "$pid" >/dev/null 2>&1 || true; done; done
python -m http.server 8123 --directory build/web >/tmp/_shoot_http.log 2>&1 &
sleep 2
"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" --headless=new --remote-debugging-port=9222 --window-size=1310,604 --hide-scrollbars --no-first-run --user-data-dir="$(mktemp -d)" about:blank >/tmp/_shoot_edge.log 2>&1 &
sleep 3
export NODE_PATH="${ROOT}/node_modules"
node scripts/capture_board.mjs "$URL" "$OUT"
RC=$?
for P in 8123 9222; do for pid in $(netstat -ano 2>/dev/null | grep ":${P} " | grep LISTENING | awk '{print $NF}' | sort -u); do taskkill //F //PID "$pid" >/dev/null 2>&1 || true; done; done
exit $RC
