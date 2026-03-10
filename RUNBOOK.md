# Runbook — YouTube Workload Pipeline

All commands assume you are running from the **project root** unless otherwise noted.

---

## Regular Update (run whenever Workload.csv is updated)

1. Export updated `Workload.csv` to `data/`
2. Load into DuckDB:
   ```bash
   python scripts/load_raw.py
   ```
3. Run and test dbt models:
   ```bash
   cd transform
   dbt run
   dbt test
   ```

---

## Adding a New Planned Video

When you add a new row to `transform/seed/video_labels.csv`, you only need to fill in the **natural key** and the label columns — no `video_id` required. `video_id` is computed automatically in the pipeline from the natural key.

**Natural key** (all three must be unique together): `media_title`, `video_type`, `video_subtype`

CSV columns to fill in:
```
media_title, video_type, video_subtype, expected_length_mins,
complexity_new, complexity_media_depth, complexity_delivery_style,
complexity_logistics, complexity_worklife, is_complete
```

Set `is_complete = 0` for planned videos. Then seed and refresh:

```bash
cd transform
dbt seed
dbt run --select dim_videos_ml fct_videos_pending
dbt test --select video_labels
```

---

## Marking a Video as Complete

Update the row in `transform/seed/video_labels.csv`: set `is_complete = 1`. Then:

```bash
cd transform
dbt seed
dbt run --select dim_videos_ml fct_videos_pending
dbt test --select video_labels
```

---

## Full Fresh Build

Use this on a new machine or after schema changes:

```bash
python scripts/load_raw.py

cd transform
dbt seed
dbt run
dbt test
```

---

## dbt Models

| Model | Type | Description |
|---|---|---|
| `stg_workload` | view | Cleans and normalises raw workload sessions from `Workload.csv` |
| `combined_sessions` | view | Combines sessions across videos |
| `dim_videos` | view | One row per video with aggregated hours and date spans |
| `dim_videos_ml` | view | Extends `dim_videos` with ML labels from `video_labels` seed (join on natural key) |
| `fct_videos_pending` | view | Planned videos (`is_complete = 0`) with model-ready features for prediction |

---

## Pipeline Architecture

```
Workload.csv
    │
    ▼
scripts/load_raw.py          # drops and recreates `workload` table in DuckDB
    │
    ▼
stg_workload                 # cleaning and normalisation; computes video_id hash
    │
    ▼
combined_sessions            # session-level aggregation (dbt view)
    │
    ▼
dim_videos                   # video-level aggregation; carries video_id (dbt view)
    │
seeds/video_labels.csv ──── ▼
    │                   dim_videos_ml       # ML feature layer; join on natural key
    │
    └──────────────────► fct_videos_pending # planned videos (is_complete = 0)
                                            # video_id recomputed from natural key
```

---

## Notes

- `data/Workload.csv` and `data/workload.duckdb` are excluded from version control
- `seeds/video_labels.csv` is version controlled — commit changes alongside any model changes
- `video_id` is **not** stored in `video_labels.csv`; it is the MD5 hash of
  `media_title || '|' || video_type || '|' || video_subtype`, computed in `stg_workload`
  and recomputed in `fct_videos_pending` where needed
- dbt profile is `youtube_workload` (defined in `~/.dbt/profiles.yml`)
- Production model artifact: `artifacts/yt_hours_ridge_v1.pkl` (loaded by `src/predict.py`)
