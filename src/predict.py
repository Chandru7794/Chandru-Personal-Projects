"""
predict.py
Loads yt_hours_ridge_v1 and scores all pending videos from fct_videos_pending.

Usage:
    python src/predict.py
"""

import sys
import json
import pathlib
import joblib
import duckdb
import pandas as pd

# --- Paths ---
ROOT = pathlib.Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "workload.duckdb"
ARTIFACT_DIR = ROOT / "artifacts"
MODEL_ID = "yt_hours_ridge_v1"

MODEL_COLS = [
    "length_tier_ord",
    "complexity_new",
    "complexity_media_depth",
    "complexity_delivery_style",
]

# --- Load model ---
model = joblib.load(ARTIFACT_DIR / f"{MODEL_ID}.pkl")
with open(ARTIFACT_DIR / f"{MODEL_ID}_meta.json") as f:
    meta = json.load(f)

# --- Load pending videos from dbt view ---
con = duckdb.connect(str(DB_PATH))
df = con.execute("SELECT * FROM fct_videos_pending").df()
con.close()

if df.empty:
    print("No pending videos found in fct_videos_pending.")
    sys.exit(0)

# --- Drop rows missing required model inputs ---
missing_inputs = df[MODEL_COLS].isnull().any(axis=1)
if missing_inputs.any():
    print(
        f"Warning: {missing_inputs.sum()} video(s) skipped — "
        "missing expected_length_mins or complexity flags.\n"
    )
    df = df[~missing_inputs].copy()

if df.empty:
    print("All pending videos are missing required inputs.")
    sys.exit(0)

# --- Predict ---
X = df[MODEL_COLS].astype(float)
df["predicted_hours"] = model.predict(X).round(1)

# --- Print results ---
print(f"\nModel: {MODEL_ID}  |  Holdout RMSE: {meta['holdout_rmse']}h\n")
print(f"{'Title':<45} {'Type':<18} {'Subtype':<30} {'Tier':<9} {'Pred hrs':>8}")
print("-" * 115)

for _, row in df.sort_values("predicted_hours", ascending=False).iterrows():
    tier = row.get("length_tier") or "?"
    pred = row["predicted_hours"]
    print(
        f"{str(row['media_title']):<45} "
        f"{str(row['video_type']):<18} "
        f"{str(row['video_subtype']):<30} "
        f"{tier:<9} "
        f"{pred:>8.1f}h"
    )

print(f"\nTotal pending: {len(df)} videos")
print(
    f"Intercept: {meta['intercept']:.2f}h  |  "
    f"Coefficients: length_tier_ord +{meta['coefficients']['length_tier_ord']:.2f}h/step, "
    f"media_depth +{meta['coefficients']['complexity_media_depth']:.2f}h, "
    f"delivery_style +{meta['coefficients']['complexity_delivery_style']:.2f}h, "
    f"new +{meta['coefficients']['complexity_new']:.2f}h"
)
