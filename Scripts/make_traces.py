"""
Generate glucose/insulin traces and virtual user profiles from shadow execution data.

For each user it writes:
- traces/<user_id>/t1d_data_<start>_<end>.json: paired glucose and insulin chunks (from meal logs)
- VirtualUsers/<user_id>/*.json: therapy settings (from determineBasal logs)

These are the inputs to Scripts/generate_all_added_glucose.sh.

Usage (from the repo root):
    python Scripts/make_traces.py --data-dir downloaded_files/trio-oref-validation/algorithm-comparisons
"""

import argparse
import json
import sys
from glob import glob
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from Scripts.insulin_trace import clean_insulin_data, process_insulin_data
from Scripts.glucose_trace import process_glucose_data
from Scripts.extract_user_profile import extract_user_profile, save_extracted_data

# 681E14FF-BD54-4DFA-9C67-88A54B793F28 and 673C17FA-4728-467E-9331-72EAE8FC04B4 are not usable
USERS = [
    "70431AA7-98C0-4ED9-8EAB-93530905061B",
    "0A9CA9B2-CD18-4AF4-8384-866278470D72",
    "547C7B4D-D130-4A57-AFF9-C6F23D577308",
    "14CFC51D-9B72-4B05-93BC-3544FCA8D58B",
    "77F59FB6-ED9C-4989-AA86-F00FC1EAC1B1",
    "9371E304-BC2B-49D1-91AB-C1CC82801ACF",
    "AB00357B-DD41-4CBB-83FE-C9A43A49D34A",
    "F349A9CB-640F-4D82-BD2E-B5089F254135",
]


def cut_into_chunks(sorted_df: pd.DataFrame, large_gap=pd.Timedelta(minutes=30)) -> list[pd.DataFrame]:
    is_large_gap = sorted_df["date"].diff() > large_gap
    sorted_df["chunk_id"] = is_large_gap.cumsum()
    chunks = [group.drop(columns=["chunk_id"]) for _, group in sorted_df.groupby("chunk_id")]
    print(f"  chopped into {len(chunks)} chunks")
    return chunks


def pair_chunk_to(chunk: pd.DataFrame, candidate_chunks: list[pd.DataFrame]) -> pd.DataFrame | None:
    chunk_start = chunk["date"].min()
    chunk_end = chunk["date"].max()

    # not worth pairing, chunk shorter than 1 hour
    if chunk_end - chunk_start < pd.Timedelta(hours=1):
        return None

    best_match = None
    best_overlap = pd.Timedelta(0)
    for candidate in candidate_chunks:
        latest_start = max(chunk_start, candidate["date"].min())
        earliest_end = min(chunk_end, candidate["date"].max())
        overlap = max(pd.Timedelta(0), earliest_end - latest_start)
        if overlap > best_overlap:
            best_overlap = overlap
            best_match = candidate[candidate["date"].between(latest_start, earliest_end)]

    return best_match


def load_json(path: str):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        print(f"  skipping {path}: {e}")
        return None


def make_traces(data_dir: str, user_id: str, save_dir: Path):
    json_files = sorted(glob(f"{data_dir}/**/meal/{user_id}/*.json", recursive=True))
    print(f"  found {len(json_files)} meal JSON files")

    glucose_list = []
    insulin_list = []
    for jf in json_files:
        data = load_json(jf)
        if data is None:
            continue
        insulin_list.append(clean_insulin_data(data))
        glucose_list.append(process_glucose_data(data))

    glucose_df = pd.concat(glucose_list, ignore_index=True)
    glucose_df.drop_duplicates(subset=["date"], inplace=True)
    glucose_df.sort_values("date", inplace=True, ignore_index=True)

    insulin_df = pd.concat(insulin_list, ignore_index=True)
    insulin_df = process_insulin_data(insulin_df)
    insulin_df.drop_duplicates(subset=["date", "value", "deliveryReason"], inplace=True)
    insulin_df.sort_values("date", inplace=True, ignore_index=True)

    glucose_chunks = cut_into_chunks(glucose_df)
    insulin_chunks = cut_into_chunks(insulin_df)

    save_dir.mkdir(parents=True, exist_ok=True)
    n_saved = 0
    for chunk in insulin_chunks:
        matching_glucose = pair_chunk_to(chunk, glucose_chunks)
        if matching_glucose is None:
            continue
        combined = pd.concat([chunk, matching_glucose], ignore_index=True)
        combined.sort_values("date", inplace=True, ignore_index=True)

        start_date = combined["date"].iloc[0].strftime("%Y-%m-%dT%H:%M:%SZ")
        end_date = combined["date"].iloc[-1].strftime("%Y-%m-%dT%H:%M:%SZ")
        combined["date"] = combined["date"].dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        combined.to_json(save_dir / f"t1d_data_{start_date}_{end_date}.json", orient="records", indent=2)
        n_saved += 1

    print(f"  saved {n_saved} traces to {save_dir}")


def make_virtual_user(data_dir: str, user_id: str, save_dir: Path):
    json_files = sorted(glob(f"{data_dir}/**/determineBasal/{user_id}/*.json", recursive=True))
    print(f"  found {len(json_files)} determineBasal JSON files")

    extracted_data = None
    for jf in json_files:
        data = load_json(jf)
        if data is None:
            continue
        ok, extracted_data = extract_user_profile(data, extracted_data)
        if ok:
            break

    if extracted_data is None:
        print(f"  failed to find any user profile data for {user_id}")
        return
    save_extracted_data(extracted_data, save_dir)


def main():
    parser = argparse.ArgumentParser(description="Generate traces/ and VirtualUsers/ from shadow execution data")
    parser.add_argument("--data-dir", required=True,
                        help="algorithm-comparisons folder, e.g. downloaded_files/trio-oref-validation/algorithm-comparisons")
    parser.add_argument("--out-dir", default=".", help="where traces/ and VirtualUsers/ are written (default: .)")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    for user_id in USERS:
        print(f"===== {user_id}")
        make_traces(args.data_dir, user_id, out_dir / "traces" / user_id)
        make_virtual_user(args.data_dir, user_id, out_dir / "VirtualUsers" / user_id)


if __name__ == "__main__":
    main()
