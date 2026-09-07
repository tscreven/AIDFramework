STATE_SNAPSHOT="iobBugInvoke/state_91a36648-cc7e-4f11-9364-d725d1cb289f.4"
STATE_DIR="state/user1_20260403_111711"
RESUME_AT="$(cat "$STATE_SNAPSHOT/resumeTimestamp.txt")"
LOG="temp.txt"

csv="iobBugInvoke/sample_added_glucose_trace/14CFC51D-9B72-4B05-93BC-3544FCA8D58B_2025-11-02T10:15:00Z.csv"
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

python3 Scripts/plot_glucose.py 