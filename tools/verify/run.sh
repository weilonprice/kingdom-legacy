#!/bin/bash
# Run one verification scenario against a fresh game instance.
#   tools/verify/run.sh <scenario.json> [--seed N] [--headless] [--timeout SECONDS]
# Prints the evidence directory; exits 0 on PASS, 1 on FAIL, 124 on timeout.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SCENARIO="" SEED=12345 HEADLESS="" TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --headless) HEADLESS="--headless"; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) SCENARIO="$1"; shift ;;
  esac
done
[ -f "$SCENARIO" ] || { echo "usage: $0 <scenario.json> [--seed N] [--headless] [--timeout S]" >&2; exit 2; }
SCENARIO="$(cd "$(dirname "$SCENARIO")" && pwd)/$(basename "$SCENARIO")"
NAME="$(basename "$SCENARIO" .json)"
OUT="$ROOT/.verify-evidence/$(date +%Y%m%d-%H%M%S)-$NAME"
mkdir -p "$OUT"
cp "$SCENARIO" "$OUT/scenario.json"

"$GODOT" --path "$ROOT" $HEADLESS --resolution 1600x900 res://tools/verify/driver.tscn \
  -- --scenario="$SCENARIO" --out="$OUT" --seed="$SEED" > "$OUT/godot.log" 2>&1 &
PID=$!
echo "$PID" > "$OUT/pid"
echo "started pid=$PID seed=$SEED out=$OUT"

for ((i = 0; i < TIMEOUT; i++)); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"   # only the instance this run started
  STATUS=124
  echo "TIMEOUT after ${TIMEOUT}s" | tee -a "$OUT/godot.log"
else
  wait "$PID"; STATUS=$?
fi
rm -f "$OUT/pid"
grep -E "^VERIFY (READY|DONE|FAIL)|SCRIPT ERROR" "$OUT/godot.log"
echo "exit=$STATUS evidence=$OUT"
exit $STATUS
