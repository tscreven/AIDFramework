#!/usr/bin/env python3

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from exponential_insulin_model import ExponentialInsulinModel


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert insulin and glucose timeseries into addedGlucose"
    )
    parser.add_argument("-u", required=True, help="Virtual user directory path")
    parser.add_argument("-i", required=True, help="Insulin and glucose JSON file")
    return parser.parse_args()


def parse_date(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def round_to_5min(dt):
    epoch = dt.timestamp()
    rounded = round(epoch / 300) * 300
    return datetime.fromtimestamp(rounded, tz=timezone.utc)


def minutes_of_day(dt):
    return dt.hour * 60 + dt.minute


def lookup_isf(sensitivities, dt):
    mod = minutes_of_day(dt)
    active = sensitivities[0]
    for entry in sensitivities:
        if entry["offset"] <= mod:
            active = entry
    return active["sensitivity"]


def main():
    args = parse_args()

    # Load insulin sensitivities from virtual user directory
    with open(f"{args.u}/insulin_sensitivities.json") as f:
        isf_data = json.load(f)
    sensitivities = isf_data["sensitivities"]

    # Load input data
    with open(args.i) as f:
        data = json.load(f)

    # Separate glucose and insulin entries, align to 5m boundaries
    glucose_by_time = {}
    insulin_by_time = {}

    for entry in data:
        dt = parse_date(entry["date"])
        aligned = round_to_5min(dt)

        if entry["type"] == "glucose":
            if aligned not in glucose_by_time:
                glucose_by_time[aligned] = []
            glucose_by_time[aligned].append(entry["value"])
        elif entry["type"] == "insulin":
            if aligned not in insulin_by_time:
                insulin_by_time[aligned] = 0.0
            insulin_by_time[aligned] += entry["value"]

    # Average glucose values at same 5m boundary
    glucose_aligned = {}
    for t, values in glucose_by_time.items():
        glucose_aligned[t] = sum(values) / len(values)

    known_times = sorted(glucose_aligned.keys())

    if len(known_times) < 2:
        print("Error: need at least 2 glucose readings", file=sys.stderr)
        sys.exit(1)

    # Check for gaps > 30m
    for j in range(len(known_times) - 1):
        gap_min = (known_times[j + 1] - known_times[j]).total_seconds() / 60
        if gap_min > 30:
            print(
                f"Error: glucose gap of {gap_min:.0f} minutes between "
                f"{known_times[j].isoformat()} and {known_times[j+1].isoformat()}",
                file=sys.stderr,
            )
            sys.exit(1)

    # Build complete 5m timeline and interpolate missing glucose
    start = known_times[0]
    end = known_times[-1]
    all_times = []
    t = start
    while t <= end:
        all_times.append(t)
        t += timedelta(minutes=5)

    interpolated_glucose = {}
    ki = 0  # index into known_times
    for t in all_times:
        if t in glucose_aligned:
            interpolated_glucose[t] = glucose_aligned[t]
        else:
            # Advance ki so known_times[ki] <= t < known_times[ki+1]
            while ki + 1 < len(known_times) and known_times[ki + 1] <= t:
                ki += 1
            before = known_times[ki]
            after = known_times[ki + 1]
            frac = (t - before).total_seconds() / (after - before).total_seconds()
            interpolated_glucose[t] = (
                glucose_aligned[before]
                + frac * (glucose_aligned[after] - glucose_aligned[before])
            )

    glucose_series = [(t, interpolated_glucose[t]) for t in all_times]

    # Sort insulin entries by time
    insulin_entries = sorted(insulin_by_time.items())

    # Use lyumjev model for insulin action
    model = ExponentialInsulinModel.lyumjev()

    # Calculate and output added glucose
    print("time,glucose,insulinAction,addedGlucose")

    for i, (t, glucose) in enumerate(glucose_series):
        if i == 0:
            print(f"{t.isoformat()},{glucose:.1f},0.0000,0.0000")
            continue

        t_prev = glucose_series[i - 1][0]
        g_prev = glucose_series[i - 1][1]
        delta_glucose = glucose - g_prev

        # Sum insulin action from all deliveries in the last 10 hours
        total_insulin_action = 0.0
        cutoff = t - timedelta(hours=10)
        for ins_time, ins_units in insulin_entries:
            if ins_time < cutoff:
                continue
            if ins_time > t:
                break
            t_minus_one_secs = (t_prev - ins_time).total_seconds()
            t_secs = (t - ins_time).total_seconds()
            pct_prev = model.percent_effect_remaining(t_minus_one_secs)
            pct_curr = model.percent_effect_remaining(t_secs)
            total_insulin_action += (pct_prev - pct_curr) * ins_units

        isf = lookup_isf(sensitivities, t)
        added_glucose = delta_glucose + total_insulin_action * isf

        print(f"{t.isoformat()},{glucose:.1f},{total_insulin_action:.4f},{added_glucose:.4f}")


if __name__ == "__main__":
    main()
