import json
import pandas as pd
from datetime import datetime, timezone

def process_glucose_data(data: list[dict]) -> pd.DataFrame:
    """
    Reads glucose data from a JSON file, processes it, and returns a list
    of dictionaries in the specified format.
    """

    all_glucose_records = []
    # The JSON can be a list of records or a single record

    for record in data:
        meal_input = record.get("mealInput", {})
        glucose_history = meal_input.get("glucose", []) if isinstance(meal_input, dict) else []

        if glucose_history:
            all_glucose_records.extend(
                glucose_history
            )
    if not all_glucose_records:
        return pd.DataFrame() # Return empty DataFrame if no glucose data found

    all_glucose_df = pd.DataFrame(all_glucose_records)
    all_glucose_df.drop_duplicates(subset=['_id', 'date', 'dateString'], inplace=True)
    all_glucose_df.dropna(subset=['sgv'], inplace=True)

    all_glucose_df['unit'] = 'mg/dL'
    all_glucose_df['type'] = 'glucose'
    all_glucose_df['date'] = pd.to_datetime(all_glucose_df['dateString'], unit='s', utc=True)
    all_glucose_df.rename(columns={'sgv': 'value'}, inplace=True)

    all_glucose_df.drop(
        columns=['_id', 'dateString', 'direction'], 
        inplace=True
    )

    return all_glucose_df