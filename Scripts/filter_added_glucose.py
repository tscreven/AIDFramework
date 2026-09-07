from pathlib import Path
from datetime import datetime, timedelta, timezone
import random
import pandas as pd

FOLDER = Path("added_glucose")
OUTPUT = Path("iobBugInvoke/sample_added_glucose_trace")
SUB_FOLDERS = [
    "0A9CA9B2-CD18-4AF4-8384-866278470D72",
    "547C7B4D-D130-4A57-AFF9-C6F23D577308",
    "14CFC51D-9B72-4B05-93BC-3544FCA8D58B",
    "77F59FB6-ED9C-4989-AA86-F00FC1EAC1B1",
    "9371E304-BC2B-49D1-91AB-C1CC82801ACF",
    "AB00357B-DD41-4CBB-83FE-C9A43A49D34A",
    "F349A9CB-640F-4D82-BD2E-B5089F254135",
    "70431AA7-98C0-4ED9-8EAB-93530905061B"
]

# example path: added_glucose/0A9CA9B2-CD18-4AF4-8384-866278470D72/added_glucose_2025-06-21T07:13:11Z_2025-06-21T15:38:04Z.csv

FMT = "%Y-%m-%dT%H:%M:%SZ"
WINDOW = timedelta(hours=24)
N = 3
SEED = 42

OUTPUT.mkdir(parents=True, exist_ok=True)

for sub in SUB_FOLDERS:
    folder = FOLDER / sub

    # collect 24h chunks from each file that spans > 24h
    chunks = []
    for f in sorted(folder.iterdir()):
        if f.suffix != ".csv":
            continue
        parts = f.stem.split("_")
        file_start = datetime.strptime(parts[2], FMT).replace(tzinfo=timezone.utc)
        file_end = datetime.strptime(parts[3], FMT).replace(tzinfo=timezone.utc)
        if file_end - file_start <= WINDOW:
            continue
        df = pd.read_csv(f, parse_dates=["time"])
        t0 = df["time"].iloc[0]
        while True:
            t1 = t0 + WINDOW
            chunk = df[(df["time"] >= t0) & (df["time"] < t1)]
            if chunk.empty:
                break
            if chunk["time"].max() < t1 - timedelta(minutes=5):
                break  # partial last chunk, discard
            chunks.append((t0, chunk))
            t0 = t1

    if not chunks:
        print(f"{sub}: no qualifying files")
        continue

    selected = chunks if len(chunks) <= N else random.Random(SEED).sample(chunks, N)

    print(f"{sub}: {len(chunks)} chunks total, saving {len(selected)}")
    for t0, chunk in selected:
        start_str = t0.strftime("%Y-%m-%dT%H:%M:%SZ")
        out_name = f"{sub}_{start_str}.csv"
        chunk.to_csv(OUTPUT / out_name, index=False)
        print(f"  saved {out_name}  ({len(chunk)} rows)")

print(f"\nDone — outputs in {OUTPUT}/")
