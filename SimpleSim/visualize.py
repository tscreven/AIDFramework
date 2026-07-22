#!/usr/bin/env python3

import argparse
import csv
import os
from collections import defaultdict
from datetime import datetime, timezone

import matplotlib.pyplot as plt
import matplotlib.dates as mdates


LOCAL_TZ = datetime.now(timezone.utc).astimezone().tzinfo


def load_csv(path):
    """Load a CSV and return {day: [(datetime, glucose)]} using local timezone."""
    daily = defaultdict(list)
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt = datetime.fromisoformat(row["time"]).astimezone(LOCAL_TZ)
            day = dt.strftime("%Y-%m-%d")
            glucose = float(row["glucose"])
            daily[day].append((dt, glucose))
    return daily


def main():
    parser = argparse.ArgumentParser(description="Generate daily glucose line charts from SimpleSim output")
    parser.add_argument("sim_csv", help="Path to SimpleSim output CSV")
    parser.add_argument("actual_csv", nargs="?", help="Path to added glucose CSV with real glucose values")
    parser.add_argument("-o", "--output-dir", default=".", help="Directory for output PNGs (default: current directory)")
    args = parser.parse_args()

    sim_data = load_csv(args.sim_csv)
    actual_data = load_csv(args.actual_csv) if args.actual_csv else None

    all_days = sorted(sim_data.keys())
    if actual_data:
        all_days = sorted(set(all_days) | set(actual_data.keys()))

    os.makedirs(args.output_dir, exist_ok=True)

    for day in all_days:
        fig, ax = plt.subplots(figsize=(12, 5))

        if day in sim_data:
            times, values = zip(*sorted(sim_data[day]))
            ax.plot(times, values, label="Simulated", color="#1f77b4", linewidth=1.5)

        if actual_data and day in actual_data:
            times, values = zip(*sorted(actual_data[day]))
            ax.plot(times, values, label="Actual", color="#ff7f0e", linewidth=1.5)

        # Target range shading
        ax.axhspan(70, 180, color="#2ca02c", alpha=0.08)
        ax.axhline(70, color="#2ca02c", linewidth=0.5, linestyle="--", alpha=0.5)
        ax.axhline(180, color="#2ca02c", linewidth=0.5, linestyle="--", alpha=0.5)

        ax.set_title(day)
        ax.set_xlabel("Time")
        ax.set_ylabel("Glucose (mg/dL)")
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%-I %p", tz=LOCAL_TZ))
        ax.xaxis.set_major_locator(mdates.HourLocator(interval=2, tz=LOCAL_TZ))
        fig.autofmt_xdate(rotation=45)
        ax.legend()
        ax.grid(True, alpha=0.3)

        out_path = os.path.join(args.output_dir, f"{day}.png")
        fig.savefig(out_path, dpi=150, bbox_inches="tight")
        plt.close(fig)
        print(f"Saved {out_path}")


if __name__ == "__main__":
    main()
