import random
import argparse
import numpy as np
import os
from datetime import datetime
import re


def parse_args():
    parser = argparse.ArgumentParser(description="Generate meal scenario")
    parser.add_argument("-d", required=True, type=int, help="Number of days to simulate a meal scenario.")
    parser.add_argument("-ps", type=float, default=0.5, help="Probability of a snack occurring.")

    parser.add_argument("-bk", type=int, default=30, help="Median breakfast carbohydrate amount.")
    parser.add_argument("-ln", type=int, default=60, help="Median lunch carbohydrate amount.")
    parser.add_argument("-dn", type=int, default=50, help="Median dinner carbohydrate amount.")
    parser.add_argument("-sn", type=int, default=20, help="Median snack carbohydrate amount.")
    parser.add_argument("-mr", type=float, default=0.1, help="+/-% allowable carbohydrate deviation from mean meal carbohydrate amount.")

    parser.add_argument("-bkTime", default='8:30', help="Median breakfast time. 24 hour clock [h]:[m].")
    parser.add_argument("-lnTime", default='13:00', help="Median lunch time. 24 hour clock [h]:[m].")
    parser.add_argument("-dnTime", default='19:00', help="Median dinner time. 24 hour clock [h]:[m].")
    parser.add_argument("-tr", type=int, default=30, help="+/- allowable time deviation from median meal time in minutes.")

    parser.add_argument("-fp", default="scen.npy", help="Filepath of file to write results to.")
    args = parser.parse_args()

    if args.ps < 0 or args.ps > 1:
        raise Exception(f"Probability of a snack must be between [0,1]. Inputted snack probability = {args.ps}.")
    for v, m_str in zip([args.bk, args.ln, args.dn, args.sn], ["breakfast", "lunch", "dinner", "snack"]):
        if v < 0:
            raise Exception(f"Number of carbohydrates in a meal must be at least 0. {m_str}'s inputted mean carb input = {v}.")
    if args.mr < 0:
        raise Exception(f"Allowable deviation from mean meal carb amount must be >= 0. Inputted deviation = {args.mr}.")
    
    pattern = r"^(?:[01]?\d|2[0-3]):[0-5]\d$"
    for time, m_str in zip([args.bkTime, args.lnTime, args.dnTime], ["breakfast", "lunch", "dinner"]):
        if not re.match(pattern, time):
            raise Exception(f"Invalid median {m_str} time: {time}. Expected formatting: [h]:[m] in a 24 hour clock")
        
    if args.tr < 0:
        raise Exception(f"Invalid time deviation from median meal time: {args.tr}. Deviation must be >= 0.")
    
    if os.path.exists(args.fp):
        response = input(f"Target filepath {args.fp} already exists. Do you want to overwrite {args.fp}? [y/[n]]: ")
        if response.lower() == 'y':
            print("Overwriting ", args.fp)
        else:
            print(f"\tExiting program. {args.fp} was not overwritten.")
            exit(0)

    return args


def meal_time(time:str, minute_range:int):
    date = datetime.strptime(time, "%H:%M")
    reading_idx = (date.hour * 60 + date.minute) // 5
    step_range = minute_range // 5
    low = reading_idx - step_range
    high = reading_idx + step_range
    return random.randint(low, high) / 12


#
# Return meal scenario for virtual patient. Each day, virtual patient eats
# breakfast, lunch, and dinner within a range of times of the median meal time.
# Within these ranges, each minute has an equal chance of being selected. Size
# of meal randomly selected from range around median meal carbohydrate size. If
# a snack occurs, equal probability of it happening at the midway point between
# breakfast and lunch, and lunch and dinner. Size of snack determined same way
# as other meals. Default parameter values for simulator runner.
#
def generate_scenario(days:int, p_snack=0.5, bkf_carb=30, lnc_carb=60, 
                      dnr_carb=50, snack_mean=20, meal_range=0.1, 
                      bkf_med_time='8:30', lnc_med_time='13:00', 
                      dnr_med_time='19:00', time_range=30) -> list:
    meals = []
    pct_lowerbound = 1 - meal_range
    pct_upperbound = 1 + meal_range

    for d in range(days):

        i = 24 * d # 24 hours in a day.

        bkf_time = meal_time(bkf_med_time, time_range)
        lnc_time = meal_time(lnc_med_time, time_range)
        dnr_time = meal_time(dnr_med_time, time_range)
        is_snack = random.random()

        bkf_size = random.randint(round(pct_lowerbound * bkf_carb), round(pct_upperbound * bkf_carb))
        if bkf_size > 0: 
            meals.append((i+bkf_time, bkf_size))

        # If is_snack < P(snack), snack occurs. If snack occurs, equal odds
        # snack occurs between breakfast and lunch, and lunch and dinner. If
        # is_snack < P(snack)/2, snack occurs at midway point between breakfast
        # and lunch. If is_snack >= P(snack)/2, snack occurs at midway point
        # between lunch and dinner. 
        snk_size = random.randint(round(pct_lowerbound * snack_mean), round(pct_upperbound * snack_mean))
        if snk_size > 0 and is_snack < p_snack/2:
            snack_time = round((bkf_time+lnc_time) / 2)
            meals.append((i+snack_time, snk_size))

        lnc_size = random.randint(round(pct_lowerbound * lnc_carb), round(pct_upperbound * lnc_carb))
        if lnc_size > 0:
            meals.append((i+lnc_time, lnc_size))

        # Snack occurs at midway point between lunch and dinner.
        if snk_size > 0 and is_snack >= p_snack/2 and is_snack < p_snack:
            snack_time = round((lnc_time+dnr_time) / 2)
            meals.append((i+snack_time, snk_size))

        dnr_size = random.randint(round(pct_lowerbound * dnr_carb), round(pct_upperbound * dnr_carb))
        if dnr_size > 0: 
            meals.append((i+dnr_time, dnr_size))
    
    return meals

if __name__ == "__main__":
    args = parse_args()
    scen = generate_scenario(args.d, args.ps, args.bk, args.ln, args.dn, 
                             args.sn, args.mr, args.bkTime, args.lnTime, 
                             args.dnTime, args.tr)
    np.save(args.fp, np.array(scen, dtype=object))