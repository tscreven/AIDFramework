#!/bin/bash
set -e

WORKSPACE="Trio.xcworkspace"
SCHEME="Trio Tests"
DERIVED_DATA="./DerivedDataTesting"
SIMULATOR_ID="2434464A-90F3-479B-AB5E-F8432C12D0D2"  # iPhone 16 (iOS 18.2)

# Build
xcodebuild build-for-testing \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA"

# Run autosens test
xcodebuild test-without-building \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing "TrioTests/AutosensCliTests"
