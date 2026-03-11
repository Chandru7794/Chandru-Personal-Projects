# EDA Report: Video-Level Production Time Analysis

**Notebook:** `eda/video_eda.ipynb`
**Date:** 2026-02-28
**Purpose:** Assess whether predicting total production time per video is feasible and identify data quality issues before modelling.

---

## 1. Dataset

Source: `dim_videos` view from `workload.duckdb`. One row per video (identified by `video_id`, which is a combination of `media_title` + `video_subtype`). This is the video-level aggregate built on top of `combined_sessions`.

| Property | Detail |
|---|---|
| Grain | One row per video (media_title + video_subtype) |
| Total rows | 125 |
| Total columns | 35 |
| Key numeric columns | `total_hours`, `hours_*` (13 duration columns), `total_day_span`, `active_days_worked` |
| Key categorical columns | `media_type`, `media_title`, `video_type`, `video_subtype`, `media_series` |

---

## 2. Schema

| # | Column | Dtype | Non-Null |
|---|---|---|---|
| 0 | video_id | str | 125 |
| 1 | media_title | str | 125 |
| 2 | video_type | str | 125 |
| 3 | video_subtype | str | 125 |
| 4 | media_type | str | 125 |
| 5 | media_series | str | 125 |
| 6 | total_hours | float64 | 125 |
| 7 | date_first | datetime64 | 125 |
| 8 | date_last | datetime64 | 125 |
| 9 | total_day_span | int64 | 125 |
| 10 | active_days_worked | int64 | 125 |
| 11–18 | hours_editing … hours_uploading | float64 | 125 (each) |
| 19 | hours_pre_processing | float64 | 125 |
| 20 | hours_processing | float64 | 125 |
| 21 | hours_post_processing | float64 | 125 |
| 22 | hours_uncategorised | float64 | 125 |
| 23 | pre_processing_date_first/last | datetime64 | **118** |
| 24 | pre_processing_total_day_span | Int64 | **118** |
| 25 | processing_date_first/last | datetime64 | **109** |
| 26 | processing_total_day_span | Int64 | **109** |
| 27 | post_processing_date_first/last | datetime64 | **100** |
| 28 | post_processing_total_day_span | Int64 | **100** |

All `hours_*` columns are fully populated — no video is missing duration data for any category. The nulls in the date/span columns indicate videos where that phase has not been started yet (incomplete videos).

---

## 3. Video Composition

### 3.1 By Media Type

| media_type | Count |
|---|---|
| Video Games | ~70 |
| Movies | ~55 |

Two distinct content types are present. The notebook notes a "big difference between movies and video games" — this is likely the strongest categorical signal in the dataset and should be a top-level split in any model.

### 3.2 Video Games Titles Observed

| media_title | video_types |
|---|---|
| The Witcher 3 | Review, Rankings |
| Elden Ring | Review, Playthrough |
| Baldur's Gate 3 | Playthrough |
| Grand Theft Auto V | Review |
| Marvel's Spiderman | Review |
| Hitman WOA | Playthrough |

### 3.3 Movies Series Observed

| media_series / title grouping | video_types |
|---|---|
| Halloween series | Review, Shorts, Scene Breakdown |
| Indiana Jones series | Review, Rankings, Scene Breakdown |
| Jaws series | Review, Rankings |
| Jurassic Park / World series | Review, Rankings, Essay, Shorts |
| Superman series | Review, Rankings, Essay, Retrospectives |
| A Nightmare on Elm Street | Review, Scene Breakdown, Stats |

### 3.4 Video Types Present

| video_type | Notes |
|---|---|
| Review | Dominant type — the core content format |
| Playthrough | Long-form game series, often multi-part |
| Rankings | Typically shorter, comparative format |
| Scene Breakdown | Very short, targeted analysis |
| Essay | Variable length, thematic |
| Shorts | Near-zero hours — almost certainly incomplete |
| Retrospectives | Variable |
| Stats | Very short |

---

## 4. Total Hours Distribution

### 4.1 Notable Values

| total_hours | media_title | video_type | video_subtype |
|---|---|---|---|
| 0.08 | Superman: The Movie | Essay | Superman and Lois Toxic Relationship |
| 0.12 | Halloween | Shorts | 3 Things |
| 0.22 | Halloween | Scene Breakdown | Judith Myers |
| 0.25 | Elden Ring | Playthrough | Part 7 |
| 0.37 | Jurassic Park | Shorts | 3 Things |
| 55.03 | Halloween | Review | 3 Things |
| 39.62 | Jaws | Review | 3 Things |
| 38.48 | Indiana Jones (Crystal Skull) | Review | 3 Things |
| 32.75 | The Witcher 3 | Review | Return to Crookback Bog |
| 32.50 | Jurassic World: Dominion | Review | 3 Things |

The range spans from 0.08 hrs to 55.03 hrs — nearly three orders of magnitude. This is a key modelling challenge. The minimum values (< 1 hr) almost certainly represent **incomplete or abandoned videos**, not genuine short productions.

### 4.2 Identified Issue: Incomplete Videos

The notebook explicitly flags that **uncompleted videos must be removed** before modelling. The extreme low values (< 1 hr, near-zero `active_days_worked`) are the clearest indicator. A filter on minimum `active_days_worked` or minimum `total_hours` is needed before any analysis or modelling.

---

## 5. Day Span Issue

The `total_day_span` column shows values up to **484 days** (Halloween Review). This is not a genuine production time — it reflects the calendar distance between the first and last session, which spans multiple other videos being worked on simultaneously. The user noted: *"total_day_span seems to not make sense. I have to figure out how to calculate overlapping videos."*

Selected examples illustrating the problem:

| media_title | video_subtype | total_hours | total_day_span | active_days_worked |
|---|---|---|---|---|
| Halloween | 3 Things | 55.03 | 484 | 25 |
| Halloween 2 | 3 Things | 34.52 | 464 | 16 |
| Indiana Jones (Crystal Skull) | 3 Things | 38.48 | 389 | 17 |
| The Witcher 3 | Twisted Firestarter | 10.23 | 241 | 5 |
| GTA V | First Heist | 26.53 | 159 | 23 |

`active_days_worked` is the more reliable effort metric: it counts only the days where at least one session occurred, independent of what else was being worked on in parallel. For modelling, `active_days_worked` should be preferred over `total_day_span` until the span calculation is fixed.

---

## 6. Processing Phase Completeness

| Phase | Videos with Date Data | Missing |
|---|---|---|
| Pre-Processing | 118 / 125 | 7 |
| Processing | 109 / 125 | 16 |
| Post-Processing | 100 / 125 | 25 |

Videos missing Post-Processing dates have likely not yet been uploaded/published. These are strong candidates for the incomplete video filter. The 25 videos missing post-processing data likely overlap heavily with the low-`total_hours` outliers identified above.

---

## 7. dbt Model Note: Script Moved to Pre-Processing

The notebook records a deliberate model decision: `Script` was reclassified from `Processing` to `Pre-Processing`. The stated rationale:

> *"i think there could be a useful signal in terms of which videos i begin editing while the script is still in flux"*

This means `hours_pre_processing` now includes both `Script` and `Processing Raw Video` time. This is reflected in the `dim_videos` CASE statement as of the current model version. Any comparison to older exports of this view should account for this change.

---

## 8. Issues and Recommended Next Steps

### 8.1 Filter Incomplete Videos Before Any Analysis

Remove videos where:
- Post-processing dates are null (25 videos not yet uploaded), or
- `total_hours < threshold` (e.g., < 2 hrs), or
- `active_days_worked == 1` and `total_hours < 1` (single-session stubs)

This is the highest priority action — all distributions and model targets are skewed by these records.

### 8.2 Fix or Replace `total_day_span`

`total_day_span` is unreliable as a production effort metric due to overlapping concurrent video work. Options:
- Drop the column from modelling entirely and use only `active_days_worked`
- Compute a true "net working days" using a calendar-aware join against all session dates

### 8.3 Stratify All Analysis by `media_type`

The notebook notes a "big difference between movies and video games." All EDA and modelling should separate these two groups. A pooled model without `media_type` as a feature will likely underperform significantly.

However, further EDA shows that `media_type` is almost entirely correlated with temporal pattern.  All but 1 video game video was done prior to movie videos.

### 8.4 Examine `total_hours` Distribution Per Video Type

`Review`, `Playthrough`, `Rankings`, and `Scene Breakdown` likely have very different production time profiles. The distribution of `total_hours` within each `video_type` × `media_type` combination has not yet been plotted. Box plots or violin plots stratified this way are the natural next step.

### 8.5 Assess Whether 125 Rows Is Sufficient for Modelling

After filtering incomplete videos, the usable sample may be considerably smaller than 125. If 30–40% of rows are removed, the remaining ~75–90 complete videos may be too few for a reliable model — particularly with the number of categorical splits (`video_type`, `media_type`, `media_series`). The effective N per subgroup needs to be assessed before committing to a modelling approach.