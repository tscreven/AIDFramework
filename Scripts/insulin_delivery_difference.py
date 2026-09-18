import statistics

import pandas as pd
from pathlib import Path

ROWS_PER_HOUR = 12  # each CSV row is 5 minutes apart


def insulin_delivery_difference(buggy_csv, fixed_csv, window_hours=None):
    """Return the percent difference in insulin delivered between two simulation outputs.

    With window_hours=None the whole file is compared. Otherwise only the first
    window_hours of each file (from the start of the CSV) are summed. The difference
    is |fixed - buggy| relative to buggy; NaN is returned if buggy delivered zero insulin.
    """
    insulin_buggy = pd.read_csv(buggy_csv)['insulin']
    insulin_fixed = pd.read_csv(fixed_csv)['insulin']

    if window_hours is not None:
        window_rows = int(window_hours * ROWS_PER_HOUR)
        insulin_buggy = insulin_buggy.iloc[:window_rows]
        insulin_fixed = insulin_fixed.iloc[:window_rows]

    sum_buggy = insulin_buggy.sum()
    sum_fixed = insulin_fixed.sum()
    if sum_buggy == 0:
        return float("nan")
    return abs(sum_fixed - sum_buggy) / sum_buggy * 100


def report_insulin_delivery_differences(root_dir, window_hours=6):
    """Compare every buggy/fixed CSV pair under root_dir/simOut_* and print summary stats.

    For each pair two numbers are computed: the whole-file (24 h) difference and the
    difference over the first window_hours of the file.
    """
    root_dir = Path(root_dir)
    simOut_dirs = sorted(root_dir.glob("simOut_*"))

    results = []  # (diff_24h, diff_window, buggy_csv, fixed_csv)

    for simout in simOut_dirs:
        for buggy_csv in sorted((simout / "buggy").glob("*.csv")):
            fixed_csv = simout / "fixed" / buggy_csv.name
            if not fixed_csv.exists():
                print(f"warning: no fixed counterpart for {buggy_csv}")
                continue

            diff_24h = insulin_delivery_difference(buggy_csv, fixed_csv)
            diff_win = insulin_delivery_difference(buggy_csv, fixed_csv, window_hours)
            results.append((diff_24h, diff_win, buggy_csv, fixed_csv))

    if not results:
        print(f"no CSV pairs found under {root_dir}")
        return results

    diffs_24h = [r[0] for r in results]
    diffs_win = [r[1] for r in results]
    max_24h = max(results, key=lambda r: r[0])
    max_win = max(results, key=lambda r: r[1])

    def fmt(x):
        return f"{x:.3f} %"

    rows = [
        ("Pairs compared", f"{len(results)}", ""),
        ("Max diff", fmt(max_24h[0]), fmt(max_win[1])),
        ("Median diff", fmt(statistics.median(diffs_24h)), fmt(statistics.median(diffs_win))),
        ("Mean diff", fmt(statistics.mean(diffs_24h)), fmt(statistics.mean(diffs_win))),
    ]
    headers = ("", "24 h total", f"{window_hours} h window")
    widths = [max(len(str(r[i])) for r in rows + [headers]) for i in range(3)]
    border = "+-" + "-+-".join("-" * w for w in widths) + "-+"

    print(f"Insulin delivery difference (buggy vs fixed) in {root_dir}")
    print(border)
    print(f"| {headers[0]:<{widths[0]}} | {headers[1]:>{widths[1]}} | {headers[2]:>{widths[2]}} |")
    print(border)
    for label, v24, vwin in rows:
        print(f"| {label:<{widths[0]}} | {v24:>{widths[1]}} | {vwin:>{widths[2]}} |")
    print(border)
    print()
    print("Max 24 h diff pair:")
    print(f"  buggy: {max_24h[2]}")
    print(f"  fixed: {max_24h[3]}")
    print()
    print(f"Max {window_hours} h window diff pair:")
    print(f"  buggy: {max_win[2]}")
    print(f"  fixed: {max_win[3]}")

    return results


if __name__ == "__main__":
    window_hours = 12
    report_insulin_delivery_differences("autosensBugInvoke", window_hours)
    report_insulin_delivery_differences("iobBugInvoke", window_hours)
