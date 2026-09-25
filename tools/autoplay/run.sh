#!/bin/bash
# Plays whole games with the autoplayer and collects reports.
#   tools/autoplay/run.sh [--seeds 12345,7] [--minutes 120] [--difficulty 1]
# Reports land in .autoplay/<timestamp>/seed-<n>/{report.json,summary.md}.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SEEDS=12345 MINUTES=120 DIFF=1
while [ $# -gt 0 ]; do
  case "$1" in
    --seeds) SEEDS="$2"; shift 2 ;;
    --minutes) MINUTES="$2"; shift 2 ;;
    --difficulty) DIFF="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
OUT="$ROOT/.autoplay/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
for s in ${SEEDS//,/ }; do
  mkdir -p "$OUT/seed-$s"
  # Real-time cap: generous, a 120-minute game usually takes a few minutes.
  perl -e 'alarm shift; exec @ARGV' 3600 "$GODOT" --headless --fixed-fps 30 --path "$ROOT" \
    res://tools/autoplay/autoplay.tscn -- --seed="$s" --minutes="$MINUTES" --difficulty="$DIFF" \
    --out="$OUT/seed-$s" > "$OUT/seed-$s/godot.log" 2>&1
  grep "AUTOPLAY" "$OUT/seed-$s/godot.log" | tail -1
  errors=$(grep -c "SCRIPT ERROR" "$OUT/seed-$s/godot.log")
  [ "$errors" -gt 0 ] && echo "WARNING: $errors script error(s) in seed-$s/godot.log"
done
echo "$OUT"
