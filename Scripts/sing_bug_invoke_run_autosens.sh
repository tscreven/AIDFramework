STATE_SNAPSHOT="autosensBugInvoke/state_3ed02451"
STATE_DIR="state/user1_20260403_111711"
RESUME_AT="$(cat "$STATE_SNAPSHOT/resumeTimestamp.txt")"
LOG="temp.txt"

csv="iobBugInvoke/sample_added_glucose_trace/0A9CA9B2-CD18-4AF4-8384-866278470D72_2025-07-01T12:35:00Z.csv"
basename="${csv##*/}"
stem="${basename%.csv}"

mkdir -p "$STATE_DIR"

echo "=== Buggy: $basename ==="
cp "$STATE_SNAPSHOT"/* "$STATE_DIR"/
> "$LOG"
python3 SimpleSim/simplesim.py \
    -i lyumjev \
    -a "$csv" \
    --jsbug \
    -replayState "$STATE_DIR" \
    -resumeAt "$RESUME_AT" \
    > "buggy_output.csv"

echo "Autosens ratios seen (buggy, chronological):"
grep "^autosens:" "$LOG" | sed 's/.*ratio=\([^ ]*\).*/\1/' | uniq

echo ""
echo "=== Fixed: $basename ==="
cp "$STATE_SNAPSHOT"/* "$STATE_DIR"/
> "$LOG"
python3 SimpleSim/simplesim.py \
    -i lyumjev \
    -a "$csv" \
    -replayState "$STATE_DIR" \
    -resumeAt "$RESUME_AT" \
    > "fixed_output.csv"

echo "Autosens ratios seen (fixed, chronological):"
grep "^autosens:" "$LOG" | sed 's/.*ratio=\([^ ]*\).*/\1/' | uniq

echo ""