"""
Convert pump history to absolute insulin delivery events,
matching how Trio exports to HealthKit.

- Bolus events: insulin = amount (as-is)
- TempBasal events: insulin = (duration_min / 60) * rate
- Gaps between temp basals: filled with scheduled basal from basal profile

Usage:
    python3 scripts/insulin_trace.py --input test.json --output absolute.json
"""


import pandas as pd
import numpy as np

def process_insulin_data(df: pd.DataFrame):
    
    # 3. Clean the whole DataFrame at once
    df.drop(columns=['isSMB', 'isExternal'], inplace=True)
    df.drop_duplicates(subset=['id', 'timestamp'], inplace=True)

    df = pair_temp_basal(df)
    trim_overlapping_temp_basals(df)
    convert_temp_basal_to_insulin(df)
    return format_insulin_data(df)

def clean_insulin_data(data: list[dict]) -> pd.DataFrame:
    # 1. Gather all raw dictionaries into a single flat list
    flat_history = []
    for rec in data:
        # Using .get() is safer and faster than checking "if key in dict" twice
        meal_input = rec.get("mealInput", {})
        pump_history = meal_input.get("pumpHistory", [])
        
        if pump_history:
            # .extend() unrolls the list and adds the dicts directly
            flat_history.extend(pump_history)

    # 2. Create the DataFrame EXACTLY ONCE
    if not flat_history:
        return pd.DataFrame() # Safety catch for empty data
        
    df = pd.DataFrame(flat_history)

    # 4. Apply your merging logic
    return df

def pair_temp_basal(df: pd.DataFrame) -> pd.DataFrame:
    # 1. Split the data into 3 distinct groups
    is_tb = df['_type'] == 'TempBasal'
    is_dur = df['_type'] == 'TempBasalDuration'
    
    # Everything else (Bolus, etc.)
    bolus_df = df[df['_type'] == 'Bolus'].copy() 
    
    tb_df = df[is_tb].drop(columns=['duration (min)'])
    dur_df = df[is_dur]

    # 2. Merge TempBasal and Duration on their shared timestamp
    # This instantly aligns the rate from tb_df with the duration from dur_df
    merged_tb = pd.merge(
        tb_df, 
        dur_df[['timestamp', 'duration (min)']], # Only bring the columns we need
        on='timestamp', 
        how='left'
    )
    
    # 3. Rename columns to match your desired final output
    merged_tb.rename(columns={'duration (min)': 'duration_min'}, inplace=True)
    merged_tb['amount'] = pd.NA
    
    # 4. Stack the regular events and the newly merged Temp Basals back together
    final_df = pd.concat([bolus_df, merged_tb], ignore_index=True)
    final_df.drop(columns=['duration (min)'], inplace=True)
    
    # Sort them so they are back in chronological order
    final_df.sort_values('timestamp', ignore_index=True, inplace=True)
    return final_df

def trim_overlapping_temp_basals(pump_history_paired: pd.DataFrame):
    """
    Trim temp basal durations so they don't overlap with the next temp basal.
    Modifies pump_history_paired in place.
    """
    # 1. Ensure the whole dataframe is sorted chronologically first
    pump_history_paired.sort_values('timestamp', inplace=True)
    
    # 2. Create a boolean mask for just the Temp Basals
    is_tb = pump_history_paired['_type'] == 'TempBasal'
    
    # 3. Find the "next" start time for every Temp Basal
    # .shift(-1) pulls the value from the row directly below it
    next_start_times = pump_history_paired.loc[is_tb, 'timestamp'].shift(-1)
    
    # 4. Calculate the maximum allowed duration (in minutes) before they hit the next basal
    max_duration_min = (next_start_times - pump_history_paired.loc[is_tb, 'timestamp']) / 60.0
    
    # The last Temp Basal won't have a "next" start time (it will be NaN). 
    # We fill it with infinity so we don't accidentally trim it.
    max_duration_min = max_duration_min.fillna(np.inf)
    
    # 5. Update the durations
    # .clip() limits the original durations to our newly calculated maximums
    pump_history_paired.loc[is_tb, 'duration_min'] = pump_history_paired.loc[is_tb, 'duration_min'].clip(upper=max_duration_min)

def convert_temp_basal_to_insulin(df: pd.DataFrame):
    """Convert TempBasal entries in the DataFrame to insulin amounts."""
    is_tb = df['_type'] == 'TempBasal'
    df.loc[is_tb, 'amount'] = (df.loc[is_tb, 'duration_min'] / 60.0) * df.loc[is_tb, 'rate']
    df.loc[is_tb, 'amount'] = df.loc[is_tb, 'amount'].round(4)
    df['deliveryReason'] = "bolus"
    df.loc[is_tb, 'deliveryReason'] = "basal"

def format_insulin_data(df: pd.DataFrame) -> pd.DataFrame:
    """Formats the insulin DataFrame for the final JSON output."""
    df['date'] = pd.to_datetime(df['timestamp'], unit='s', utc=True)
    df['unit'] = 'U'
    df['type'] = 'insulin'
    df.rename(columns={'amount': 'value'}, inplace=True)
    return df[['date', 'type', 'unit', 'value', "deliveryReason"]]
