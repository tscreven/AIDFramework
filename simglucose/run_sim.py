from datetime import timedelta
from datetime import datetime
from simglucose.simulation.env import T1DSimEnv
from simglucose.controller.trio_ctrller import TrioOrefController
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.simulation.sim_engine import SimObj, sim
from simglucose.simulation.scenario import CustomScenario
from gen_meal_scenario import generate_scenario
import argparse
import numpy as np
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))

def parse_args():
    parser = argparse.ArgumentParser(description="Run UVA/Padova Simulator")
    parser.add_argument("-u", required=True, help="Virtual user")
    parser.add_argument("-a", default="swift", choices=["swift", "js", "jsbug"], help="Run JavaScript algorithm instead of Swift algorithm.")
    parser.add_argument("-d", type=int, default=14, help="Number of days to simulate.")
    parser.add_argument('-scen', help="Filepath of file containing custom meal scenario.")
    parser.add_argument("-fn", help="Filepath of file to write results to.")
    args = parser.parse_args()

    return args


def main(user, alg, days, scen, results_file):

    # formatting for CLI JS command flag
    js_flag = "--" + alg  if alg == "js" or alg == "jsbug" else None

    if not results_file:
        results_dir = os.path.join(REPO_ROOT, "simglucoseResults", user)
        name = f"{alg}.csv"
        results_file = os.path.join(results_dir, name)
    
    if os.path.exists(results_file):
        now = datetime.now()
        fn = f"{results_file.strip('.csv')}_{now.ctime()}.csv"
        print(f"Output file {results_file} already exists. Writing to {fn}")
        results_file = fn

    seed = 1

    num_days = days
    meal_scen = list(np.load(scen, allow_pickle=True)) if scen is not None else generate_scenario(num_days)
    split = user.find('0')
    patient_name = user[:split] + '#' + user[split:]
    patient = T1DPatient.withName(patient_name)
    start_time = datetime.combine(datetime.now().date(), datetime.min.time())
    day_length = timedelta(days=num_days)
    
    scenario = CustomScenario(start_time=start_time, scenario=meal_scen)
    sensor = CGMSensor.withName('GuardianRT', seed=seed) # GuardianRT produces reading once every 5 minutes
    pump = InsulinPump.withName('Insulet')
    env = T1DSimEnv(patient, sensor, pump, scenario)
    controller = TrioOrefController(user, js_flag)
    s = SimObj(env, controller, day_length, animate=False, results_fn=results_file)
    sim(s)

if __name__ == "__main__":
    args = parse_args()
    main(args.u, args.a, args.d, args.scen, args.fn)
