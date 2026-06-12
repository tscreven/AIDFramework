#!/bin/bash

set -euo pipefail
readonly PARALLELISM=10
swift build -c release

run_user() {
    local user="$1"

    mkdir simglucoseResults/${user}

    python3 simglucose/run_sim.py -u ${user} -scen MealScenarios/${user}/scenario.npy -fn simglucoseResults/${user}/fixed_hourScen.csv
    python3 simglucose/run_sim.py -u ${user} -a jsbug -scen MealScenarios/${user}/scenario.npy -fn simglucoseResults/${user}/jsbug_hourScen.csv
    echo "finished ${user}"
}

export -f run_user
users=( "child005" "child002" "adolescent007" "adolescent009" "child003" "child004" "adolescent008" "adolescent006" "adolescent001" "adult006" "adult001" "adult008" "child010" "adult009" "adult007" "adolescent004" "adolescent003" "adult010" "child008" "child001" "child006" "adolescent002" "adolescent005" "child007" "child009" "adult002" "adult005" "adolescent010" "adult004" "adult003" )
printf '%s\0' "${users[@]}" | xargs -0 -n 1 -P "${PARALLELISM}" bash -lc 'run_user "$1"' _