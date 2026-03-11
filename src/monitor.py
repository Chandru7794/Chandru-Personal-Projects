"""
monitor.py
Evaluates production model performance on all completed videos.

Loads all three candidate models (M1-raw, M2-raw, M3b), predicts for every
completed video in dim_videos_ml, and prints a monitoring report covering:
  - Rolling RMSE vs holdout benchmark and B1 baseline
  - Full rolling mean residual trajectory (drift detection over time)
  - Residuals by length tier and video type
  - Feature distribution shift vs training period

Each run is logged to the MLflow experiment 'yt-hours-monitoring' so the
rolling residual trend is visible across monitoring cycles in the UI.

Usage:
    python src/monitor.py
"""

import sys
import json
import pathlib
import warnings
import joblib
import duckdb
import mlflow
import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")

# --- Paths ---
ROOT = pathlib.Path(__file__).resolve().parent.parent
DB_PATH      = ROOT / "data" / "workload.duckdb"
ARTIFACT_DIR = ROOT / "artifacts"

# --- Benchmarks (from Phase 1) ---
B1_RMSE      = 5.45   # mean by length tier
HOLDOUT_RMSE = 4.68   # M1-raw holdout

# Training cutoff: read from primary model meta so it updates automatically
# at each retrain (never hardcode — it changes every time the model is refitted).
_primary_meta_path = ARTIFACT_DIR / "yt_hours_ridge_v1_meta.json"
with open(_primary_meta_path) as f:
    _primary_meta = json.load(f)
TRAIN_CUTOFF = _primary_meta["train_cutoff"]

DRIFT_WINDOW    = 5    # match retrain cadence (every 5 new completed videos)
DRIFT_THRESHOLD = 2.0  # flag if |mean residual| > 2h over drift window
                       # (2h is ~43% of holdout RMSE — defensible at 5-video window;
                       #  revisit after 2-3 retrain cycles with more post-training data)

# --- MLflow setup ---
# Each monitor.py run creates one MLflow run in yt-hours-monitoring.
# The rolling_mean_resid and rolling_rmse metrics use step= so the UI
# shows the full trajectory across post-training videos — compare runs
# across retrain cycles to see long-term drift behaviour.
MLFLOW_DIR = ROOT / "mlruns"
mlflow.set_tracking_uri(f"file:///{MLFLOW_DIR}")
mlflow.set_experiment("yt-hours-monitoring")

# --- Model registry ---
# All three Phase 1 candidates. M1-raw is primary (drives the detailed report).
# M2-raw and M3b are tracked for comparison — to detect if either overtakes M1-raw
# as training data grows.
MODELS = [
    {
        "id": "yt_hours_ridge_v1",
        "label": "M1-raw (Ridge, flags)",
        "features": [
            "length_tier_ord",
            "complexity_new",
            "complexity_media_depth",
            "complexity_delivery_style",
        ],
    },
    {
        "id": "yt_hours_ridge_vtype_v1",
        "label": "M2-raw (Ridge, video_type)",
        "features": None,   # loaded from meta below
    },
    {
        "id": "yt_hours_rf_flags_v1",
        "label": "M3b (RF, flags)",
        "features": None,   # loaded from meta below
    },
]

# Load features for M2-raw and M3b from their meta sidecars
for m in MODELS:
    if m["features"] is None:
        meta_path = ARTIFACT_DIR / f"{m['id']}_meta.json"
        with open(meta_path) as f:
            m["features"] = json.load(f)["features"]

# --- Load completed videos from dbt view ---
con = duckdb.connect(str(DB_PATH))
df = con.execute("""
    SELECT
        video_id,
        media_title,
        video_type,
        video_subtype,
        date_first,
        hours_creation,
        length_tier,
        length_tier_ord,
        complexity_new,
        complexity_media_depth,
        complexity_delivery_style
    FROM dim_videos_ml
    WHERE is_complete = 1
      AND hours_creation IS NOT NULL
      AND length_tier_ord IS NOT NULL
      AND complexity_new IS NOT NULL
      AND complexity_media_depth IS NOT NULL
      AND complexity_delivery_style IS NOT NULL
    ORDER BY date_first
""").df()
con.close()

if df.empty:
    print("No completed videos with full feature data found.")
    sys.exit(0)

# Split into training-era and post-training (production) videos
df["date_first"] = pd.to_datetime(df["date_first"])
cutoff    = pd.to_datetime(TRAIN_CUTOFF)
df_train  = df[df["date_first"] <= cutoff].copy()
df_prod   = df[df["date_first"] > cutoff].copy()

n_total = len(df)
n_train = len(df_train)
n_prod  = len(df_prod)

run_name = f"monitor_{pd.Timestamp.now().strftime('%Y-%m-%d_%H%M')}"

with mlflow.start_run(run_name=run_name):

    mlflow.log_param("train_cutoff",     TRAIN_CUTOFF)
    mlflow.log_param("n_total",          n_total)
    mlflow.log_param("n_train",          n_train)
    mlflow.log_param("n_prod",           n_prod)
    mlflow.log_param("drift_window",     DRIFT_WINDOW)
    mlflow.log_param("drift_threshold",  DRIFT_THRESHOLD)

    # =========================================================================
    # SECTION 1 — Overall RMSE per model (all completed videos)
    # =========================================================================
    print("\n" + "=" * 70)
    print("MODEL PERFORMANCE REPORT")
    print("=" * 70)
    print(f"Completed videos: {n_total}  "
          f"(training-era: {n_train}, post-training: {n_prod})")
    print(f"Benchmarks — B1: {B1_RMSE}h  |  M1-raw holdout: {HOLDOUT_RMSE}h\n")

    for m in MODELS:
        artifact = ARTIFACT_DIR / f"{m['id']}.pkl"
        if not artifact.exists():
            print(f"  {m['label']}: artifact not found, skipping.")
            continue

        model = joblib.load(artifact)
        cols  = m["features"]

        # Build feature matrix; fill any missing vtype dummy columns with 0
        X = df[cols].copy() if all(c in df.columns for c in cols) else None
        if X is None:
            missing = [c for c in cols if c not in df.columns]
            for c in missing:
                df[c] = 0
            X = df[cols].copy()

        preds     = model.predict(X.astype(float))
        residuals = df["hours_creation"].values - preds
        df[f"pred_{m['id']}"]  = preds
        df[f"resid_{m['id']}"] = residuals

        rmse_all = np.sqrt(np.mean(residuals ** 2))
        mlflow.log_metric(f"{m['id']}_overall_rmse", round(float(rmse_all), 4))

        if n_prod > 0:
            mask       = df["date_first"] > cutoff
            resid_prod = residuals[mask]
            rmse_prod  = np.sqrt(np.mean(resid_prod ** 2))
            prod_str   = f"  post-training RMSE: {rmse_prod:.2f}h (n={n_prod})"
            mlflow.log_metric(f"{m['id']}_prod_rmse", round(float(rmse_prod), 4))
        else:
            prod_str = "  no post-training videos yet"

        beat = "BEATS HOLDOUT" if rmse_all < HOLDOUT_RMSE else (
               "beats B1" if rmse_all < B1_RMSE else "below B1")
        print(f"  {m['label']}")
        print(f"    overall RMSE: {rmse_all:.2f}h  [{beat}]")
        print(f"   {prod_str}")
        print()

    # From here, report is driven by primary model (M1-raw)
    primary_id = MODELS[0]["id"]
    if f"resid_{primary_id}" not in df.columns:
        print("Primary model artifact not found. Cannot produce detailed report.")
        sys.exit(1)

    resid_col = f"resid_{primary_id}"
    pred_col  = f"pred_{primary_id}"

    # =========================================================================
    # SECTION 2 — Drift: full rolling trajectory (post-training only)
    #
    # Prints one row per post-training video (once min 3 are available).
    # Each row shows the rolling mean residual and RMSE over the last
    # DRIFT_WINDOW videos — so you can see whether bias is growing,
    # shrinking, or stable rather than just a single snapshot value.
    #
    # rolling_mean_resid and rolling_rmse are also logged to MLflow with
    # step= so the trajectory is visible as a line chart in the UI.
    # Compare across monitoring runs to see long-term drift behaviour.
    # =========================================================================
    print("-" * 70)
    print(f"DRIFT REPORT — primary model: M1-raw  (window={DRIFT_WINDOW} videos)")
    print("-" * 70)

    if n_prod < 3:
        print(f"  Only {n_prod} post-training video(s) — need at least 3 for drift.\n")
        mlflow.log_metric("drift_flag", 0)
    else:
        prod = df[df["date_first"] > cutoff].copy().reset_index(drop=True)
        prod["rolling_mean_resid"] = (
            prod[resid_col].rolling(DRIFT_WINDOW, min_periods=3).mean()
        )
        prod["rolling_rmse"] = (
            prod[resid_col].rolling(DRIFT_WINDOW, min_periods=3)
            .apply(lambda x: np.sqrt(np.mean(x ** 2)), raw=True)
        )

        print(f"  {'Video #':<9} {'Date':<13} {'Rolling mean resid':>20}  "
              f"{'Rolling RMSE':>13}")
        print(f"  {'-'*8}  {'-'*12}  {'-'*19}  {'-'*12}")

        for i, row in prod.iterrows():
            mean_r = row["rolling_mean_resid"]
            rmse_r = row["rolling_rmse"]
            if pd.isna(mean_r):
                continue
            date_str  = str(row["date_first"])[:10]
            drift_str = "  ** DRIFT **" if abs(mean_r) > DRIFT_THRESHOLD else ""
            print(f"  Video {i+1:<4}  {date_str:<12}  {mean_r:>+19.2f}h  "
                  f"{rmse_r:>12.2f}h{drift_str}")
            # step= creates a line chart in MLflow UI across post-training videos
            mlflow.log_metric("rolling_mean_resid", round(float(mean_r), 4), step=i + 1)
            mlflow.log_metric("rolling_rmse",       round(float(rmse_r), 4), step=i + 1)

        latest_mean = prod["rolling_mean_resid"].iloc[-1]
        latest_rmse = prod["rolling_rmse"].iloc[-1]
        drift_flag  = abs(latest_mean) > DRIFT_THRESHOLD
        mlflow.log_metric("drift_flag", int(drift_flag))

        print()
        print(f"  Latest rolling mean residual: {latest_mean:+.2f}h  "
              f"{'*** DRIFT DETECTED ***' if drift_flag else 'OK'}")
        print(f"  Latest rolling RMSE:          {latest_rmse:.2f}h  "
              f"(holdout: {HOLDOUT_RMSE}h  |  B1: {B1_RMSE}h)")
        if drift_flag:
            direction = "underpredicting" if latest_mean > 0 else "overpredicting"
            print(f"\n  Model is consistently {direction} by "
                  f"{abs(latest_mean):.1f}h on average.")
            print("  Consider retraining.\n")
        else:
            print()

    # =========================================================================
    # SECTION 3 — Residuals by length tier
    # =========================================================================
    print("-" * 70)
    print("RESIDUALS BY LENGTH TIER  (actual - predicted; positive = underpredict)")
    print("-" * 70)
    tier_stats = (
        df.groupby("length_tier")[resid_col]
        .agg(n="count", mean="mean", rmse=lambda x: np.sqrt(np.mean(x ** 2)))
        .reset_index()
    )
    tier_order = ["Short", "Average", "Long"]
    tier_stats["length_tier"] = pd.Categorical(
        tier_stats["length_tier"], categories=tier_order, ordered=True
    )
    tier_stats = tier_stats.sort_values("length_tier")

    print(f"  {'Tier':<10} {'N':>4}  {'Mean resid':>11}  {'RMSE':>6}")
    for _, row in tier_stats.iterrows():
        print(f"  {row['length_tier']:<10} {int(row['n']):>4}  "
              f"{row['mean']:>+10.2f}h  {row['rmse']:>5.2f}h")
        mlflow.log_metric(f"tier_{row['length_tier']}_mean_resid",
                          round(float(row["mean"]), 4))
        mlflow.log_metric(f"tier_{row['length_tier']}_rmse",
                          round(float(row["rmse"]), 4))
    print()

    # =========================================================================
    # SECTION 4 — Residuals by video type
    # =========================================================================
    print("-" * 70)
    print("RESIDUALS BY VIDEO TYPE")
    print("-" * 70)
    vtype_stats = (
        df.groupby("video_type")[resid_col]
        .agg(n="count", mean="mean", rmse=lambda x: np.sqrt(np.mean(x ** 2)))
        .reset_index()
        .sort_values("n", ascending=False)
    )
    print(f"  {'Type':<22} {'N':>4}  {'Mean resid':>11}  {'RMSE':>6}")
    for _, row in vtype_stats.iterrows():
        print(f"  {row['video_type']:<22} {int(row['n']):>4}  "
              f"{row['mean']:>+10.2f}h  {row['rmse']:>5.2f}h")
    print()

    # =========================================================================
    # SECTION 5 — Feature distribution shift (training-era vs post-training)
    # =========================================================================
    print("-" * 70)
    print("FEATURE DISTRIBUTION SHIFT  (post-training vs training-era)")
    print("-" * 70)

    if n_prod < 5:
        print(f"  Only {n_prod} post-training video(s) — need at least 5 for shift.\n")
    else:
        flag_cols = [
            "complexity_new", "complexity_media_depth", "complexity_delivery_style"
        ]
        print(f"  {'Feature':<30} {'Train mean':>12}  {'Post-train mean':>16}")
        for col in flag_cols:
            train_mean = df_train[col].mean()
            prod_mean  = df_prod[col].mean()
            delta      = prod_mean - train_mean
            flag       = "  *" if abs(delta) > 0.15 else ""
            print(f"  {col:<30} {train_mean:>11.2f}   {prod_mean:>14.2f}  "
                  f"({delta:+.2f}){flag}")
            mlflow.log_metric(f"shift_{col}", round(float(delta), 4))

        print()
        print(f"  {'Length tier mix':<30} {'Train %':>10}  {'Post-train %':>14}")
        for tier in tier_order:
            tr_pct = (df_train["length_tier"] == tier).mean() * 100
            pr_pct = (df_prod["length_tier"]  == tier).mean() * 100 if n_prod > 0 else 0.0
            print(f"  {tier:<30} {tr_pct:>9.1f}%   {pr_pct:>13.1f}%")
        print()

    print("=" * 70)
    print(f"Retraining recommended when: |rolling mean residual| > {DRIFT_THRESHOLD}h  "
          f"OR  rolling RMSE > {B1_RMSE}h")
    print("=" * 70 + "\n")
    print(f"MLflow run logged: {run_name}")
