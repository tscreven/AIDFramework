# simglucose

This document provides instructions for simulating the Trio oref algorithm in `simglucose` on pre-loaded virtual persons and explains how Trio's oref algorithm is looped into the simulator's controller policy.

The `simglucose` implementation included in this repository is adapted from the original implementation by Jianxiong Xie and contributors. Modifications were made to support the evaluation environment used in this study.

## Outline
1. Simulation Instructions and Commands
    * [Create meal scenario](#create-meal-scenario)
    * [Run simulator](#run-simulator)
2. [Oref Algorithm Integration Explanation](#trio-oref-algorithm-integration-in-simglucose)

## Commands

### Create Meal Scenario
Inputting a meal scenario is not required to run the simulator. However, if a meal scenario is not given, the simulation executor will randomly generate one. Inputting a meal scenario allows for results to be reproduced.

**Manually create meal scenario:** 

The scenario is expected as a 2D `NumPy` matrix of shape (N, 2) where N = number of meals in the scenario. First column is the number of simulation steps since the simulation started: number of CGM readings since the simulation started. There is one CGM reading every simulation step.

The step index is the number of steps since the start of the simulation, which means a meal at the first simulation step occurs at reading number zero. For example, a meal at the 12th step means a meal one hour into the simulation. The second column is the carbohydrate amount. For example, a row of [355, 20] means 20 grams of carbohydrates were consumed at the 356th CGM reading (zero-based indexing). Meal scenario files should be saved as a `NumPy` file (.npy).

**Programmatically create meal scenario:**

The following script generates a random meal scenario given certain constraints around the number of days in the scenario, meal size, and meal timing.

[gen_meal_scenario.py](../simglucose/gen_meal_scenario.py) creates a meal scenario with the following algorithm: 
1. Each day, the virtual person eats breakfast, lunch, and dinner within +/- 30 minutes of the median meal time.
    * Default median meal times: breakfast = 8:30, lunch = 13:00, dinner = 19:00.
2. Within a meal range, each minute has an equal chance of being selected.
3. Meal size is randomly selected between a minimum and maximum carbohydrate amount. $mealMedian$ = median carbohydrate amount for the meal. $mealRange$ = percent allowed variation from $mealMedian$; $mealRange$ = [0,1]. Minimum possible carbohydrate amount = $mealMedian$ - $mealRange$ * $mealMedian$. Maximum possible carbohydrate amount = $mealMedian$ + $mealRange$ * $mealMedian$.
4. There is either 0 or 1 snacks in a day, which is determined by a preset probability. If a snack occurs, there is an equal chance of it happening at the midway point between breakfast and lunch, and lunch and dinner. Snack size is determined the same way as other meals.

</br>

```
python3 simglucose/gen_meal_scenario.py -d <days> -ps <p_snack> -bk <breakfast> -ln <lunch> -dn <dinner> -sn <snack> -mr <meal_range> -bkTime <breakfast_time> -lnTime <breakfast_time> -dbTime <dinner_time> -fp <filepath>
```

| Field | Description | Required | Default Value |
| :-: | :-: | :-: | :-: |
| days | Number of days in the scenario | Yes | N/A |
| p_snack | Probability of a snack occurring in a day (between [0, 1]) | No | 0.5 |
| breakfast | Median breakfast carbohydrate amount | No | 30 |
| lunch | Median lunch carbohydrate amount | No | 60 |
| dinner | Median dinner carbohydrate amount | No | 50 |
| snack | Median breakfast carbohydrate amount | No | 20 |
| meal_range | Maximum allowed percent difference from median carbohydrates for each meal (between [0, 1]) | No | 0.1 |
| breakfast_time | Median breakfast time in possible scenario | No | 8:30 |
| lunch_time | Median lunch time in possible scenario | No | 13:00 |
| dinner_time | Median dinner time in possible scenario | No | 19:00 |
| filepath | Filepath to .npy file where scenario matrix will be saved | No | "./scen.npy" |



### Run Simulator

```
python3 simglucose/run_sim.py -u <virtual_patient> -a <alg_name> -d <days> -scen <meal_scenario_path> -fn <results_file>
```

* `virtual_patient`: Name of virtual person. Valid names are age group followed by three digits. Age groups = [child, adolescent, adult]. Valid digits = [001, 002, 003, 004, 005, 006, 007, 008, 009, 010].
    * eg. adolescent002 or adult010
    * Virtual person therapeutic settings in directory [VirtualPersons](../VirtualPersons/).
* `alg_name`: Optional argument. Name of the JavaScript oref algorithm variant to run instead of the Swift algorithm. Defaults to `"swift"` if no argument given. Possible choices:
    * `jsbug`: Original JavaScript implementation.
    * `js`: Javascript implementation of bug-free Swift oref algorithm.
    * `swift`: Swift implementation of oref algorithm.
* `days`: Number of days simulation runs (must be whole number)
* `meal_scenario_path`: Optional argument. Filepath to precomputed .npy file containing meal scenario.
* `results_file`: Filepath to .csv file where outputs will be written to.


## Trio Oref Algorithm Integration in simglucose
A [controller](../simglucose/simglucose/controller/trio_ctrller.py) initializes a simulation state for the Trio oref algorithm. The oref algorithm uses this simulation state to track the last 24 hours of self-managed time-series data to decide the amount of insulin to deliver at the current timestep.

The oref algorithm uses unique physiological parameters for each virtual person translated from the their settings in [../simglucose/simglucose/params/](../simglucose/simglucose/params/). For some virtual persons, their insulin sensitivity (correction factor) was tuned against random scenario runs of the simulator, because simulated glucose outputs spent significant amount of time in hypoglycemia. In these scenarios, we increased the insulin sensitivity. Virtual patient data is located in [../VirtualPersons/](../VirtualPersons/).

We simulate the Trio oref algorithm by wiring oref's insulin delivery outputs into the controller's policy. The controller translates oref's basal and bolus commands into rates in terms of U/min. These rates are then inputted into `simglucose` which uses these rates to calculate future glucose values.

The `simglucose` simulator executing oref algorithm is ran through [run_sim.py](../simglucose/run_sim.py). The `simglucose` simulator runs a custom meal scenario. This meal scenario can be pre-generated (either manually or through [gen_meal_scenario.py](../simglucose/gen_meal_scenario.py)), or randomly generated in `run_sim.py`. 

Meal scenarios used for mechanistic in silico experiments in paper written to directory [MealScenarios](../MealScenarios/).