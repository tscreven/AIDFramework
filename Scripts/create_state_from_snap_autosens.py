import sys
from pathlib import Path
from create_pump_history import convert as convert_pump_history
from replace_preference import replace as replace_preferences
import shutil
import json
from datetime import datetime, timezone, timedelta

PREFERENCE_PATH = 'autosensBugInvoke/state_autosens_error/preferences.json'
GLUCOSE_PATH = 'autosensBugInvoke/state_autosens_error/glucose.json'
TDD_PATH = 'autosensBugInvoke/state_autosens_error/tdd.json'
SETTINGS_PATH = 'autosensBugInvoke/state_autosens_error/settings.json'

def create_state(snapshot_path: str):
    snapshot_file = Path(snapshot_path)
    snapshot_id = snapshot_file.name.rsplit('.', 2)[0].split('-')[0]
    destination_dir = snapshot_file.parent / f'state_{snapshot_id}'

    with open(snapshot_path, 'r') as f:
        snapshot = json.load(f)

    with open(PREFERENCE_PATH, 'r') as f:
        preferences = json.load(f)

    basal_profile = snapshot['autosensInput']['profile']['basalprofile']
    bg_targets = snapshot['autosensInput']['profile']['bg_targets']
    insulin_sensitivities = snapshot['autosensInput']['profile']['isfProfile']
    _, preferences = replace_preferences(preferences, snapshot['autosensInput']['profile'])
    history = snapshot['autosensInput']['history']
    pump_history = convert_pump_history(history)
    carb_ratios = snapshot['autosensInput']['profile']['carb_ratios']
    carbs = snapshot['autosensInput']['carbs']
    glucose = snapshot['autosensInput']['glucose']

    resumeat = snapshot['autosensInput']['clock']
    destination_dir.mkdir(exist_ok=True)

    with open(destination_dir / 'resumeTimestamp.txt', 'w') as f:
        f.write(str(resumeat))
    clock_dt = datetime.fromtimestamp(resumeat, tz=timezone.utc)
    autosens_ts = (clock_dt - timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
    profile_sens = snapshot['autosensInput']['profile']['sens']
    autosens = {"timestamp": autosens_ts, "ratio": 1, "newisf": profile_sens}
    with open(destination_dir / 'autosens.json', 'w') as f:
        json.dump(autosens, f, indent=2)
    with open(destination_dir / 'basal_profile.json', 'w') as f:
        json.dump(basal_profile, f, indent=4)
    with open(destination_dir / 'bg_targets.json', 'w') as f:
        json.dump(bg_targets, f, indent=4)
    with open(destination_dir / 'carbs.json', 'w') as f:
        json.dump(carbs, f, indent=4)
    with open(destination_dir / 'carb_ratios.json', 'w') as f:
        json.dump(carb_ratios, f, indent=4)
    glucose_converted = [
        {"timestamp": float(g["dateString"]), "glucose": g.get("sgv", g.get("glucose"))}
        for g in glucose
    ]
    with open(destination_dir / 'glucose.json', 'w') as f:
        json.dump(glucose_converted, f, indent=4)
    with open(destination_dir / 'insulin_sensitivities.json', 'w') as f:
        json.dump(insulin_sensitivities, f, indent=4)
    with open(destination_dir / 'preferences.json', 'w') as f:
        json.dump(preferences, f, indent=4)
    with open(destination_dir / 'profile.json', 'w') as f:
        json.dump(snapshot['autosensInput']['profile'], f, indent=4)
    with open(destination_dir / 'pump_history.json', 'w') as f:
        json.dump(pump_history, f, indent=4)
    history_converted = []
    for h in history:
        entry = dict(h)
        if 'timestamp' in entry and isinstance(entry['timestamp'], (int, float)):
            entry['timestamp'] = datetime.fromtimestamp(entry['timestamp'], tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
        history_converted.append(entry)
    with open(destination_dir / 'autosens_history.json', 'w') as f:
        json.dump(history_converted, f, indent=4)
    shutil.copy(SETTINGS_PATH, destination_dir / 'settings.json')
    shutil.copy(TDD_PATH, destination_dir / 'tdd.json')
    with open(destination_dir / 'temptargets.json', 'w') as f:
        json.dump([], f, indent=4)

    print(f'Created {destination_dir}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <snapshot.json> [...]')
        sys.exit(1)

    for path in sys.argv[1:]:
        create_state(path)
