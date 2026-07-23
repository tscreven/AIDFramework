"""
Givent he data from json file, extract the following user specific information
Save each of them in a standalone json file:
- insulin_sensitivities.json
- bg_targets.json
- basal_profile.json
- carb_ratios.json
- preferences.json
- settings.json
- temptargets.json
"""

from pathlib import Path
import json

def save_extracted_data(extracted_data: dict, output_dir: str | Path = Path(".")):

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Save each of them in a standalone json file
    for name, value in extracted_data.items():
        if not value:
            print(f"Warning: {name} is empty or None: {value}")
        (output_dir / f"{name}.json").write_text(json.dumps(value, indent=2))
        print(f"Saved {name}.json")


# used in a for loop, need to consider data passed to/from previous iterations
def extract_user_profile(data: list[dict], extracted_data: dict | None = None):
    settings = {
            "maxBolus" : 10,
            "insulin_action_curve" : 10,
            "maxBasal" : 5
        }
    
    if extracted_data is None:
        carb_ratios = None
        basal_profile = None
        bg_targets = None
        insulin_sensitivities = None
        preferences = None
        temptargets = []
    else:
        carb_ratios = extracted_data.get("carb_ratios")
        basal_profile = extracted_data.get("basal_profile")
        bg_targets = extracted_data.get("bg_targets")
        insulin_sensitivities = extracted_data.get("insulin_sensitivities")
        preferences = extracted_data.get("preferences")
        settings = extracted_data.get("settings", settings)
        temptargets = extracted_data.get("temptargets", [])

    for rec in data:
        try:
            determineBasalInput: dict = rec.get("determineBasalInput", {})
            profile: dict = determineBasalInput.get("profile", {})

            # assume if the key exists, then the content is not empty.
            preferences = determineBasalInput.get("preferences", preferences)
            basal_profile = determineBasalInput.get("basalProfile", basal_profile)
            # second possible place for basal profile
            basal_profile = profile.get("basalprofile", basal_profile)

            carb_ratios = profile.get("carb_ratios", carb_ratios)
            bg_targets = profile.get("bg_targets", bg_targets)
            insulin_sensitivities = profile.get("isfProfile", insulin_sensitivities)

            if all([preferences, carb_ratios, basal_profile, bg_targets, insulin_sensitivities]):
                break  # Exit early if we've found all the data we need
        
        except Exception as e:
            print(f"Error processing record: {e}")
            continue

    extracted_data = {
        "preferences": preferences,
        "carb_ratios": carb_ratios,
        "basal_profile": basal_profile,
        "bg_targets": bg_targets,
        "insulin_sensitivities": insulin_sensitivities,
        "settings": settings,
        "temptargets": temptargets
    }
    
    return all([preferences, carb_ratios, basal_profile, bg_targets, insulin_sensitivities]), extracted_data




        