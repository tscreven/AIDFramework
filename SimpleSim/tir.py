#!/usr/bin/env python3

import argparse
import csv
from collections import defaultdict
from datetime import datetime, timezone


LOCAL_TZ = datetime.now(timezone.utc).astimezone().tzinfo

CATEGORIES = [
    ("very_high", "> 250"),
    ("high",      "181-250"),
    ("in_range",  "70-180"),
    ("low",       "55-69"),
    ("very_low",  "< 55"),
]


def parse_local_day(ts):
    """Parse an ISO8601 timestamp and return the local-timezone date string."""
    dt = datetime.fromisoformat(ts).astimezone(LOCAL_TZ)
    return dt.strftime("%Y-%m-%d")


def classify(glucose):
    if glucose > 250:
        return "very_high"
    elif glucose > 180:
        return "high"
    elif glucose >= 70:
        return "in_range"
    elif glucose >= 55:
        return "low"
    else:
        return "very_low"


def load_csv(path):
    """Load a CSV and return {day: [glucose_values]} using local timezone for days."""
    daily_glucose = defaultdict(list)
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            day = parse_local_day(row["time"])
            glucose = float(row["glucose"])
            daily_glucose[day].append(glucose)
    return daily_glucose


def print_day_stats(label, glucose_values):
    """Print TIR stats for a single day of glucose values."""
    counts = defaultdict(int)
    for g in glucose_values:
        counts[classify(g)] += 1
    total = len(glucose_values)
    avg = sum(glucose_values) / total
    print(f"  {label}  ({total} readings, avg {avg:.0f} mg/dL)")
    for key, cat_label in CATEGORIES:
        n = counts[key]
        pct = 100 * n / total
        print(f"    {cat_label:>7s}:  {pct:5.1f}%  ({n} readings)")


def main():
    parser = argparse.ArgumentParser(description="Calculate daily glucose time-in-range from SimpleSim CSV output")
    parser.add_argument("sim_csv", help="Path to SimpleSim output CSV")
    parser.add_argument("actual_csv", nargs="?", help="Path to added glucose CSV with real glucose values")
    args = parser.parse_args()

    sim_data = load_csv(args.sim_csv)
    actual_data = load_csv(args.actual_csv) if args.actual_csv else None

    all_days = sorted(sim_data.keys())
    if actual_data:
        all_days = sorted(set(all_days) | set(actual_data.keys()))

    for day in all_days:
        print(f"\n{day}")
        print("-" * 50)
        has_sim = day in sim_data
        has_actual = actual_data and day in actual_data

        if has_sim and has_actual:
            print_day_stats("Simulated", sim_data[day])
            print()
            print_day_stats("Actual   ", actual_data[day])
        elif has_sim:
            print_day_stats("Simulated", sim_data[day])
        elif has_actual:
            print_day_stats("Actual   ", actual_data[day])


if __name__ == "__main__":
    main()
