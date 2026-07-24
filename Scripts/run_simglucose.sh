#!/bin/bash

set -euo pipefail
readonly PARALLELISM=1
swift build -c release

run_user() {
    local user="$1"

    mkdir -p simglucoseResults/${user}

    echo "starting Swift oref simulation on ${user}"
    python3 simglucose/run_sim.py -u ${user} -d 14 -scen MealScenarios/${user}/scenario.npy -fn simglucoseResults/${user}/swift.csv

    echo "starting original JavaScript oref simulation on ${user}"
    python3 simglucose/run_sim.py -u ${user} -d 14 -a jsbug -scen MealScenarios/${user}/scenario.npy -fn simglucoseResults/${user}/jsbug.csv

    echo "finished ${user} simulations"
}

export -f run_user
users=( "child001" "child002" "child003" "child004" "child005" "child006" "child007" "child008" "child009" "child010" "adolescent001" "adolescent002" "adolescent003" "adolescent004" "adolescent005" "adolescent006" "adolescent007" "adolescent008" "adolescent009" "adolescent010" "adult001" "adult002" "adult003" "adult004" "adult005" "adult006" "adult007" "adult008" "adult009" "adult010" )
printf '%s\0' "${users[@]}" | xargs -0 -n 1 -P "${PARALLELISM}" bash -lc 'run_user "$1"' _