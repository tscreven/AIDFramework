# Run Trio Oref Algorithm in Simulator

Read [README.md](README.md) from original `simglucose` repo for general information on `simglucose`. 

This file provides instructions on how to simulate the Trio oref algorithm through `simglucose` on virtual patients, explains how Trio's oref algorithm is looped into the simulator's controller policy, and explains changes/additions to the `simglucose` codebase.

## Outline
1. Bash commands
    * [Create meal scenario](#create-meal-scenario)
    * [Run simulator](#run-simulator)
2. [Oref Algorithm Integration Explanation](#trio-oref-algorithm-integration-in-simglucose)
2. [Codebase Changes](#edits-to-existing-codebase)

## Bash Commands

Commands assume they're executed from filepath location: `~/TrioOrefCLI`. 

### Create Meal Scenario
You do not have to pre-compute a meal scenario to runthe  simulator. However, if a meal scenario is not given to simulator runner, it will randomly generate one. Create and input a meal scenario for reproducability.

**Instructions for manually creating a meal scenario:** the scenario is expected as a `numpy` matrix of size (N, 2) where N = number of meals in the scenario. First column is the number of simulation steps since the simulation started. Another way to think about it is the number of CGM readings since the simulation started; there is one cgm reading for every simualtion step.

The step index the step count since the first step in the simulation, meaning a meal at the first simulation step occurs at reading number zero. For example, a meal at the 12th step means a meal one hour into the simulation. The second column is the carbohydrate amount. For example, a row of [355, 20] means 20 grams of carbohydrates were consumed at the 356th CGM reading (zero-based indexing). Meal scenario files need to be saved as a `.npy` file.

**Instructions for programatically creating a meal scenario:**

The follwing command invokes a Python script which generates a random meal scenario given certain constraints around the length of the scenario, the meal size, and meal timing.

```
python3 simglucose/gen_meal_scenario.py -d <days> -ps <p_snack> -bk <breakfast> -ln <lunch> -dn <dinner> -sn <snack> -mr <meal_range> -fp <filepath>
```
* `days`: Number of days to create scenario for
* `p_snack`: **Optional argument**. Probability of a snack occuring in a day. Valid values = [0,1]. Default value = 0.5.
* `breakfast`: **Optional argument**. Mean breakfast carbohydrate amount. Default value = 60.
* `lunch`: **Optional argument**. Mean lunch carbohydrate amount. Default value = 60.
* `dinner`: **Optional argument**. Mean dinner carbohydrate amount. Default value = 50.
* `snack`: **Optional argument**. Mean snack carbohydrate amount. Default value = 20.
* `meal_range`: **Optional argument**. Percent allowed variation from mean carbohydrate amount in a meal. Valid values = [0,1]. Default value = 0.1.
* `filepath`: Filepath to .npy file where scenario matrix will be saved.

</br>

`gen_meal_scenario.py` scenario rules: 
1. Each day, virtual patient eats breakfast, lunch, and dinner within a range of times with the mean meal time +/- 30 minutes of range.
    * Mean meal times: breakfast = 8:30, lunch = 13:00, dinner = 19:00. Change times in `generate_scenario()`.
2. Within these meal ranges, each minute has an equal chance of being selected,
3. Size of meal randomly selected from range. $mealMean$ = mean possible carbohydrate amount for a meal. $mealRange$ = percent allowed variation from $mealMean$ in range; $mealRange$ = [0,1]. Lowerbound of range = $mealMean$ - $mealRange$ * $mealMean$. Upperbound of range = $mealMean$ + $mealRange$ * $mealMean$.
4. If a snack occurs, equal probability of it happening at the midway point between breakfast and lunch, and lunch and dinner. Size of snack determined same way as other meals.


### Run Simulator
Run `simglucose` using Trio oref controller. 
```
python3 simglucose/run_sim.py -u <virtual_patient> -a <alg_name> -d <days> -scen <meal_scenario_path> -fn <results_file> --log
```
* `virtual_patient`: Name of virtual patient. Valid patient names are age group followed by three digits. Age groups = [child, adolescent, adult]. Valid digits = [001, 002, 003, 004, 005, 006, 007, 008, 009, 010]
    * eg. adolescent002 or adult010
* `alg_name`: Optinal argument. Name of Javascript oref algorithm variant to run instead of Swift algorithm. Possible algorithms
    * `jsbug`: Original Javascript implementation.
    * `jsiobfix`: Javascript implementation with IOB bug fixes.
    * `jsiob_as_fix`: Javascript implementation with IOB and Autosens bug fixes.
    * `js`: Javascript implementation of bug-free Swift oref algorithm. Only run this algorithm for logging purposes because it is equivalent to Swift implementation and it is slower.
* `days`: Number of days simulation runs (must be whole number)
* `meal_scenario_pat`h`: **Optional argument**. Filepath to precomputed .npy file containing meal scenario.
* `results_file`: Filepath to .csv file where outputs will be written to.
* `--log`: Optional flag to print logs of variables which can potentially cause precision errors.

## Trio Oref Algorithm Integration in `simglucose`
A controller (`simglucose/controller/trio_ctrller.py`) initialzes a simulation state for the oref algorithm. The oref algorithm uses this simulation state to track the last 24 hours of self-managed time-series data to decide the amount of insulin to deliver at the current timestep.

The oref algorithm uses unique physiological parameters for each virtual patient translated from patient's settings in `simglucose/params/`. For some virtual patients, their insulin sensitivity (correction factor) was tuned against random scenario runs of the simulator, because simulated glucose outputs spent significant amount of time in hypoglycemia. In these scenarios, we increased the insulin sensitivity. Virtual patient data is located in `../VirtualPatients/`.

We simulate the Trio oref algorithm by inserting oref's insulin delivery calculation command into the controller's policy. The controller translates oref's basal and bolus commands into rates in terms of U/min. These rates are then wired into `simglucose` which uses these rates to predict future glucose values.

The `simglucose` simulator executing oref algorithm is ran through `run_sim.py`. The `simglucose` simulator runs a custom meal scenario. This meal scenario can be pre-generated (either manually or through using `gen_meal_scenario.py`), or randoomly generated in `run_sim.py`. Meal scenarios used in experiments for paper in `../MealScenarios/`.

## Edits to Existing Codebase
Some files in the original codebase are not in this directory because they are unnecessary to run the Trio controller. Original codebase: https://github.com/jxx123/`simglucose`.

### Unedited Files
The following directories in `simglucose` are untouched from the original `simglucose` repo:
- `simglucose/actuator/`
- `simglucose/analysis/`
- `simglucose/envs/`
- `simglucose/params/`
- `simglucose/patient/`
- `simglucose/sensor/`

### Edited Files
Directory `simglucose/simulation/` has small addition in `sim_engine.py` which saves simulator results to a specified file given by the user.

### New Files
- `simglucose/controller/trio_ctrller.py`: Controller running policy wiring oref algorithm into `simglucose`.
-  `simglucose/gen_meal_scenario.py`: Create meal scenario. 
-  `simglucose/run_sim.py`: Run `simglucose` using controller defined in `trio_ctrller.py`.
