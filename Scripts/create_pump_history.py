#!/usr/bin/env python3
"""Convert history.json into pump history format.

Pairs TempBasalDuration with TempBasal by '_' + id (or timestamp as fallback).
Uses isSMB to distinguish SMB boluses from regular boluses.

Usage:
    python3 Scripts/create_pump_history.py <history.json> [output.json]
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def to_unix(timestamp) -> float:
    """Convert timestamp to Unix seconds float, handling both ISO8601 strings and numbers."""
    if isinstance(timestamp, (int, float)):
        return float(timestamp)
    # ISO8601 string
    dt = datetime.fromisoformat(str(timestamp).replace('Z', '+00:00'))
    return dt.timestamp()


def convert(history: list[dict]) -> list[dict]:
    durations: dict[str, int] = {}   # TempBasalDuration id -> duration_min
    ts_durations: dict[float, int] = {}  # timestamp -> duration_min (fallback)

    for entry in history:
        if entry.get("_type") == "TempBasalDuration":
            durations[entry["id"]] = entry["duration (min)"]
            ts_durations[to_unix(entry["timestamp"])] = entry["duration (min)"]

    pump_history = []
    for entry in history:
        t = entry.get("_type")

        if t == "TempBasal":
            raw_id = entry["id"]  # e.g. "_66C281F9-..."
            base_id = raw_id.lstrip("_")
            ts = to_unix(entry["timestamp"])
            duration = durations.get(base_id) or ts_durations.get(ts)

            pump_history.append({
                "type": "tempBasal",
                "rate": entry["rate"],
                "timestamp": ts,
                "id": base_id,
                "duration": duration,
            })

        elif t == "Bolus":
            pump_history.append({
                "type": "smb",
                "amount": entry["amount"],
                "timestamp": to_unix(entry["timestamp"]),
                "id": entry["id"],
            })

        elif t == "PumpResume":
            pump_history.append({
                "type": "pumpResume",
                "timestamp": to_unix(entry["timestamp"]),
                "id": entry["id"],
            })

        elif t == "PumpSuspend":
            pump_history.append({
                "type": "pumpSuspend",
                "timestamp": to_unix(entry["timestamp"]),
                "id": entry["id"],
            })

    pump_history.sort(key=lambda x: x["timestamp"])
    return pump_history


def main():
    if len(sys.argv) < 2:
        print("Usage: create_pump_history.py <history.json> [output.json]")
        sys.exit(1)

    history_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("pump_history.json")

    with open(history_path) as f:
        history = json.load(f)

    pump_history = convert(history)

    with open(output_path, "w") as f:
        json.dump(pump_history, f, indent=4)

    print(f"Wrote {len(pump_history)} entries to {output_path.resolve()}")


if __name__ == "__main__":
    main()
