import json
from pathlib import Path

json_path = 'iob-comparison-threshold.json'

with open(json_path, 'r') as f:
    data = json.load(f)

files = data['entries']

files = sorted(files, key=lambda x: x['maxDelta'], reverse=True)

for i, file in enumerate(files):
    filePath = file['filePath']
    basename = Path(filePath).name
    print(basename)

    if i >= 100:
        break