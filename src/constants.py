# src/constants.py
# Shared encoding constants for ML feature engineering.
# Import in notebooks with:
#   import sys; sys.path.append('..')
#   from src.constants import LENGTH_TIER_MAP, LENGTH_TIER_ORDER
#
# WARNING — SYNC REQUIRED:
# The LENGTH_TIER_MAP and LENGTH_TIER_ORDINAL definitions below are duplicated
# as SQL CASE statements in two dbt models:
#   transform/models/marts/dim_videos_ml.sql
#   transform/models/marts/fct_videos_pending.sql
# If you add a new expected_length_mins value or change tier boundaries here,
# you MUST update the CASE statements in both SQL files and re-run dbt.

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

# Ordinal encoding for Ridge regression (preserves tier ordering)
LENGTH_TIER_ORDINAL = {'Short': 0, 'Average': 1, 'Long': 2}
