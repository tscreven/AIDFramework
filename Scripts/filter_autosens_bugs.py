import json
import sys
from pathlib import Path

json_path = 'autosens-comparison-threshold.json'

with open(json_path, 'r') as f:
    data = json.load(f)


files = data['entries']

files = sorted(files, key=lambda x: x['maxDelta'], reverse=True)


seen_names = set()

for i, file in enumerate(files):
    filePath = file['filePath']
    basename = Path(filePath).name
    uuid = basename.split('.')[0]
    if uuid in seen_names:
        # Short-name state dirs would collide; create these with --long-name instead
        print(f"skipped (duplicate user): {basename}", file=sys.stderr)
        continue
    seen_names.add(uuid)
    print(basename)

    if i >= 100:
        break