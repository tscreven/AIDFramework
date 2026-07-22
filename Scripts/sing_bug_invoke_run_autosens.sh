STATE_SNAPSHOT="autosensBugInvoke/state_autosens_error"
STATE_DIR="state/user1_20260403_111711"
RESUME_AT="1763639955.907"
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
    > "buggy_output.csv" # may want to change the output path

echo ""
echo "=== Fixed: $basename ==="
cp "$STATE_SNAPSHOT"/* "$STATE_DIR"/
> "$LOG"
python3 SimpleSim/simplesim.py \
    -i lyumjev \
    -a "$csv" \
    -replayState "$STATE_DIR" \
    -resumeAt "$RESUME_AT" \
    > "fixed_output.csv" # may want to change the output path

echo ""