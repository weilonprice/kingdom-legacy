#!/bin/bash
# Stop game instances started by run.sh (tracked by pid files) and drop the
# pid files. Evidence in .verify-evidence/ is kept. Never kills by process
# name: the user's Godot editor is also a "Godot" process.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for f in "$ROOT"/.verify-evidence/*/pid; do
  [ -f "$f" ] || continue
  P="$(cat "$f")"
  if ps -p "$P" -o command= 2>/dev/null | grep -q "tools/verify/driver.tscn"; then
    kill "$P" && echo "stopped verify instance pid=$P"
  fi
  rm -f "$f"
done
echo "cleanup done; evidence kept in $ROOT/.verify-evidence/"
