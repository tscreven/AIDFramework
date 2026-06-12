# Create added glucose

Create added glucose is a python script located at
@SimpleSim/create_added_glucose.py for converting insulin and glucose
timeseries data into a timeseries of addedGlucose.

On the command line, this script needs to take arguments for:

  -u: virtual user (e.g., VirtualUsers/sam)

  -i: insulin and glucose json file

## Inputs

The input is a JSON array that has either glucose or insulin entries.

Glucose entries look like:

```json
  {
    "date" : "2026-02-14T03:38:59Z",
    "type" : "glucose",
    "unit" : "mg\/dL",
    "value" : 73
  }
```

and insulin entries look like:

```json
  {
    "date" : "2026-02-14T02:45:13Z",
    "deliveryReason" : "bolus",
    "type" : "insulin",
    "unit" : "U",
    "value" : 4
  }
```

## Preprocessing the data

To preprocess the data, we need to separate glucose and insulin
entries and align them to the closest 5m boundary.

  - if there are multiple glucose entries at the same 5m boundary,
    average them

  - if there are multiple insulin entries at the same 5m boundary, sum
    them

If there are any missing glucose data entries in the aligned glucose
data, use linear interpolation to fill in the gaps. If any gaps are
greater than 30m, print an error and exit the script.

## Physiological data

From the virtual user directory passed in via the command line, read
in and store in memory the:

  - insulin_sensitivities.json: contains the insulin sensitivity
    schedule for the user

As the algorithm run, you use these schedules to lookup the insulin
sensitivity.

Also, there is a exponential_insulin_model.py file that you can use
for calculating insulin action. See the @Docs/simplesim.md file for
more details on how to calculate insulin action.

## Added glucose

To calculate added glucose assuming index i:

deltaGlucose = glucose[i] - glucose[i-1]
insulinAction = # do this for t[i-1] -> t[i]

addedGlucose = deltaGlucose + insulinAction * insulinSensitivity

the first addedGlucose value is 0 so that the addedGlucose array is
the same length as the glucose array.

## Output

The output is a CSV file with time | glucose | insulinAction | addedGlucose