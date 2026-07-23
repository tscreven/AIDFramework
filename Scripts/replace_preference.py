#!/usr/bin/env python3
"""Replace keys in preference.json with values from profile.json where keys match."""

import json
import sys
from pathlib import Path

def replace(preferences, profile):
    changes = []
    for key in preferences:
        if key in profile:
            old_val = preferences[key]
            new_val = profile[key]
            if old_val != new_val:
                changes.append((key, old_val, new_val))
                preferences[key] = new_val
    return changes, preferences


def main():
    if len(sys.argv) != 3:
        print("Usage: replace_preference.py <preference.json> <profile.json>")
        sys.exit(1)

    pref_path = Path(sys.argv[1])
    profile_path = Path(sys.argv[2])

    with open(pref_path) as f:
        preferences = json.load(f)

    with open(profile_path) as f:
        profile = json.load(f)

    changes, preferences = replace(preferences, profile)

    output_path = Path("preferences.json")
    with open(output_path, "w") as f:
        json.dump(preferences, f, indent=2)

    if changes:
        for key, old_val, new_val in changes:
            print(f"{key}: {old_val} -> {new_val}")
    else:
        print("No changes made.")

    print(f"\nSaved to {output_path.resolve()}")


if __name__ == "__main__":
    main()
