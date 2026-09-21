from .base import Controller
from .base import Action
import subprocess
import sys
import json
from pathlib import Path

OREF_SWIFT_BINARY = ".build/arm64-apple-macosx/release/oref-swift"

class TrioOrefController(Controller):

    def __init__(self, virtual_user, js_alg):
        self.js_alg = js_alg

        virtual_users_dir = Path(__file__).resolve().parents[3] / "VirtualPersons"
        user_path = virtual_users_dir / virtual_user

        # Initialize TrioOref simulation state.
        init_result = subprocess.run(
            [OREF_SWIFT_BINARY, "initialize", "-u", str(user_path), "-o", "-"],
            capture_output=True, text=True
        )
        if init_result.returncode != 0:
            print(f"Error initializing: {init_result.stderr}", file=sys.stderr)
            sys.exit(1)
        self.state_dir = json.loads(init_result.stdout)["stateDir"]


    #
    # Execute TrioOref algorithm calculate command. Integrate algorithm output
    # into expected format for simulator.
    #
    def policy(self, observation, reward, done, **kwargs):
        sample_time = kwargs.get('sample_time', 1)
        t = kwargs.get('time')
        timestamp = t.timestamp() # type: ignore
        glucose = observation.CGM

        determination = self._calculate(timestamp, glucose)
        active_rate, bolus_rate = self._insulin_outputs(determination, sample_time)

        return Action(basal=active_rate, bolus=bolus_rate)
        

    #
    # Execute and return result of TrioOref's calculate command.
    #
    def _calculate(self, timestamp, glucose):
        cmd = [OREF_SWIFT_BINARY, "calculate", "-s", self.state_dir, "-i", "-", "-o", "-"]

        if self.js_alg is not None:
            cmd.append(self.js_alg)

        input_data = json.dumps({"timestamp": timestamp, "glucose": glucose})
        result = subprocess.run(cmd, input=input_data, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error calculating: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        return json.loads(result.stdout)


    #
    # Return TrioOref's bolus and determine basal outputs.
    #
    def _insulin_outputs(self, determination, sample_time):
        bolus = determination.get("units") or 0.0
        rate = determination.get("rate")
        duration = determination.get("duration")

        active_rate = 0
        if rate is not None and duration is not None and (rate != 0 or duration != 0):
            active_rate = rate / duration

        return active_rate, bolus / sample_time
    

    # Empty method to satisfy parent class.
    def reset(self):
        pass
