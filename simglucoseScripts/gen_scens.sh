#!/bin/bash

users=( "child005" "child002" "adolescent007" "adolescent009" "child003" "child004" "adolescent008" "adolescent006" "adolescent001" "adult006" "adult001" "adult008" "child010" "adult009" "adult007" "adolescent004" "adolescent003" "adult010" "child008" "child001" "child006" "adolescent002" "adolescent005" "child007" "child009" "adult002" "adult005" "adolescent010" "adult004" "adult003" )
file_name="scenario.npy"

for user in "${users[@]}"; do
    python3 simglucose/gen_meal_scenario.py -d 14 -fp MealScenarios/${user}/${file_name}
    echo finished ${user}
done