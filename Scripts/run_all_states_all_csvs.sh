#!/bin/bash
set -e

TRACE_DIR="iobBugInvoke/sample_added_glucose_trace"
MAX_PARALLEL=8
LOG="temp.txt"
BUGTYPE="autosensBugInvoke"
# BUGTYPE="iobBugInvoke"

run_state() {
    local STATE_SNAPSHOT="$1"
    local SNAPSHOT_ID="${STATE_SNAPSHOT##*_}"
    if [ ! -f "$STATE_SNAPSHOT/resumeTimestamp.txt" ]; then
        echo "=== Skipping $SNAPSHOT_ID (no resumeTimestamp.txt) ===" >&2
        return
    fi
    local STATE_DIR="state/tmp_${SNAPSHOT_ID}"
    local RESUME_AT
    RESUME_AT="$(cat "$STATE_SNAPSHOT/resumeTimestamp.txt")"
    local BUGGY_OUT="$BUGTYPE/simOut_${SNAPSHOT_ID}/buggy"
    local FIXED_OUT="$BUGTYPE/simOut_${SNAPSHOT_ID}/fixed"

    if [ -d "$BUGGY_OUT" ] && [ -d "$FIXED_OUT" ]; then
        echo "=== Skipping snapshot $SNAPSHOT_ID (already exists) ==="
        return
    fi

    mkdir -p "$STATE_DIR" "$BUGGY_OUT" "$FIXED_OUT"

    for csv in "$TRACE_DIR"/*.csv; do
        local basename="${csv##*/}"
        local stem="${basename%.csv}"

        echo "=== [$SNAPSHOT_ID] Buggy: $basename ==="
        cp "$STATE_SNAPSHOT"/* "$STATE_DIR"/
        > "$LOG"
        python3 SimpleSim/simplesim.py \
            -i lyumjev \
            -a "$csv" \
            --jsbug \
            -replayState "$STATE_DIR" \
            -resumeAt "$RESUME_AT" \
            > "$BUGGY_OUT/${stem}_output.csv"

        echo "=== [$SNAPSHOT_ID] Fixed: $basename ==="
        cp "$STATE_SNAPSHOT"/* "$STATE_DIR"/
        > "$LOG"
        python3 SimpleSim/simplesim.py \
            -i lyumjev \
            -a "$csv" \
            -replayState "$STATE_DIR" \
            -resumeAt "$RESUME_AT" \
            > "$FIXED_OUT/${stem}_output.csv"
    done

    rm -rf "$STATE_DIR"
}

jobs=0
for STATE_SNAPSHOT in $BUGTYPE/state_*/; do
    run_state "${STATE_SNAPSHOT%/}" &
    (( jobs++ ))
    if (( jobs >= MAX_PARALLEL )); then
        wait
        jobs=0
    fi
done
wait

echo "Done."
