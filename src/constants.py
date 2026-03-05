# src/constants.py
# Shared encoding constants for ML feature engineering.
# Import in notebooks with:
#   import sys; sys.path.append('..')
#   from src.constants import LENGTH_TIER_MAP, LENGTH_TIER_ORDER

# --- expected_length_mins encoding ---
# Raw values (7,10,15,20,25,30) are ordinal tier labels, not continuous measurements.
# Grouped into 3 tiers based on EDA (target_eda.ipynb).
LENGTH_TIER_MAP = {
    7:  'Short',    # n ≈ 46
    10: 'Short',
    15: 'Average',  # n ≈ 36
    20: 'Long',     # n ≈ 17
    25: 'Long',
    30: 'Long',
}
LENGTH_TIER_ORDER = ['Short', 'Average', 'Long']
