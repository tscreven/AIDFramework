#!/usr/bin/env python3

import argparse
import csv
import json
import math
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from exponential_insulin_model import ExponentialInsulinModel


def parse_args():
    parser = argparse.ArgumentParser(description="SimpleSim - virtual human glucose simulator")
    parser.add_argument("-u", help="Virtual user directory path")
    parser.add_argument("-i", required=True, choices=["humalog", "lyumjev"], help="Insulin type")
    parser.add_argument("-g", type=float, help="Initial glucose concentration (mg/dL)")
    parser.add_argument("-n", type=int, help="Number of 5-minute simulation steps")
    parser.add_argument("-f", action="store_true", help="Enable low pass filtering on glucose")
    parser.add_argument("-a", help="Added glucose CSV file for trace replay")
    parser.add_argument("-replayState", help="State directory to load in replay mode.")
    parser.add_argument(
        "-previousOutputs",
        help="CSV file containing prior simulator outputs required when resuming from replayState."
    )
    parser.add_argument(
        "-resumeAt",
        type=float,
        default=None,
        help="Unix timestamp to start the simulation clock at. Remaps the added_glucose trace "
             "to start at this time, seeding insulin history from -replayState pump_history.json. "
             "No -previousOutputs needed when this is used."
    )
    parser.add_argument(
        "-stopTime",
        help="Stop replay when the trace timestamp reaches this time (ISO-8601 or Unix timestamp)."
    )
    parser.add_argument("-timezone", default=None, help="IANA timezone for the JS runtime (e.g. 'America/Vancouver'). Sets TZ env var for the Swift subprocess.")
    parser.add_argument("--timing", action="store_true", help="Print per-step timing to stderr")
    parser.add_argument("--js", action="store_true", help="Run JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("--jsbug", action="store_true", help="Run buggy JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("--jsiobfix", action="store_true", help="Run IOB fixed buggy JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("--jsiob_as_fix", action="store_true", help="Run IOB and Autosens fixed buggy JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("--jsiob_as_db_fix", action="store_true", help="Run IOB, Autosens, and determine basal fixed buggy JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("--autosensSeconds", action="store_true", help="Pass --autosensSeconds to oref-swift calculate (encode JS autosens input dates as Unix seconds).")

    args = parser.parse_args()
    if args.replayState is None and args.u is None:
        parser.error("-u is required unless -replayState is provided")
    if args.replayState is not None and args.previousOutputs is None and args.resumeAt is None:
        parser.error("-previousOutputs is required when -replayState is provided (unless -resumeAt is used)")
    if args.a is None and (args.g is None or args.n is None):
        parser.error("-g and -n are required unless -a is provided")
    return args


def load_added_glucose_csv(path):
    timestamps = []
    added_glucose_values = []
    glucose_values = []
    initial_glucose = None
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Parse UTC timestamp and convert to local timezone
            try: 
                dt = datetime.fromisoformat(row["times"]).astimezone()
            except:
                dt = datetime.fromisoformat(row["time"]).astimezone()
            timestamps.append(dt)
            added_glucose_values.append(float(row["addedGlucose"]))
            glucose_values.append(float(row["glucose"]))
            if initial_glucose is None:
                initial_glucose = float(row["glucose"])
    return timestamps, initial_glucose, added_glucose_values, glucose_values


OREF_SWIFT_BINARY = ".build/arm64-apple-macosx/release/oref-swift"


def initialize(virtual_user):
    result = subprocess.run(
        [OREF_SWIFT_BINARY, "initialize", "-u", virtual_user, "-o", "-"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Error initializing: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    output = json.loads(result.stdout)
    return output["stateDir"]


def load_basal_profile(state_dir):
    with open(f"{state_dir}/basal_profile.json") as f:
        return json.load(f)


def load_insulin_sensitivities(state_dir):
    with open(f"{state_dir}/insulin_sensitivities.json") as f:
        data = json.load(f)
    return data["sensitivities"]


def load_optional_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def minutes_of_day(dt):
    return dt.hour * 60 + dt.minute


def parse_stop_time(value):
    if value is None:
        return None
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc).astimezone()
    except ValueError:
        pass
    try:
        dt = datetime.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"Invalid stopTime '{value}'. Expected ISO-8601 datetime or Unix timestamp."
        ) from None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.now().astimezone().tzinfo)
    return dt.astimezone()


def load_last_state_glucose_timestamp(state_dir):
    glucose_records = load_optional_json(f"{state_dir}/glucose.json")
    if not glucose_records:
        return None

    last_timestamp = glucose_records[-1].get("timestamp")
    if last_timestamp is None:
        return None

    return datetime.fromtimestamp(float(last_timestamp), tz=timezone.utc).astimezone()


def find_replay_start_index(timestamps, replay_state_timestamp):
    if replay_state_timestamp is None:
        return 0

    for index, timestamp in enumerate(timestamps):
        if timestamp > replay_state_timestamp:
            return index

    return len(timestamps)


def write_replay_state_directory(state_dir, alg):
    with open(f"{alg}ReplayStateDirectory.json", "w") as f:
        json.dump({"stateDir": state_dir}, f)


def parse_output_float(value, default=None):
    if value is None or value == "":
        return default
    return float(value)


def load_previous_outputs_csv(path):
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row:
                continue
            if row.get("time") in (None, ""):
                continue
            if row.get("time") == "time":
                rows = []
                continue
            rows.append({
                "time": datetime.fromisoformat(row["time"]).astimezone(),
                "glucose": parse_output_float(row["glucose"]),
                "insulin": parse_output_float(row["insulin"], 0.0),
                "unfiltered_glucose": parse_output_float(row.get("unfiltered glucose")),
                "total_insulin_action": parse_output_float(row.get("total insulin action")),
                "isf": parse_output_float(row.get("insulin sensitivity factor")),
                "temp_basal_rate": parse_output_float(row.get("temp basal rate")),
                "duration": parse_output_float(row.get("duration")),
            })
    return rows


def load_resume_state(previous_outputs_path, replay_state_timestamp):
    rows = load_previous_outputs_csv(previous_outputs_path)
    if not rows:
        return [], None, None, None

    if replay_state_timestamp is not None:
        rows = [row for row in rows if row["time"] <= replay_state_timestamp]

    if not rows:
        return [], None, None, None

    last_row = rows[-1]
    cutoff = last_row["time"] - timedelta(hours=10)
    insulin_deliveries = [
        (row["time"], row["insulin"])
        for row in rows
        if row["time"] >= cutoff and row["insulin"] is not None
    ]

    pump_temp_basal = None
    if last_row["temp_basal_rate"] is not None and last_row["duration"] is not None and last_row["duration"] > 0:
        pump_temp_basal = {
            "rate": last_row["temp_basal_rate"],
            "remaining_minutes": int(last_row["duration"]),
        }

    return (
        insulin_deliveries,
        pump_temp_basal,
        last_row["glucose"],
        last_row["unfiltered_glucose"] if last_row["unfiltered_glucose"] is not None else last_row["glucose"],
    )


def load_last_previous_output_timestamp(previous_outputs_path):
    rows = load_previous_outputs_csv(previous_outputs_path)
    if not rows:
        return None
    return rows[-1]["time"]


def validate_replay_inputs(replay_state_timestamp, previous_outputs_timestamp):
    if replay_state_timestamp is None or previous_outputs_timestamp is None:
        return

    if replay_state_timestamp != previous_outputs_timestamp:
        print(
            "Error: replayState and previousOutputs do not describe the same resume point. "
            f"replayState ends at {replay_state_timestamp.isoformat()} but previousOutputs ends at "
            f"{previous_outputs_timestamp.isoformat()}",
            file=sys.stderr,
        )
        sys.exit(1)


def compute_resume_glucose(model, last_glucose, insulin_deliveries, sensitivities, resume_timestamp, added_glucose):
    if last_glucose is None:
        return None, -1, -1

    isf = lookup_isf(sensitivities, resume_timestamp)
    total_insulin_action = compute_insulin_action(model, insulin_deliveries, resume_timestamp)
    glucose = max(40, min(400, last_glucose - total_insulin_action * isf + added_glucose))
    return glucose, total_insulin_action, isf


def lookup_basal_rate(basal_profile, dt):
    mod = minutes_of_day(dt)
    active = basal_profile[0]
    for entry in basal_profile:
        if entry["minutes"] <= mod:
            active = entry
    return active["rate"]


def lookup_isf(sensitivities, dt):
    mod = minutes_of_day(dt)
    active = sensitivities[0]
    for entry in sensitivities:
        if entry["offset"] <= mod:
            active = entry
    return active["sensitivity"]


def calculate(state_dir, timestamp, glucose, run_js, use_timing=False, inspect_from=None, timezone=None, autosens_seconds=False):
    if run_js is None:
        cmd = [OREF_SWIFT_BINARY, "calculate", "-s", state_dir, "-i", "-", "-o", "-"]
    else:
        cmd = [OREF_SWIFT_BINARY, "calculate", run_js, "-s", state_dir, "-i", "-", "-o", "-"]

    if autosens_seconds:
        cmd.append("--autosens-seconds")
    if use_timing:
        cmd.append("--timing")
    if inspect_from is not None:
        cmd.extend(["--inspectStart", inspect_from])
    input_data = json.dumps({"timestamp": timestamp, "glucose": glucose})
    env = None
    if timezone is not None:
        import os
        env = os.environ.copy()
        env["TZ"] = timezone
    result = subprocess.run(
        cmd,
        input=input_data, capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        print(f"Error calculating: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    if use_timing and result.stderr:
        sys.stderr.write(result.stderr)
    return json.loads(result.stdout)


def simulate_step(state_dir, basal_profile, t, glucose, pump_temp_basal, determination):
    """Process a single simulation step: handle insulin dosing from determination.
    Returns (five_min_insulin, pump_temp_basal)."""
    five_min_insulin = 0.0

    # Handle SMB bolus
    bolus_units = determination.get("units")
    if bolus_units is not None and bolus_units > 0:
        five_min_insulin += bolus_units

    # Handle temp basal state machine
    det_rate = determination.get("rate")
    det_duration = determination.get("duration")

    if det_rate is not None and det_duration is not None:
        if det_rate == 0 and det_duration == 0:
            pump_temp_basal = None
        else:
            pump_temp_basal = {"rate": det_rate, "remaining_minutes": det_duration}

    # Determine basal rate for this 5-min period
    if pump_temp_basal is not None:
        active_rate = pump_temp_basal["rate"]
    else:
        active_rate = lookup_basal_rate(basal_profile, t)

    five_min_insulin += active_rate / 12.0

    # Decrement temp basal remaining time
    if pump_temp_basal is not None:
        pump_temp_basal["remaining_minutes"] -= 5
        if pump_temp_basal["remaining_minutes"] <= 0:
            pump_temp_basal = None

    return five_min_insulin, pump_temp_basal, active_rate


LOW_PASS_TAU = 11.3  # minutes


def low_pass_filter(raw_glucose, prev_filtered, delta_minutes):
    """Apply time-aware IIR low-pass filter to a glucose reading.
    Returns the filtered glucose value."""
    alpha = 1 - math.exp(-delta_minutes / LOW_PASS_TAU)
    return alpha * raw_glucose + (1 - alpha) * prev_filtered


def compute_insulin_action(model, insulin_deliveries, t):
    """Sum insulin action from all deliveries in the last 10 hours."""
    cutoff = t - timedelta(hours=10)
    total = 0.0
    for delivery_time, units in insulin_deliveries:
        if delivery_time < cutoff:
            continue
        t_minus_one_secs = (t - timedelta(minutes=5) - delivery_time).total_seconds()
        t_secs = (t - delivery_time).total_seconds()
        pct_at_t_minus_one = model.percent_effect_remaining(t_minus_one_secs)
        pct_at_t = model.percent_effect_remaining(t_secs)
        total += (pct_at_t_minus_one - pct_at_t) * units
    return total


def load_resume_state_from_dir(state_dir, resume_at_ts, basal_profile):
    """Seed resume state from pump_history.json and glucose.json in the state directory.
    Returns the same (insulin_deliveries, pump_temp_basal, last_glucose, unfiltered_glucose)
    tuple as load_resume_state(), but without requiring a previousOutputs CSV."""
    pump_history = json.load(open(f"{state_dir}/pump_history.json"))
    glucose_records = load_optional_json(f"{state_dir}/glucose.json") or []

    resume_dt = datetime.fromtimestamp(resume_at_ts, tz=timezone.utc).astimezone()
    cutoff = resume_dt - timedelta(hours=10)

    pump_history = sorted(pump_history, key=lambda e: e["timestamp"])

    # Build temp basal intervals and find any still-active temp at resume_dt
    temp_intervals = []
    pump_temp_basal = None
    for event in pump_history:
        if event.get("type") != "tempBasal":
            continue
        ts = datetime.fromtimestamp(event["timestamp"], tz=timezone.utc).astimezone()
        duration_min = event.get("duration", 30)
        end_ts = ts + timedelta(minutes=duration_min)
        temp_intervals.append((ts, end_ts, event["rate"]))
        if ts <= resume_dt < end_ts:
            remaining = (end_ts - resume_dt).total_seconds() / 60
            pump_temp_basal = {"rate": event["rate"], "remaining_minutes": int(remaining)}

    # Build 5-min basal delivery chunks across the 10-hour window
    insulin_deliveries = []
    chunk = cutoff
    while chunk < resume_dt:
        active_rate = lookup_basal_rate(basal_profile, chunk)
        for start, end, rate in temp_intervals:
            if start <= chunk < end:
                active_rate = rate
                break
        insulin_deliveries.append((chunk, active_rate / 12.0))
        chunk += timedelta(minutes=5)

    # Add SMB boluses
    for event in pump_history:
        if event.get("type") != "smb":
            continue
        ts = datetime.fromtimestamp(event["timestamp"], tz=timezone.utc).astimezone()
        if cutoff <= ts <= resume_dt:
            insulin_deliveries.append((ts, event["amount"]))

    # Last glucose at or before resume_at; fall back to first entry if timestamps don't overlap
    last_glucose = None
    for g in glucose_records:
        if g["timestamp"] <= resume_at_ts:
            last_glucose = g["glucose"]
    if last_glucose is None and glucose_records:
        last_glucose = glucose_records[0]["glucose"]

    return insulin_deliveries, pump_temp_basal, last_glucose, last_glucose


def main():
    args = parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    stop_time = parse_stop_time(args.stopTime)

    if args.i == "humalog":
        model = ExponentialInsulinModel.humalog()
    else:
        model = ExponentialInsulinModel.lyumjev()
    
    is_replay = args.replayState is not None

    state_dir = args.replayState if is_replay else initialize(args.u)
    basal_profile = load_basal_profile(state_dir)
    sensitivities = load_insulin_sensitivities(state_dir)

    insulin_deliveries = []  # list of (datetime, units)
    pump_temp_basal = None

    print("time,glucose,insulin,unfiltered glucose,total insulin action,insulin sensitivity factor,temp basal rate,duration")

    filtered_glucose = None
    prev_t = None

    js_alg = None
    if args.js:
        js_alg = "--js"
    elif args.jsbug:
        js_alg = "--jsbug"
    elif args.jsiobfix:
        js_alg = "--jsiobfix"
    elif args.jsiob_as_fix:
        js_alg = "--jsiob_as_fix"
    elif args.jsiob_as_db_fix:
        js_alg = "--jsiob_as_db_fix"

    if args.a is not None:
        # Replay added glucose trace
        timestamps, glucose, added_glucose_values, glucose_values = load_added_glucose_csv(args.a)
        replay_state_timestamp = load_last_state_glucose_timestamp(state_dir) if is_replay else None
        previous_outputs_timestamp = None
        prev_glucose = -1
        insulin_action = -1
        prev_isf = -1
        previous_step_glucose = None
        simulation_clock_start = None
        if is_replay and args.resumeAt is not None:
            simulation_clock_start = datetime.fromtimestamp(args.resumeAt, tz=timezone.utc).astimezone()
            # Shift tdd.json timestamps so records align with the remapped clock.
            # offset = resumeAt - original anchor (last glucose timestamp in state dir)
            if replay_state_timestamp is not None:
                ts_offset = args.resumeAt - replay_state_timestamp.timestamp()

                tdd_path = f"{state_dir}/tdd.json"
                tdd_records = load_optional_json(tdd_path)
                if tdd_records:
                    for r in tdd_records:
                        if "timestamp" in r:
                            r["timestamp"] = r["timestamp"] + ts_offset
                    with open(tdd_path, "w") as f:
                        json.dump(tdd_records, f)


            (
                insulin_deliveries,
                pump_temp_basal,
                previous_step_glucose,
                filtered_glucose,
            ) = load_resume_state_from_dir(state_dir, args.resumeAt, basal_profile)
        elif is_replay:
            previous_outputs_timestamp = load_last_previous_output_timestamp(args.previousOutputs)
            validate_replay_inputs(replay_state_timestamp, previous_outputs_timestamp)
            (
                insulin_deliveries,
                pump_temp_basal,
                previous_step_glucose,
                filtered_glucose,
            ) = load_resume_state(
                args.previousOutputs,
                replay_state_timestamp
            )
        # When -resumeAt is used, start from the beginning of the CSV.
        # The simulation clock is remapped to resumeAt, so CSV timestamps don't need to align.
        if args.resumeAt is not None:
            resume_timestamp = None
        else:
            resume_timestamp = previous_outputs_timestamp if previous_outputs_timestamp is not None else replay_state_timestamp
        start_step = find_replay_start_index(timestamps, resume_timestamp) if args.previousOutputs else 0

        num_steps = len(timestamps)
        if start_step >= num_steps:
            return

        if is_replay:
            first_step_t = simulation_clock_start if simulation_clock_start is not None else timestamps[start_step]
            glucose, insulin_action, prev_isf = compute_resume_glucose(
                model,
                previous_step_glucose,
                insulin_deliveries,
                sensitivities,
                first_step_t,
                added_glucose_values[start_step]
            )
            prev_glucose = glucose if glucose is not None else -1
        else:
            glucose = glucose_values[start_step]
        stopped_due_to_stop_time = False

        for step in range(start_step, num_steps):
            if simulation_clock_start is not None:
                t = simulation_clock_start + timedelta(minutes=5 * (step - start_step))
            else:
                t = timestamps[step]
            if stop_time is not None and t >= stop_time:
                stopped_due_to_stop_time = True
                break

            algo_glucose = glucose
            if args.f:
                if filtered_glucose is None:
                    filtered_glucose = glucose
                else:
                    delta_minutes = (t - prev_t).total_seconds() / 60.0
                    filtered_glucose = low_pass_filter(glucose, filtered_glucose, delta_minutes)
                algo_glucose = filtered_glucose
            prev_t = t

            t0 = time.time()
            determination = calculate(
                state_dir,
                t.timestamp(),
                algo_glucose,
                js_alg,
                use_timing=args.timing,
                timezone=args.timezone,
                autosens_seconds=args.autosensSeconds,
            )
            elapsed = time.time() - t0
            if args.timing:
                print(f"[timing] step {step} wall: {elapsed*1000:.0f}ms", file=sys.stderr)

            five_min_insulin, pump_temp_basal, active_rate = simulate_step(
                state_dir, basal_profile, t, glucose, pump_temp_basal, determination
            )
            insulin_deliveries.append((t, five_min_insulin))

            duration = 0  if pump_temp_basal is None else pump_temp_basal['remaining_minutes']
            print(f"{t.isoformat()},{glucose:.1f},{five_min_insulin:.4f},{prev_glucose},{insulin_action},{prev_isf},{active_rate},{duration}") 

            if step < num_steps - 1:
                if simulation_clock_start is not None:
                    t_next = simulation_clock_start + timedelta(minutes=5 * (step - start_step + 1))
                else:
                    t_next = timestamps[step + 1]
                isf = lookup_isf(sensitivities, t_next)
                total_insulin_action = compute_insulin_action(model, insulin_deliveries, t_next)
                glucose = max(40, min(400, glucose - total_insulin_action * isf + added_glucose_values[step + 1]))

                prev_glucose = glucose 
                insulin_action = total_insulin_action
                prev_isf = isf

        if stopped_due_to_stop_time:
            alg = 'swift' if js_alg is None else js_alg[2:]
            write_replay_state_directory(state_dir, alg)

    else:
        # Original simulation mode
        t = datetime.now()
        glucose = args.g

        for step in range(args.n):
            algo_glucose = glucose
            if args.f:
                if filtered_glucose is None:
                    filtered_glucose = glucose
                else:
                    delta_minutes = (t - prev_t).total_seconds() / 60.0
                    filtered_glucose = low_pass_filter(glucose, filtered_glucose, delta_minutes)
                algo_glucose = filtered_glucose
            prev_t = t

            t0 = time.time()
            determination = calculate(
                state_dir,
                t.timestamp(),
                algo_glucose,
                js_alg,
                use_timing=args.timing,
                inspect_from=args.inspectStart,
                timezone=args.timezone,
                autosens_seconds=args.autosensSeconds,
            )
            elapsed = time.time() - t0
            if args.timing:
                print(f"[timing] step {step} wall: {elapsed*1000:.0f}ms", file=sys.stderr)

            five_min_insulin, pump_temp_basal, _ = simulate_step(
                state_dir, basal_profile, t, glucose, pump_temp_basal, determination
            )
            insulin_deliveries.append((t, five_min_insulin))

            print(f"{t.isoformat()},{glucose:.1f},{five_min_insulin:.4f}")

            t = t + timedelta(minutes=5)

            scheduled_basal = lookup_basal_rate(basal_profile, t)
            isf = lookup_isf(sensitivities, t)
            basal_glucose = scheduled_basal * isf / 12.0
            total_insulin_action = compute_insulin_action(model, insulin_deliveries, t)

            glucose = max(40, min(400, glucose - total_insulin_action * isf + basal_glucose))


if __name__ == "__main__":
    main()
