import json
import argparse
import sys


def detect_function_type(entries):
    """Detect which function type based on the keys present in the first non-error entry."""
    for entry in entries:
        if entry.get('error'):
            continue
        if 'swiftRatio' in entry:
            return 'autosens'
        if 'swiftUnits' in entry or 'swiftRate' in entry:
            return 'determineBasal'
        if 'swiftIob' in entry:
            return 'iob'
        if 'swiftCarbs' in entry:
            return 'meal'
    return 'unknown'


# Each function type defines: a list of (field_label, swift_key, js_key) tuples
FIELD_SPECS = {
    'determineBasal': [
        ('units', 'swiftUnits', 'jsUnits'),
        ('rate', 'swiftRate', 'jsRate'),
        ('duration', 'swiftDuration', 'jsDuration'),
    ],
    'autosens': [
        ('ratio', 'swiftRatio', 'jsRatio'),
    ],
    'iob': [
        ('iob', 'swiftIob', 'jsIob'),
        ('activity', 'swiftActivity', 'jsActivity'),
    ],
    'meal': [
        ('carbs', 'swiftCarbs', 'jsCarbs'),
        ('mealCOB', 'swiftMealCOB', 'jsMealCOB'),
    ],
}

# Fuzzy match thresholds from OrefFunction.swift approximateMatchingNumbers()
THRESHOLDS = {
    'determineBasal': {},
    'autosens': {
        'ratio': 0.021,
    },
    'iob': {
        'iob': 0.1,
        'activity': 0.01,
    },
    'meal': {
        'carbs': 0.1,
        'mealCOB': 10,
    },
}


def analyze(entries, function_type):
    fields = FIELD_SPECS.get(function_type)
    if not fields:
        print(f"Unknown function type: {function_type}")
        sys.exit(1)

    matches = 0
    mismatches = 0
    errors = 0
    mismatch_details = []

    for entry in entries:
        if entry.get('error'):
            errors += 1
            continue

        is_match = all(entry.get(sk) == entry.get(jk) for _, sk, jk in fields)

        if is_match:
            matches += 1
        else:
            mismatches += 1
            mismatch_details.append(entry)

    total = len(entries)
    print(f"Function type: {function_type}")
    print(f"Total entries: {total}")
    print(f"  Matches:    {matches}")
    print(f"  Mismatches: {mismatches}")
    print(f"  Errors:     {errors}")

    thresholds = THRESHOLDS.get(function_type, {})

    if mismatches > 0:
        print(f"\nPer-field statistics:")
        for label, sk, jk in fields:
            deltas = []
            for entry in mismatch_details:
                s = entry.get(sk)
                j = entry.get(jk)
                if s is not None and j is not None:
                    deltas.append(abs(float(s) - float(j)))
            if not deltas:
                print(f"  {label}: no comparable values")
                continue
            deltas.sort()
            mean = sum(deltas) / len(deltas)
            median = deltas[len(deltas) // 2]
            threshold = thresholds.get(label)
            within = sum(1 for d in deltas if threshold and d <= threshold)
            beyond = len(deltas) - within if threshold else len(deltas)
            print(f"  {label} ({len(deltas)} differ):")
            print(f"    Min:    {min(deltas):.4f}")
            print(f"    Max:    {max(deltas):.4f}")
            print(f"    Mean:   {mean:.4f}")
            print(f"    Median: {median:.4f}")
            if threshold:
                print(f"    Within threshold ({threshold}): {within}")
                print(f"    Beyond threshold ({threshold}): {beyond}")

        # Find the 3 worst mismatched entries
        ranked = []
        for entry in mismatch_details:
            max_delta = 0
            max_exceedance = 0
            for label, sk, jk in fields:
                s = entry.get(sk)
                j = entry.get(jk)
                if s is not None and j is not None:
                    delta = abs(float(s) - float(j))
                    max_delta = max(max_delta, delta)
                    threshold = thresholds.get(label)
                    if threshold and delta > threshold:
                        max_exceedance = max(max_exceedance, delta - threshold)
            if max_delta > 0:
                ranked.append((max_exceedance, max_delta, entry))

        if ranked:
            if thresholds:
                # Sort by exceedance beyond threshold first, then by raw delta
                ranked.sort(key=lambda x: (x[0], x[1]), reverse=True)
                top_n = ranked[:3]
                print(f"\nTop {len(top_n)} entries exceeding threshold the most:")
                for i, (exceedance, delta, entry) in enumerate(top_n, 1):
                    print(f"\n  #{i} (exceeds threshold by {exceedance:.4f}):")
                    print(f"    {json.dumps(entry, indent=6)}")
            else:
                # No thresholds (e.g. determineBasal) — show top 3 per field
                for label, sk, jk in fields:
                    per_field = []
                    for entry in mismatch_details:
                        s = entry.get(sk)
                        j = entry.get(jk)
                        if s is not None and j is not None:
                            delta = abs(float(s) - float(j))
                            if delta > 0:
                                per_field.append((delta, entry))
                    if not per_field:
                        continue
                    per_field.sort(key=lambda x: x[0], reverse=True)
                    top_n = per_field[:3]
                    print(f"\nTop {len(top_n)} largest {label} mismatches:")
                    for i, (delta, entry) in enumerate(top_n, 1):
                        print(f"\n  #{i} (delta {delta:.4f}):")
                        print(f"    {json.dumps(entry, indent=6)}")


def main():
    parser = argparse.ArgumentParser(description="Analyze output comparison results.")
    parser.add_argument("file", help="Path to the output_compare JSON file")
    args = parser.parse_args()

    with open(args.file, 'r') as f:
        entries = json.load(f)

    function_type = detect_function_type(entries)
    analyze(entries, function_type)


if __name__ == "__main__":
    main()
