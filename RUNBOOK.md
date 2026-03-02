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

## Adding or Updating a Video Label

Run this when adding new rows to `seeds/video_labels.csv` (expected_length_mins, expected_complexity):

```bash
cd transform
dbt seed
dbt run --select dim_videos_ml
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
| `dim_videos_ml` | view | Extends `dim_videos` with manually labeled ML features (expected_length_mins, expected_complexity) |

---

## Pipeline Architecture

```
Workload.csv
    │
    ▼
scripts/load_raw.py          # drops and recreates `workload` table in DuckDB
    │
    ▼
stg_workload                 # cleaning and normalisation (dbt view)
    │
    ▼
combined_sessions            # session-level aggregation (dbt view)
    │
    ▼
dim_videos                   # video-level aggregation (dbt view)
    │
seeds/video_labels.csv ──── ▼
                        dim_videos_ml    # ML feature layer (dbt view)
```

---

## Notes

- `data/Workload.csv` and `data/workload.duckdb` are excluded from version control
- `seeds/video_labels.csv` is version controlled — commit changes to it alongside any model changes
- dbt profile is `youtube_workload` (defined in `~/.dbt/profiles.yml`)
