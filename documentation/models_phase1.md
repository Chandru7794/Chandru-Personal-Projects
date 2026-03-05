# Phase 1 - Predictive Model + End-to-End Pipeline

Build a model predicting pre-processing + processing hours, deploy it as a served endpoint backed by a dbt feature pipeline.

---

## Target

Total hours of Pre-Processing + Processing. Post-Processing excluded (mechanical, predictable on its own, and irrelevant.  Often times im making a thumbnail years later).

Stored as `hours_creation` in `dim_videos` / `dim_videos_ml` (computed in dbt, not derived in notebooks).

### Target Distribution and Outlier Handling

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

### Secondary Target

`creation_day_span` — calendar days from first to last creation session (pre-processing + processing only).

Use this instead of `total_day_span`. `total_day_span` spans the first work session to the last session of any type, including thumbnails and subtitles that can be done years after the main work is finished. `creation_day_span` is stored in `dim_videos` / `dim_videos_ml` (computed in dbt).

Secondary target to consider: total unique days worked on the video (`active_days_worked`).

---

## Features - Must Be Known Before Starting the Video

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

### `video_type` vs Complexity Flags — Modeling Approach

`video_type` and the complexity flags are correlated (Spearman r=+0.376 between `complexity_delivery_style` and `[vtype] Review`; r=-0.430 vs `[vtype] Rankings`), but not redundant — the flags explain ~14% of video_type variance (r²≈0.14), meaning both carry substantial independent signal. Note: these correlations dropped significantly after correcting `complexity_media_depth` and `complexity_delivery_style` flags for early Witcher 3 videos (previously reported at r=0.71 based on mislabeled data). However, including both at n=98 would exceed the practical parameter budget.

Two model variants will be compared on walk-forward RMSE:
- **Model A — Flags only:** `expected_length_mins` + `complexity_new` + `complexity_media_depth` + `complexity_delivery_style`. Forward-compatible as production style evolves; encodes causal mechanism rather than label. Note: `complexity_new` has weak bivariate correlation with hours_creation (Spearman r=+0.074, p=0.47) — Ridge will naturally shrink its coefficient; confirm contribution at model-fitting time.
- **Model B — video_type only:** `expected_length_mins` + `video_type` dummies (drop one reference level). More directly interpretable but less generalizable to new formats.

`media_type` excluded from both — temporally aliased with content era (Video Games 2023–2024, Movies 2024+), making the coefficient unreliable in walk-forward evaluation.

`media_series`, `media_title` — not used. Too sparse or no signal.

---

## Known Risks and Constraints

**Sample size** - ~100 usable videos after cleaning in March 2026. Biggest practical constraint.

**Learning/temporal drift** - Production speed has likely improved over time through experience, independent of content type. But this is confounded by my data where all video games are 2023-2024 and then everything after that is movies (except 1 video game).  Im expecting to do more video game content but its confounding.

**Single model vs. separate models** - Start with one model and `media_type` as a feature. Check residuals by `media_type`. If errors are systematically biased by type, split into separate models then.

**Cross-validation** - Cannot use random train/test splits on time-series data. Use walk-forward validation: train on everything before date X, test on X onward.

**Post-fit diagnostics** - After fitting, compute residuals split by:
- `hours_creation` quartile (does the model systematically underpredict hard videos?)
- `media_type` (is bias concentrated in one content era?)
- `expected_length_tier` (are errors uniform across video lengths?)
- Flag combinations (do interaction effects show up as patterned residuals?)

**Within-category variance** - If all playthroughs take roughly the same time, a model predicting the category mean will be hard to beat. Worth checking variance within segments during EDA before investing in modeling.

---

## Next Steps — Modeling Plan

### Evaluation Metric

Primary metric: **RMSE in original hours scale** (symmetric). Log-model predictions are back-transformed via `exp()` before computing RMSE so all models are comparable on the same scale.

Target precision: **±5 hours** is the threshold for the model to be considered useful. The meaningful production tiers are roughly 0–10h, 10–20h, 20–30h — a model that can distinguish these reliably is actionable.

Note: underprediction is worse than overprediction in practice (blown schedule vs. pleasant surprise). If two models have similar RMSE, prefer the one with a lower rate of large underpredictions. Check mean signed error (predicted − actual) in post-fit diagnostics.

---

### Step 1 — Baselines

Compute all three. B1 is the **success criterion** — models must beat it to be considered worthwhile. B2 is computed to validate the decision to use flags over video_type, not as a target to beat.

| ID | Model | Description | Purpose |
|----|-------|-------------|---------|
| B0 | Global mean | Predict 17h for every video | Absolute floor |
| B1 | Mean by length tier | Predict mean `hours_creation` for Short / Average / Long | **Success criterion** |
| B2 | Mean by video_type | Predict mean `hours_creation` per video_type category | Diagnostic: expected to be noisy (Reviews span 7–53h), confirming video_type groupings are too heterogeneous to use as a standalone lookup |

**How baselines are computed and compared**

Baselines involve no model fitting or optimization — they are lookup tables of means. However, those means must be computed from the **training set only** (videos 1–73); the baseline never sees test labels. Applying test-set actual values to compute the mean would be data leakage.

In rolling CV folds, the means are recomputed per fold from that fold's training window only (e.g. Fold 1 uses videos 1–48 to compute tier means, then predicts videos 49–58).

Example for B1 (training means, approximate):
```
Short  (7, 10 min) → predict 11h for every Short video in the test set using the means from the training data
Average (15 min)   → predict 17h for every Average video in the test set using the means from the training data
Long   (20–30 min) → predict 26h for every Long video in the test set using the means from the training 
```

For each test video, the squared error is `(predicted − actual)²`. RMSE is computed across all 25 test videos:

```
RMSE = sqrt( mean( (predicted_i − actual_i)² ) )
```

"Beating the baseline" means the model's RMSE across all 25 test videos is lower than B1's RMSE. A single video where the baseline is closer than the model does not matter — only the aggregate across all 25 does.

**Why within-tier variance determines how hard B1 is to beat**

B1 predicts the same value for every video in a tier, regardless of complexity flags. If Long videos cluster tightly around 26h, B1 is already a good predictor and the flags add little measurable lift. If Long videos span 10–53h (which they do), B1 is a poor predictor and there is real room for the model to improve by distinguishing flag combinations within the same tier. The EDA box plots and Spearman correlations established that within-tier variance is high enough to make B1 a meaningful but beatable benchmark.

---

### Step 2 — Model Candidates

All models fit on the training set only (videos 1–73 by `date_first`). Raw and log-transformed versions of linear models are both fit; the better one (by rolling CV RMSE) is carried forward.

| ID | Model | Features | Notes |
|----|-------|----------|-------|
| L1 | Ridge — flags (Model A) | `expected_length_mins` (tiered) + `complexity_new` + `complexity_media_depth` + `complexity_delivery_style` | Alpha tuned via TimeSeriesSplit within training set. `complexity_new` has weak bivariate signal (r=0.07); Ridge will shrink it — check coefficient magnitude post-fit. |
| L2 | Ridge — video_type (Model B) | `expected_length_mins` (tiered) + `video_type` dummies (one reference level dropped) | Direct comparison to L1. Less forward-compatible if new video formats are introduced. |
| T1 | Decision tree | Same as L1 features | Depth 2–3 only. Captures flag interactions (e.g. `media_depth=1 AND delivery_style=1`) without explicit interaction terms. No distributional assumptions. |
| T2 | Random Forest | Same as L1 features | Only pursued if T1 is competitive. Requires careful `min_samples_leaf` tuning at n=73. |

**Why tree-based is in scope**: complexity flags are unlikely to combine additively. A scripted AND wide-scope video may be disproportionately harder than the sum of each flag alone. Trees find these thresholds naturally; linear models require explicit interaction terms that the parameter budget cannot support.

---

### Step 3 — Cross-Validation Strategy

Two layers of CV, serving different purposes:

**Layer 1 — Hyperparameter tuning (inside training set)**
Used for Ridge alpha and tree depth. Use `sklearn.model_selection.TimeSeriesSplit` on the 73-video training set. Prevents data leakage; earlier videos always train, later videos always validate within each fold.

**Layer 2 — Model selection (rolling time-series CV)**
Used to choose between L1, L2, T1, T2. Produces multiple RMSE estimates per model so the comparison is not decided by one lucky or unlucky 25-video window.

```
Fold 1: Train [1–48]  → Test [49–58]   → RMSE per model
Fold 2: Train [1–58]  → Test [59–68]   → RMSE per model
Fold 3: Train [1–68]  → Test [69–78]   → RMSE per model
                         Average RMSE across folds → select winner
```

Minimum training size of 48 ensures enough data for Ridge to be meaningful. Folds are non-overlapping in the test window; training is always expanding (earlier videos are never dropped).

**Final evaluation — holdout (touched once)**
After the winner is selected via rolling CV, retrain on the full training set (videos 1–73) and evaluate on the held-out test set (videos 74–98, n=25, `date_first` ≥ 2025-02-06). This RMSE is the reported model performance. The holdout is never used during model selection.

---

### Step 4 — Post-Fit Diagnostics

Run on the winning model after final evaluation:

- **Residuals by `hours_creation` quartile** — does the model systematically underpredict hard videos (Q4)?
- **Residuals by `media_type`** — is error concentrated in the Movies era vs. Video Games era?
- **Residuals by `expected_length_tier`** — are errors uniform across Short / Average / Long?
- **Residuals by flag combination** — do patterned residuals suggest an interaction effect the model missed?
- **Mean signed error** — positive = overpredicts on average (acceptable); negative = underpredicts on average (flag for review)
- **Residual Q-Q plot** — check normality of residuals for the winning model; compare raw vs. log version if both were carried to final evaluation

If residuals show systematic bias by `media_type`, revisit splitting into separate models per content era.

---

### Order of Operations

1. Compute B0, B1, B2 baselines
2. Run rolling CV (Layer 2) for L1-raw, L1-log, L2-raw, L2-log, T1
3. Select winning model by mean rolling CV RMSE
4. If T1 competitive (within 1h RMSE of best linear), try T2
5. Retrain winner on full training set (videos 1–73)
6. Evaluate once on final holdout (videos 74–98) — report RMSE
7. Run post-fit diagnostics on winning model
