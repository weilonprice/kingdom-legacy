#!/bin/bash
# Read-only health check: is this checkout worth driving?
# Checks the Godot binary/version, that every script parses (headless editor
# load, which may refresh the .godot cache), and lists verify runs still alive.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OK=1
if [ -x "$GODOT" ]; then
  V="$("$GODOT" --version 2>/dev/null)"
  echo "godot: $V"
  case "$V" in 4.7.*) ;; *) echo "WARN: project targets Godot 4.7"; OK=0 ;; esac
else
  echo "FAIL: Godot not found at $GODOT (set GODOT=...)"; exit 1
fi
echo "commit: $(git -C "$ROOT" rev-parse --short HEAD) branch: $(git -C "$ROOT" branch --show-current)"
LOG="$(mktemp -t kl-doctor)"
perl -e 'alarm shift; exec @ARGV' 150 "$GODOT" --headless --path "$ROOT" --editor --quit-after 400 > "$LOG" 2>&1
ERRS="$(grep -iE "SCRIPT ERROR|Parse Error|Failed to load" "$LOG" | sort -u)"
if [ -n "$ERRS" ]; then echo "FAIL: scripts do not load:"; echo "$ERRS"; OK=0; else echo "scripts: all load"; fi
rm -f "$LOG"
for f in "$ROOT"/.verify-evidence/*/pid; do
  [ -f "$f" ] || continue
  P="$(cat "$f")"
  if kill -0 "$P" 2>/dev/null; then echo "running verify instance: pid=$P ($(dirname "$f"))"; fi
done
[ $OK = 1 ] && echo "DOCTOR OK" || { echo "DOCTOR FAIL"; exit 1; }
