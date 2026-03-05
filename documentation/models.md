# Project Phases

## Phase 1 - Predictive Model + End-to-End Pipeline
Build a model predicting pre-processing + processing hours, deploy it as a served endpoint backed by a dbt feature pipeline.

## Phase 2 - Retrospective Lever Analysis (Dashboard)
Retrospective statistical analysis of which working behaviors correlate with efficiency. Output is a refreshing dashboard, not a deployed model.

## Phase 3 - Lever Impact Evaluation
After changing behaviors based on Phase 2 findings, re-evaluate the Phase 1 model to see if predictions improve.
Note: need to separate lever-driven improvement from natural improvement over time (getting faster through experience).
Use Phase 1 model residuals over time as a baseline drift metric before attributing gains to the levers.

---



## Phase 1 Detail - Predict Time (Hours) to Complete a Video

### Target
Total hours of Pre-Processing + Processing. Post-Processing excluded (mechanical, predictable on its own, and irrelevant.  Often times im making a thumbnail years later).

Stored as `hours_creation` in `dim_videos` / `dim_videos_ml` (computed in dbt, not derived in notebooks).

#### Target Distribution and Outlier Handling

One significant outlier exists: the Halloween Review (3 Things), `hours_creation = 53.15`, the first movie review ever made (June 2024). Most complexity flag was active simultaneously (`complexity_new=1`, `complexity_media_depth=1`, `complexity_delivery_style=1`, `complexity_logistics=1`). It is ~40% above the next-highest video (Jaws, 37.85 hrs) and ~3x the dataset mean.

**Plan: Fit both raw and log-transformed models; let residual diagnostics and out-of-sample RMSE decide.**

The normality assumption in linear regression applies to the **model residuals**, not the raw target. A Q-Q plot of the raw target is a useful preliminary indicator but is not the definitive test. The Q-Q R² on the raw target is 0.924, which is in the acceptable range — the data is not wildly non-normal. The Shapiro-Wilk test rejects normality, but at n=98 it has enough power to flag mild departures that are practically irrelevant.

Both versions will be fit with Ridge regularization, and the winner is determined by:
1. Residual Q-Q plots — whichever produces better-behaved (more normal) residuals
2. Walk-forward RMSE in the original hours scale (log model predictions are back-transformed via `exp()` before comparison)

**Option 1 — Log-transform**
- Compresses the right tail proportionally. Halloween shifts from 53.15 to log=3.97; Jaws from 37.85 to 3.63. Reduces Halloween's leverage on coefficients without discarding it.
- Keeps all 99 data points.
- Coefficients become multiplicative: a flag adding β log-hours means the video takes e^β times as long.
- Trade-off: back-transformation introduces a small bias. `exp(predicted_log)` estimates the geometric mean, not the arithmetic mean. A smearing correction (`exp(predicted_log + residual_variance/2)`) is needed for unbiased hour predictions. Predictions less intuitive to reason about.

**Option 2 — Raw (no transform)**
- Predictions directly in hours — easier to interpret and communicate.
- Ridge regularization partially mitigates Halloween's leverage by shrinking all coefficients.
- Valid if residuals are approximately normal after fitting.

**Option 3 — Cap (Winsorize)** — Rejected
- Clips values above a percentile threshold, effectively relabelling Halloween with a fabricated label. The cap value is arbitrary and percentile estimates are unstable at n=98.

**Option 4 — Removal** — Rejected
- Drops Halloween from training (n=98 to 97). Halloween is the only row where all complexity flags fire at once; removing it further thins signal for already-sparse flags. Future first-time videos still need a grounding point.

#### Secondary Target
`creation_day_span` — calendar days from first to last creation session (pre-processing + processing only).

Use this instead of `total_day_span`. `total_day_span` spans the first work session to the last session of any type, including thumbnails and subtitles that can be done years after the main work is finished. `creation_day_span` is stored in `dim_videos` / `dim_videos_ml` (computed in dbt).

Secondary target to consider: total unique days worked on the video (`active_days_worked`).

### Features - Must Be Known Before Starting the Video

`expected_length_mins` — likely one of the strongest predictors. Values (7,10,15,20,25,30) are tier labels, not continuous measurements. Encoded as 3 ordinal tiers for modeling:
- Short: 7, 10 min (n ≈ 46)
- Average: 15 min (n ≈ 36)
- Long: 20, 25, 30 min (n ≈ 17)

**Complexity Flags** (binary 0/1; all assigned prospectively before work begins)

`complexity_new` — 1 if: new video series, first time doing something on-camera or technically, or first time watching the source material. Captures startup/unfamiliarity overhead.

`complexity_media_depth` — 1 = wide range of topics covered (e.g. a full movie review covering themes, characters, plot); 0 = narrow/focused scope (e.g. a single boss review, a scene breakdown covering one scene).

`complexity_delivery_style` — 1 = fully scripted, not adlibbing recordings; 0 = notes-based with adlibbed delivery. Scripted (1) is the target standard for reviews going forward.

`complexity_logistics` — excluded from primary model. 1 if external circumstantial disruptions were present during production. Partially retrospective (not always predictable at video start). Retained in seed/dbt for Phase 2 lever analysis.

`complexity_worklife` — excluded from primary model. 1 = forced to work in limited intervals due to work-life balance pressures. Temporally confounded (skews toward recent videos) and more predictive of `creation_day_span` than `hours_creation`. Retained in seed/dbt for Phase 2.

**`video_type` vs Complexity Flags — Modeling Approach**

`video_type` and the complexity flags are correlated (Spearman r=+0.376 between `complexity_delivery_style` and `[vtype] Review`; r=-0.430 vs `[vtype] Rankings`), but not redundant — the flags explain ~14% of video_type variance (r²≈0.14), meaning both carry substantial independent signal. Note: these correlations dropped significantly after correcting `complexity_media_depth` and `complexity_delivery_style` flags for early Witcher 3 videos (previously reported at r=0.71 based on mislabeled data). However, including both at n=98 would exceed the practical parameter budget.

Two model variants will be compared on walk-forward RMSE:
- **Model A — Flags only:** `expected_length_mins` + `complexity_new` + `complexity_media_depth` + `complexity_delivery_style`. Forward-compatible as production style evolves; encodes causal mechanism rather than label. Note: `complexity_new` has weak bivariate correlation with hours_creation (Spearman r=+0.074, p=0.47) — Ridge will naturally shrink its coefficient; confirm contribution at model-fitting time.
- **Model B — video_type only:** `expected_length_mins` + `video_type` dummies (drop one reference level). More directly interpretable but less generalizable to new formats.

`media_type` excluded from both — temporally aliased with content era (Video Games 2023–2024, Movies 2024+), making the coefficient unreliable in walk-forward evaluation.

`media_series`, `media_title` — not used. Too sparse or no signal.






### Known Risks and Constraints

**Sample size** - ~100 usable videos after cleaning in March 2026. Biggest practical constraint. 

**Learning/temporal drift** - Production speed has likely improved over time through experience, independent of content type. But this is confounded by my data where all video games are 2023-2024 and then everything after that is movies (except 1 video game).  Im expecting to do more video game content but its confounding.

**Single model vs. separate models** - Start with one model and `media_type` as a feature. Check residuals by `media_type`. If errors are systematically biased by type, split into separate models then.

**Cross-validation** - Cannot use random train/test splits on time-series data. Use walk-forward validation: train on everything before date X, test on X onward.

**Within-category variance** - If all playthroughs take roughly the same time, a model predicting the category mean will be hard to beat. Worth checking variance within segments during EDA before investing in modeling.

---

## Phase 2 Detail - Retrospective Lever Analysis

Note: the levers below are features computed *after* a video is complete. This makes them useless for the Phase 1 predictive model but valid for a retrospective statistical study. This is a regression/correlation analysis problem, not a machine learning problem — sample size doesn't support ML here. Output is a dashboard that refreshes as new videos are completed.

Levers to investigate:
1. Should i prioritize working days or nights
    - Obviously day span will be larger and so will number of days working if i go exclusively day or night but maybe the hours spent is reduced
    - Or maybe its vice versa, maybe hours spent is higher, but day span is less (i will have to fix how span is calculated)
2. Looking at what proportion of pre-processing is done AFTER processing is done
    - often times, i finish the entire script and then make the video.  But sometimes (like my current video), im writing the script, getting stuck, so i start editing to kick things back into gear, and then writing some more.
3. Prioritize working weekdays or weekends?
4. Whether longer sessions helps total hours vs shorter sessions?  For this, i think i'd want a "% of total duration" that was spent with longer sessions vs shorter
5. Complexity of video idea? - I think i can just do this as "High", "Medium", and "Low".  Likely correlated with whether this video is the first in a "media_series" (i often have a bit of a challenge getting myself up to speed when starting on a new media series)
6. Whether working X amount of time on multiple days in a row improves my throughput?
    - Again i think this would have to be percentage of time.  So if 50% of a video's pre-processing and post-processing was done in a set/group of consecutive days where i worked >2 hours, is that more efficient than  when its only 10% or 0%?

Caution: levers aren't randomly assigned. Working nights correlates with being busy overall, which correlates with content type. Observed correlations may be confounded — interpret carefully and avoid causal language without further analysis.

---

## Secondary Models (Backlog)
1. Predicting How Long a Workflow Session Will be based on time started, creation category, day of week, etc.
    - This can be useful because MAYBE a prediction like this can be used to then be able to predict how many days a video will take?
    - Session-level data has far more rows than video-level — more tractable for ML than the primary model
    - Session model could feed into video-level estimates: predict session length, multiply by expected session count per video type
