import sys
from pathlib import Path
from create_pump_history import convert as convert_pump_history
from replace_preference import replace as replace_preferences
import shutil
import json

PREFERENCE_PATH = 'iobBugInvoke/state_2b7574f4/preferences.json'
GLUCOSE_PATH = 'iobBugInvoke/state_2b7574f4/glucose.json'
SETTINGS_PATH = 'iobBugInvoke/state_2b7574f4/settings.json'
TDD_PATH = 'iobBugInvoke/state_2b7574f4/tdd.json'


def create_state(snapshot_path: str):
    snapshot_file = Path(snapshot_path)
    snapshot_id = snapshot_file.name.replace('.json', '')
    destination_dir = snapshot_file.parent / f'state_{snapshot_id}'

    with open(snapshot_path, 'r') as f:
        snapshot = json.load(f)

    with open(PREFERENCE_PATH, 'r') as f:
        preferences = json.load(f)

    autosens = snapshot['iobInput']['autosens']
    basal_profile = snapshot['iobInput']['profile']['basalprofile']
    bg_targets = snapshot['iobInput']['profile']['bg_targets']
    insulin_sensitivities = snapshot['iobInput']['profile']['isfProfile']
    _, preferences = replace_preferences(preferences, snapshot['iobInput']['profile'])
    history = snapshot['iobInput']['history']
    pump_history = convert_pump_history(history)
    carb_ratios = snapshot['iobInput']['profile']['carb_ratios']

    resumeat = snapshot['iobInput']['clock']
    destination_dir.mkdir(exist_ok=True)

    with open(destination_dir / 'resumeTimestamp.txt', 'w') as f:
        f.write(str(resumeat))
    with open(destination_dir / 'autosens.json', 'w') as f:
        json.dump(autosens, f, indent=4)
    with open(destination_dir / 'basal_profile.json', 'w') as f:
        json.dump(basal_profile, f, indent=4)
    with open(destination_dir / 'bg_targets.json', 'w') as f:
        json.dump(bg_targets, f, indent=4)
    with open(destination_dir / 'carbs.json', 'w') as f:
        json.dump([], f, indent=4)
    with open(destination_dir / 'carb_ratios.json', 'w') as f:
        json.dump(carb_ratios, f, indent=4)
    shutil.copy(GLUCOSE_PATH, destination_dir / 'glucose.json')
    with open(destination_dir / 'insulin_sensitivities.json', 'w') as f:
        json.dump(insulin_sensitivities, f, indent=4)
    with open(destination_dir / 'preferences.json', 'w') as f:
        json.dump(preferences, f, indent=4)
    with open(destination_dir / 'profile.json', 'w') as f:
        json.dump(snapshot['iobInput']['profile'], f, indent=4)
    with open(destination_dir / 'pump_history.json', 'w') as f:
        json.dump(pump_history, f, indent=4)
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
