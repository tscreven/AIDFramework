#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACES_DIR="$PROJECT_DIR/traces"
VIRTUAL_USERS_DIR="$PROJECT_DIR/VirtualUsers"
ADDED_GLUCOSE_DIR="$PROJECT_DIR/added_glucose"
CREATE_SCRIPT="$PROJECT_DIR/SimpleSim/create_added_glucose.py"

for user_dir in "$TRACES_DIR"/*/; do
    user_id="$(basename "$user_dir")"

    # Ensure corresponding VirtualUsers directory exists
    if [ ! -d "$VIRTUAL_USERS_DIR/$user_id" ]; then
        echo "WARNING: No VirtualUsers directory for $user_id, skipping."
        continue
    fi

    # Skip if added_glucose already generated for this user
    # if [ -d "$ADDED_GLUCOSE_DIR/$user_id" ]; then
    #     echo "SKIP: added_glucose already exists for $user_id"
    #     continue
    # fi

    # Create output directory
    mkdir -p "$ADDED_GLUCOSE_DIR/$user_id"

    for json_file in "$user_dir"t1d_data_*.json; do
        [ -f "$json_file" ] || continue

        # Extract time range from filename: t1d_data_<time_range>.json -> <time_range>
        basename_json="$(basename "$json_file")"
        time_range="${basename_json#t1d_data_}"
        time_range="${time_range%.json}"

        output_file="$ADDED_GLUCOSE_DIR/$user_id/added_glucose_${time_range}.csv"

        if [ -f "$output_file" ]; then
            echo "SKIP: $output_file already exists, skipping."
            continue
        fi

        echo "Processing $user_id / $basename_json ..."
        if python "$CREATE_SCRIPT" \
            -u "$VIRTUAL_USERS_DIR/$user_id" \
            -i "$json_file" \
            > "$output_file"; then
            echo "  -> $output_file"
        else
            echo "ERROR: Failed to generate added glucose for $user_id / $basename_json" >&2
            rm -f "$output_file"
        fi
    done
done

echo "Done."
