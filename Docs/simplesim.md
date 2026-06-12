# SimpleSim

This is an extremely simple Python simulator that simulates virtual
humans using the OrefSwiftCLI algorithm.

The simulator takes the following arguments:

  - u: virtual user (e.g., VirtualUsers/sam)
  - i: insulin type (either "humalog" or "lyumjev")
  - f: low pass filtering on glucose enabled (optional)
  - g: initial glucose concentration in mg/dl
  - n: number of 5m steps of the simulation

Alternatively, the simulator can replay a trace of added glucose
values (similar in concept to "deviations" from oref) with the
following arguments:

  - u: virtual user (e.g., VirtualUsers/sam)
  - i: insulin type (either "humalog" or "lyumjev")
  - f: low pass filtering on glucose enabled (optional)
  - a: added glucose CSV file

## Algorithm

The simulation start by calling the `initiate` OrefSwiftCLI
function. Once that returns, it uses the simulation directory to fetch
(1) the insulin sensitivity schedule and (2) the basal rate schedule.

After the simulation has started it will advance the simulation state
starting at the current time and the given initial glucose
concentration. It feeds this information to the `calculate`
OrefSwiftCLI function to get the insulin dosing information. From the
insulin dosing information, it will:

  - Update `pump_temp_basal` — the temp basal currently programmed on
    the pump. This tracks `{rate, remaining_minutes}`. When the
    algorithm sets a new `rate` + `duration`, `pump_temp_basal` is
    updated. When `rate=0` and `duration=0`, the temp basal is
    cancelled (reverts to scheduled basal). When `rate=0` and
    `duration > 0`, it is a zero temp basal that shuts off basal
    delivery for that duration. When `rate` and `duration` are absent,
    the existing `pump_temp_basal` continues. Each step decrements
    `remaining_minutes` by 5; when expired, it reverts to scheduled
    basal.
  - Calculate the total insulin delivery for the next 5 minutes. This
    is the sum of any SMB bolus (`units`) plus the active pump basal
    rate divided by 12. The active pump basal rate comes from
    `pump_temp_basal` if one is active, otherwise from the scheduled
    basal profile.

Next, it increments the timestemp to t += 5 minutes and calculates the
next glucose concentration. For this calculation we need to know:

  - 5 minute basal glucose = basalRate * insulinSensitivity / 12

  - 5 total insulin action = sum of all insulin action from the last 10 hours

To calculate insulin action you can use this algorithm:

```python
model = ExponentialInsulinModel.lyumjev() # or humalog depending on the insulin type
for each insulin in insulinFromTheLast10Hours:
    tMinusOne = t - 5 minutes
    pctAtTMinusOne = model.precent_effect_remaining(tMinusOne - insulin.time)
    pctAtT = model.percent_effect_remaining(t - insulin.time)
    insulinAction = (pctAtTMinusOne - pctAtT) * insulin.units
```

then:

  - glucose = glucose - insulinAction * insulinSensitivity + basalInsulin

and the cycle repeats for `n` cycles

### Low pass filtering glucose values

If the user passes in the `-f` flag on the command line, simplesim
will apply low pass filtering to glucose values before passing them to
the algorithm. These filtered values are only passed to the algorithm,
for any other use of glucose values, like in outputs, simplesim will
use the unfiltered value.

We designed the low pass filter to smooth G7 CGM high frequency
noise. Our filter matches the noise characteristics of the G6, adds a
7.00 minute delay relative to the unfiltered G7 sensor readings, but
is still 3.75 minutes ahead of the G6.

The optimal time-aware IIR low-pass filter is:
```
y[n] = alpha * x[n] + (1 - alpha) * y[n-1]
alpha = 1 - exp(-Δt / tau)
tau = 11.3 minutes
```

Where `y` is the filtered CGM reading, `x` is the raw CGM reading,
`Δt` is the time since the last reading, and `tau` is the filter's
time constant.

## Replaying added glucose traces

If a user specifies an added glucose log on the command line, the
simulator can replay this trace. To simulate added glucose traces, the
simulation state updates still use the same insulin action calculation
but gets the initial glucose value, timestamps, and added glucose from
the logs. To use these values the new glucose update equation looks
like this:

```python
glucose = glucose - insulinAction * insulinSensitivity + addedGlucose
```

Note: Timestamps should be converted to the local timezone for
simulation to ensure we get the correct algorithm settings.

The CSV files have the following format:

timestamp | glucose | insulinAction | addedGlucose

Where the insulinAction value is ignored and only the first glucose
value is used.

## Profiling

Pass `--timing` to print per-step timing breakdowns to stderr:

```bash
python3 SimpleSim/simplesim.py -u VirtualUsers/sam -i humalog -g 120 -n 100 --timing
```

This prints wall-clock time for each simulation step plus an internal
breakdown from the Swift `calculate` command (storeGlucose, makeProfile,
fetchData, tdd, autosens, iob, meal, determineBasal, etc.). CSV output
goes to stdout as normal, so you can separate them:

```bash
python3 SimpleSim/simplesim.py -u VirtualUsers/sam -i humalog -g 120 -n 100 --timing > output.csv
```

## Outputs

The output is a csv file with time | glucose | insulin fields