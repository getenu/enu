#!/usr/bin/env bash
# Reliable repro for the reload reincarnation race (use-after-destroy under
# churn) — NO subagents, NO MCP, NO Godot interaction. Just file writes +
# the engine log. Run it against an ALREADY-RUNNING Enu with a level loaded
# (a debug build is ideal — assertions fire and the worker stall is visible).
#
# Usage:
#   reload-churn-repro.sh [LEVEL_DIR] [CYCLES] [animated|static]
# Defaults: skill-test level, 10 cycles, animated.
#
# What it does: creates ONE build, then rapidly rewrites it and `touch`es its
# JSON. Each JSON mtime bump forces worker.nim's mtime-only reload
# (`state.units -= unit; load_unit_from_json`) = a destroy+recreate of the same
# id (a reincarnation). Done fast, the cross-thread DESTROY echo for incarnation
# N lands after incarnation N+1 exists and kills it -> `Ed invalid` on a live
# unit's field (packed_chunks, then code_value, ...), and a reactive cascade
# that stalls the worker (heartbeat freezes = the "lockup").
#
# PASS (bug gone) = 0 Ed-invalid AND the worker-stats heartbeat keeps advancing.
# FAIL (bug present) = hundreds/thousands of Ed-invalid and/or a stalled heartbeat.

set -u
LEVEL="${1:-$HOME/Library/Application Support/enu/default/skill-test}"
CYCLES="${2:-10}"
MODE="${3:-animated}"
LOG="$HOME/Library/Application Support/enu/logs/enu.log"
ID="build_churn_repro"
SCR="$LEVEL/scripts/$ID.nim"
JSON="$LEVEL/data/$ID/$ID.json"

valid_script() {
  if [ "$MODE" = static ]; then
    printf 'speed=0\nbox(width=6,height=20,depth=1,color=brown)\nbox(width=4,height=2,depth=4,at=vec3(1,1,1),color=red)\n'
  else
    printf 'speed=0\nbox(width=6,height=20,depth=1,color=brown)\nbox(width=4,height=2,depth=4,at=vec3(1,1,1),color=red)\nmove me\nspeed=8\nloop:\n  nil -> sleep as down\n  down -> up(home + 16) as up\n  up -> down(home) as down\n'
  fi
}
# A version with a deliberate compile error (the original `home + vec3` type
# mismatch) to add reload pressure via the failed-script retry path.
error_script() {
  printf 'speed=0\nbox(width=6,height=20,depth=1,color=brown)\nmove me\nspeed=8\nloop:\n  nil -> sleep as down\n  down -> up(home + vec3(0,16,0)) as up\n  up -> down(home) as down\n'
}

mkdir -p "$LEVEL/data/$ID"
printf '{"id":"%s","start_transform":{"basis":[[1,0,0],[0,1,0],[0,0,1]],"origin":[150.0,0.0,-150.0]},"start_color":"BROWN","edits":{}}\n' "$ID" > "$JSON"

base=$(wc -l < "$LOG")
hb_before=$(grep -ac "worker stats" "$LOG")
echo ">>> churning $ID ($MODE), $CYCLES cycles..."
for i in $(seq 1 "$CYCLES"); do
  valid_script > "$SCR"; touch "$JSON"; sleep 0.6
  error_script > "$SCR"; touch "$JSON"; sleep 0.6
done
echo ">>> done; settling 6s..."; sleep 6

invalid=$(tail -n +$((base+1)) "$LOG" | grep -acE "Ed invalid")
fatal=$(tail -n +$((base+1)) "$LOG"  | grep -acE "Unhandled worker thread exception")
hb_after=$(grep -ac "worker stats" "$LOG")
hb_last=$(grep -a "worker stats" "$LOG" | tail -1 | grep -aoE "[0-9]{2}:[0-9]{2}:[0-9]{2}")
echo "----------------------------------------"
echo "Ed-invalid (since baseline):  $invalid"
echo "worker fatal:                 $fatal"
echo "worker-stats heartbeat:       +$((hb_after - hb_before)) ticks (last $hb_last) — advancing if > 0"
echo "verdict: $([ "$invalid" -eq 0 ] && [ "$fatal" -eq 0 ] && echo PASS || echo FAIL)"
echo "----------------------------------------"
echo "cleanup: rm -rf \"$LEVEL/data/$ID\" \"$SCR\"   (with Enu DOWN — a wedged build can fatal on delete)"
