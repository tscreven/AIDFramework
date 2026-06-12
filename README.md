# Using the OrefSwiftCLI

This guide walks through how to build and use the OrefSwiftCLI tool,
both for running individual algorithm functions and for running
simulations.

## Building

From the `OrefSwiftCLI/` directory:

```bash
cd OrefSwiftCLI
swift build
```

For a release build:

```bash
swift build -c release
```

## Running

You can run the tool with `swift run` or directly via the built binary:

```bash
swift run oref-swift <subcommand> [options]
# or
.build/debug/oref-swift <subcommand> [options]
```

Use `--help` to see available subcommands:

```bash
swift run oref-swift --help
```

## Simulation commands

The simulation commands let you run the algorithm over a series of
glucose readings, maintaining state between calls. This is useful for
testing how the algorithm behaves over time.

### Workflow overview

A simulation session follows three steps:

1. **Initialize** a session for a virtual user
2. **Calculate** insulin dosing for each new glucose reading (repeated)
3. Optionally call **stepUpdate** between calculations

### Step 1: Initialize a session

The `initialize` command creates a new simulation session from a
virtual user directory. The virtual user directory must contain therapy
settings files: `preferences.json`, `settings.json`, `bg_targets.json`,
`basal_profile.json`, `insulin_sensitivities.json`, `carb_ratios.json`,
and `temptargets.json`.

```bash
swift run oref-swift initialize \
  -u VirtualUsers/sam \
  -o init_output.json
```

This creates a state directory (e.g., `state/sam_20260213_100000/`) and
returns its path in the output:

```json
{"stateDir":"state/sam_20260213_100000"}
```

Save this path -- you'll pass it to all subsequent commands.

### Step 2: Calculate insulin dosing

The `calculate` command takes a new glucose reading and timestamp,
runs the full algorithm pipeline (makeProfile, iob, meal, autosens,
determineBasal), and returns an insulin dosing determination.

Create an input file with the glucose reading:

```json
{"timestamp": 1707800400, "glucose": 120}
```

Where `timestamp` is a Unix timestamp in seconds and `glucose` is in
mg/dL.

Run the calculation:

```bash
swift run oref-swift calculate \
  -s state/sam_20260213_100000 \
  -i glucose_reading.json \
  -o determination.json
```

The output is a Determination JSON object containing the algorithm's
dosing recommendation (temp basal rate, duration, SMB units, etc.).

**Important:** The algorithm is unaware of the fact that it's being
simulated, so it returns a raw oref determination as a JSON
object. From here, the simulator needs to infer insulin delivery.
- Bolus: Specified by the `units` property. If present, defines the
  number of units to deliver immediately.
- Basal: Specified by the `rate` and `duration` properties. If
  present, defines the pump's ongoing basal delivery rate and the
  duration of the temporary basal rate.

If the algorithm returns a determination where `rate` and `duration`
are nil or omitted, that means it is _not_ making any adjustments to
the basal rate -- the previous TempBasal command will continue to run.
Setting `rate=0` with `duration=0` cancels any ongoing TempBasal
commands, reverting the pump back to its scheduled basal rate. Setting
`rate=0` with `duration > 0` is a zero temp basal -- it shuts off
basal insulin delivery for the specified duration.

Each call to `calculate` updates the state directory with:
- The new glucose reading appended to `glucose.json`
- Any recommended pump events appended to `pump_history.json`
- Updated `autosens.json` (recalculated every 30 simulated minutes
  once enough data is available)
- Regenerated `profile.json`

### Running multiple cycles

To simulate a series of glucose readings, call `calculate` repeatedly
with incrementing timestamps (typically 5 minutes apart):

```bash
# First reading
echo '{"timestamp": 1707800400, "glucose": 120}' | \
  swift run oref-swift calculate -s state/sam_20260213_100000 -i - -o -

# 5 minutes later
echo '{"timestamp": 1707800700, "glucose": 125}' | \
  swift run oref-swift calculate -s state/sam_20260213_100000 -i - -o -

# 10 minutes later
echo '{"timestamp": 1707801000, "glucose": 130}' | \
  swift run oref-swift calculate -s state/sam_20260213_100000 -i - -o -
```

### Step 3: stepUpdate (optional)

The `stepUpdate` command is a placeholder for future use by the
broader simulation framework. It is currently a no-op.

```bash
swift run oref-swift stepUpdate -i step_input.json -o -
```

## Inspecting simulation state

Because all state files are persisted as JSON in the state directory,
you can inspect them at any point during a simulation:

```bash
# See all glucose readings recorded so far
cat state/sam_20260213_100000/glucose.json | python3 -m json.tool

# See pump history (temp basals and SMBs)
cat state/sam_20260213_100000/pump_history.json | python3 -m json.tool

# See the current profile
cat state/sam_20260213_100000/profile.json | python3 -m json.tool

# See autosens state
cat state/sam_20260213_100000/autosens.json | python3 -m json.tool

# See TDD records
cat state/sam_20260213_100000/tdd.json | python3 -m json.tool
```

## Virtual users

Virtual user directories live in `OrefSwiftCLI/VirtualUsers/`. Each
subdirectory represents a user with their own therapy settings. For
example, the `sam` virtual user:

```
OrefSwiftCLI/VirtualUsers/sam/
  preferences.json
  settings.json
  bg_targets.json
  basal_profile.json
  insulin_sensitivities.json
  carb_ratios.json
  temptargets.json
```

These files are typically copied from a Trio install that exposes
settings via the local file system on a device. To create a new
virtual user, create a new directory under `VirtualUsers/` with the
required JSON files.

## Basic algorithm commands

These commands run individual algorithm functions. Each takes a JSON
input file (`-i`) and writes the result to an output file (`-o`). Use
`-` for STDIN or STDOUT.

### makeProfile

Generates an OpenAPS profile from therapy settings.

```bash
swift run oref-swift makeProfile -i make_profile_input.json -o profile.json
```

The input JSON must contain: `preferences`, `pumpSettings`, `bgTargets`,
`basalProfile`, `isf`, `carbRatios`, `tempTargets`, `model`,
`trioSettings`, and `clock`.

### iob

Calculates insulin on board from pump history.

```bash
swift run oref-swift iob -i iob_input.json -o iob_output.json
```

### meal

Calculates meal data including carbs on board (COB).

```bash
swift run oref-swift meal -i meal_input.json -o meal_output.json
```

### autosens

Calculates the autosensitivity ratio.

```bash
swift run oref-swift autosens -i autosens_input.json -o autosens_output.json
```

### determineBasal

Determines basal rate adjustments based on current state.

```bash
swift run oref-swift determineBasal -i determine_basal_input.json -o -
```

### Piping with STDIN/STDOUT

All commands support `-` for STDIN and STDOUT:

```bash
cat input.json | swift run oref-swift iob -i - -o -
```
