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

**Unseen `video_type` categories in test set (M2 specific)** - `video_type` dummy variables are only meaningful if the category appears in the training set. Two categories violate this:

- **Scene Breakdowns** — appear only in the test set, never in training. `vtype_Scene_Breakdown` is all zeros in the training data, so it has zero variance and Ridge learns a coefficient of essentially 0. When the test set contains a Scene Breakdown, the model ignores that dummy and predicts from intercept + `length_tier_ord` only — effectively treating it as a Review (the reference category). This is pure extrapolation to an unseen category.
- **Playthroughs** — heavily represented in training but only one observation in the test set. The coefficient is well-estimated but evaluated on a single data point, which is too sparse to validate.

This is the same root cause as M1-raw's temporal distribution shift — new content formats were introduced after the training window. M2-raw's flat CV fold RMSE may partly reflect that Scene Breakdowns simply never appeared as a test challenge during the CV folds, not that the model generalises to new formats.

**Implication:** M2-raw's holdout RMSE of 5.49h should be interpreted with this caveat. For Scene Breakdown predictions specifically, the model is guessing based on length only. Residuals split by `video_type` in post-fit diagnostics will make this visible — if Scene Breakdown residuals are large and patterned (e.g. consistently underpredicting), that confirms the extrapolation problem.

---

## Next Steps — Modeling Plan

### Evaluation Metric

Primary metric: **RMSE in original hours scale** (symmetric). Log-model predictions are back-transformed via `exp()` before computing RMSE so all models are comparable on the same scale.

```
RMSE = sqrt( (1/n) * sum( (y_i - ŷ_i)² ) )
```

RMSE is **model-agnostic** — it only measures the gap between predictions and actuals, regardless of whether the model is Ridge, a decision tree, or anything else. The model's internal mechanism is irrelevant; only the output is evaluated.

Squaring the errors penalizes large misses disproportionately (a 10h error contributes 100 to the sum; a 1h error contributes 1). The square root brings the result back to hours, making it directly interpretable. This asymmetric penalty on large errors is appropriate here — a 15h scheduling miss is far worse than three 5h misses.  This is why we are not using MAE

Target precision: **±5 hours** is the threshold for the model to be considered useful. The meaningful production tiers are roughly 0–10h, 10–20h, 20–30h — a model that can distinguish these reliably is actionable.

Note: underprediction is worse than overprediction in practice (blown schedule vs. pleasant surprise). If two models have similar RMSE, prefer the one with a lower rate of large underpredictions. Check mean signed error (predicted − actual) in post-fit diagnostics.

---

### Step 1 — Baselines

Compute all three. B1 is the **success criterion** — models must beat it to be considered worthwhile. B2 is computed to validate the decision to use flags over video_type, not as a target to beat.

| ID | Model | Description | Test RMSE | Purpose |
|----|-------|-------------|-----------|---------|
| B0 | Global mean | Predict mean `hours_creation` for every video | 6.50h | Absolute floor |
| B1 | Mean by length tier | Predict mean `hours_creation` for Short / Average / Long | **5.45h** | **Success criterion** |
| B2 | Mean by video_type | Predict mean `hours_creation` per video_type category | 6.80h | Diagnostic |

B1 lift over B0: **1.05h**. B2 is worse than B0 (6.80h vs 6.50h), confirming that video_type groupings are too heterogeneous to use as a standalone lookup — Reviews in particular span 7–53h. Any candidate model must beat **5.45h RMSE** to be considered worthwhile. The ±5h usefulness threshold is not yet met by B1 itself, meaning there is meaningful room for the flag-based models to add value.

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
| M1 | Ridge — flags | `expected_length_mins` (tiered) + `complexity_new` + `complexity_media_depth` + `complexity_delivery_style` | Alpha tuned via TimeSeriesSplit within training set. `complexity_new` has weak bivariate signal (r=0.07); Ridge will shrink it — check coefficient magnitude post-fit. |
| M2 | Ridge — video_type | `expected_length_mins` (tiered) + `video_type` dummies (one reference level dropped) | Direct comparison to M1. Less forward-compatible if new video formats are introduced. |
| M3 | Random Forest | All 6 features: `length_tier_ord` + 3 complexity flags + 2 video_type dummies | Trees handle all features jointly; no need to split flags vs. dummies. Hyperparameters (`max_depth`, `min_samples_leaf`, `n_estimators`) tuned via `GridSearchCV` + `TimeSeriesSplit`. |
| M4 | XGBoost | Same 6 features | Gradient boosting; sequential tree construction. Hyperparameters (`n_estimators`, `max_depth`, `learning_rate`, `subsample`) tuned via `GridSearchCV` + `TimeSeriesSplit`. Only pursued alongside M3; winner selected by mean CV RMSE. |

### M1 vs M2 Diagnosis and Linear Model Winner

Rolling CV RMSE across folds for the raw-target models:

| Model | Fold 1 RMSE | Fold 2 RMSE | Fold 3 RMSE | Mean RMSE | Holdout RMSE |
|-------|-------------|-------------|-------------|-----------|--------------|
| M1-raw | 7.87h | 9.22h | 11.15h | 9.41h | **4.68h** |
| M2-raw | 9.04h | 9.91h | 9.99h | 9.65h | 5.49h |

M1-raw shows a rising RMSE trend across folds (7.87 → 9.22 → 11.15h). In a rolling CV where folds advance in time, a rising trend means the model is becoming progressively worse as the test window moves later — a signature of **temporal distribution shift**. The relationship between complexity flags and `hours_creation` drifted as production matured: recent videos are systematically shorter despite similar flag values (introduction of scene breakdowns, quick unscripted reviews). M1-raw's mean CV RMSE of 9.41h understates the real risk because early folds are easier.

M2-raw is stable across folds (9.04 → 9.91 → 9.99h). `video_type` appeared to be a more temporally consistent predictor — but this stability was later found to be partially a phantom.

**Revised decision — M1-raw is the linear winner:**

After fitting M2-raw, its `video_type` dummies were found to have data integrity problems relative to the train/test split:
- **Scene Breakdowns** appear only in the test set, never in training. `vtype_Scene_Breakdown` is all zeros in training — Ridge learned no coefficient for it. The model predicts scene breakdowns as if they were Reviews (the reference category), relying on `length_tier_ord` alone. This is pure extrapolation.
- **Playthroughs** are heavily represented in training but only once in the test set — not enough to validate the coefficient.

M2-raw's apparent CV stability is partially explained by scene breakdowns not appearing in the CV folds either — the model was never challenged by the category it would later have to predict. The "stability" was the absence of a hard test, not evidence of genuine generalization.

M1-raw at **4.68h holdout RMSE** beats B1 (5.45h) by 0.77h and is genuine: complexity flags are present across all training and test videos, with no category-level extrapolation problem. The rising CV trend reflects real distribution shift (production matured over time), but that shift is visible in the CV diagnostics and can be monitored. M2-raw's extrapolation problem is silent — no CV signal warned of it.

**M1-raw (4.68h) is the Ridge benchmark against which tree models are compared.**

### M3/M4 Results and XGBoost Overfitting Diagnosis

Rolling CV results (mean RMSE across 3 folds):

| Model | Fold 1 RMSE | Fold 2 RMSE | Fold 3 RMSE | Mean RMSE |
|-------|-------------|-------------|-------------|-----------|
| M3 (Random Forest) | 8.89h | 9.78h | 10.24h | 9.64h |
| M4 (XGBoost) | 8.20h | 9.96h | 11.82h | 9.99h |

M4 (XGBoost) shows two warning signs of overfitting:

1. **Rising RMSE trend**: 8.20 → 9.96 → 11.82h. Same pattern as M1-raw — the model performs well on early folds and degrades as the test window moves later. Unlike M1-raw, this is not solely explained by distribution shift; it reflects XGBoost memorising training idiosyncrasies as the training window grows.

2. **Unstable best hyperparameters across folds**: `max_depth` selected as 4 in Fold 1 (25 training videos) but 2 in Folds 2 and 3; `learning_rate` jumped from 0.05 (Folds 1–2) to 0.20 (Fold 3). If the data-generating process were stable, the same hyperparameter configuration should perform best across folds. Large jumps indicate that GridSearchCV is fitting to fold-specific noise rather than true signal.

XGBoost's sequential boosting compounds overfitting at small n: each new tree corrects residuals of the previous tree, which at n=25–57 means trees quickly start fitting noise. M3 (Random Forest) is more robust because it averages independent trees, not sequentially corrected ones.

**Initial winner: M3** with holdout RMSE of **5.11h**, beating B1 (5.45h) by 0.34h but falling short of M1-raw (4.68h) by 0.43h. See M3b below for the flags-only variant run after identifying the vtype dummy integrity issue.

**Hyperparameter sensitivity finding:** The tuning heatmap (`max_depth` × `min_samples_leaf`) showed almost no colour gradient across rows — each column was effectively a single colour. `min_samples_leaf` dominated; `max_depth` was secondary. This is expected at n=73: `min_samples_leaf` sets a hard floor on how many training observations must land in any leaf, constraining tree complexity directly regardless of depth. Once a minimum leaf size is enforced, additional depth restrictions are largely redundant. Practical implication: for any future re-fit, `min_samples_leaf` is the primary knob to tune; `max_depth` can be kept at 2–3 without careful search.

### M3b — Random Forest, Flags Only (No Video_Type Dummies)

After identifying the `video_type` dummy integrity problem (see M1 vs M2 diagnosis above), M3 was re-run without the `vtype_Playthrough` and `vtype_Rankings` dummies. The feature set becomes identical to M1-raw's: `length_tier_ord + complexity_new + complexity_media_depth + complexity_delivery_style`.

**Rationale for M3b:**
- `vtype_Scene_Breakdown` never appeared in training — the tree could not have learned a valid split on it
- `vtype_Playthrough` and `vtype_Rankings` had low feature importance in M3 (0.013 and 0.027 respectively), suggesting they contributed little real signal
- Removing sparse dummies reduces the risk of the tree overfitting to category identity rather than production complexity
- Flags-only features are more robust to new video types being introduced in future — no dummy alignment problem

M3b uses the same `rf_param_grid`, the same `rolling_cv_tree()` function, and the same GridSearchCV + TimeSeriesSplit Layer 1 structure as M3. The only change is `ALL_FEATURES → FLAGS_FEATURES` (4 features instead of 6).

**M3b results are compared directly against M3 (6 features) and M1-raw (4.68h) to determine whether removing dummies helps, hurts, or is neutral.**

**M3b feature importance finding:** After removing the dummies, `complexity_delivery_style` increased in relative importance compared to M3, while `length_tier_ord`, `complexity_media_depth`, and `complexity_new` remained roughly stable. The mechanism: when `vtype_Rankings` is present, the tree learns a shortcut — "Rankings → low hours" — rather than using the underlying production attribute. Rankings videos are predominantly non-scripted/low-effort delivery, so the dummy was absorbing variance that belongs to `complexity_delivery_style`. Without the dummy, the tree is forced to split on the actual driver. This is more generalizable: delivery style captures *why* a video takes fewer hours, not just which category it belongs to. Since future content is expected to include more variety in delivery formats across different video types, `complexity_delivery_style` having higher weight in M3b is a better reflection of the production process than M3's dummy-driven routing.

---

**Why Ridge over plain OLS:** At n=73 training samples, OLS coefficient estimates are noisy — small samples inflate variance, particularly for sparse binary flags. Ridge adds an L2 penalty that shrinks all coefficients proportionally toward zero, reducing overfitting without eliminating any feature. Alpha (the regularization strength) is not hardcoded; it is tuned via `TimeSeriesSplit` cross-validation within the training set.

**Why Ridge over Lasso:** Lasso (L1 regularization) can zero out features entirely. With only 3–4 carefully selected features, automatic elimination is not desirable — all selected features are expected to carry signal. Ridge retains all features with appropriately shrunk coefficients, which is the right behaviour here.

**Why tree-based is in scope**: complexity flags are unlikely to combine additively. A scripted AND wide-scope video may be disproportionately harder than the sum of each flag alone. Trees find these thresholds naturally; linear models require explicit interaction terms that the parameter budget cannot support.

---

### Step 3 — Cross-Validation Strategy

Two layers of CV, serving different purposes:

**Layer 1 — Hyperparameter tuning (inside training set)**
Used for Ridge alpha and tree depth. Use `sklearn.model_selection.TimeSeriesSplit` on the 73-video training set. Prevents data leakage; earlier videos always train, later videos always validate within each fold.

*Why `n_splits=3`:*

Layer 1 CV runs **inside** each outer fold's training window to select Ridge alpha. The smallest outer training window is Fold 1 with 25 videos. `TimeSeriesSplit(n_splits=k)` divides that window into k+1 segments: the last k segments become validation sets, and training always starts from video 1. The minimum inner training size is approximately:

```
min_inner_train ≈ outer_train_size // (k + 1)
```

At k=5: `25 // 6 ≈ 4 videos` in the smallest inner training window. Fitting Ridge on 4 observations with 3–4 predictors leaves almost no degrees of freedom — the coefficient estimates are dominated by noise, and alpha selection becomes arbitrary.

At k=3: `25 // 4 ≈ 6 videos`. Still small, but with 3–4 predictors the model is underdetermined only modestly. The inner fold RMSE values are noisy but carry enough signal to distinguish very small alpha (near-OLS, high variance) from very large alpha (over-regularized, high bias). That distinction is all we need from Layer 1.

Using k=5 does not help here — more inner folds do not compensate for having only 4 training observations per fold. The extra folds just average more noise.

*Why `scoring='neg_root_mean_squared_error'`:*

`RidgeCV` selects alpha by scoring each candidate against inner validation folds and picking the alpha with the best mean score. The choice of scoring metric determines what "best" means.

**Default (R²):**

```
R² = 1 - SS_res / SS_tot
   = 1 - Σ(y - ŷ)² / Σ(y - ȳ)²
```

R² normalizes the residual sum of squares by each fold's total variance (`SS_tot`). A fold with a high-variance target (e.g., one that includes Halloween at 53h or a cluster of Long videos) will have a large `SS_tot`, which shrinks the denominator's contribution to the score. A fold with a low-variance target will have a small `SS_tot`, making the same absolute errors count more. In practice, the alpha that minimizes R²-loss is weighted toward performing well on low-variance folds and can ignore high-variance folds where prediction error matters most.

**RMSE:**

```
RMSE = sqrt( (1/n) * Σ(y - ŷ)² )
```

RMSE does not normalize by fold variance — a 5-hour error counts as a 5-hour error regardless of whether that fold's target ranges from 8h to 12h or from 8h to 53h. Every fold contributes equally to alpha selection in absolute hours. This matches the metric used at all other stages (Layer 2 model selection, holdout evaluation, the B1 success criterion). Using the same metric throughout means the alpha chosen in Layer 1 is directly optimized for the same objective we care about at the end.

**Layer 2 — Model selection (rolling time-series CV)**
Used to choose between M1, M2, M3, M4. Produces multiple RMSE estimates per model so the comparison is not decided by one lucky or unlucky 25-video window.

```
Fold 1: Train [1–25]  → Test [26–41]   → RMSE per model
Fold 2: Train [1–41]  → Test [42–57]   → RMSE per model
Fold 3: Train [1–57]  → Test [58–73]   → RMSE per model
                         Average RMSE across folds → select winner
```

Fold sizing: `start = int(n * 0.35) = 25` (minimum training window); `fold_size = (n - start) // n_folds = (73 - 25) // 3 = 16`. Each test window is 16 videos; training expands by 16 per fold. Minimum training size of 25 ensures enough data for Ridge to be meaningful. Folds are non-overlapping in the test window; training is always expanding (earlier videos are never dropped).

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
2. Run rolling CV (Layer 2) for M1-raw, M1-log, M2-raw, M2-log, M3
3. Select winning model by mean rolling CV RMSE
4. If M3 competitive (within 1h RMSE of best linear), try M4
5. Retrain winner on full training set (videos 1–73)
6. Evaluate once on final holdout (videos 74–98) — report RMSE
7. Run post-fit diagnostics on winning model

---

## Phase 1 — Production Model Decision

**Production model: M1-raw (Ridge, flags + length tier, raw target)**
**Holdout RMSE: 4.68h | Beats B1 by 0.77h**

### Final model comparison

| Model | CV Trend | Holdout RMSE | vs B1 | vs M1-raw |
|-------|----------|--------------|-------|-----------|
| B1 (baseline) | — | 5.45h | — | +0.77h |
| M1-raw (Ridge) | Rising (7.87→9.22→11.15h) | **4.68h** | −0.77h | — |
| M2-raw (Ridge) | Stable | 5.49h | +0.04h | +0.81h |
| M3 (RF, 6 features) | Rising | 5.11h | −0.34h | +0.43h |
| M3b (RF, flags only) | Moderate drift | 4.94h | −0.51h | +0.26h |

### Decision rationale

**Why M1-raw over M3b despite the rising CV trend:**

M1-raw's rising CV fold RMSE (7.87→9.22→11.15h) reflected production process maturation — earlier videos were made under a different workflow. As of early 2026 the production process is stable, meaning the flag→hours relationship captured by M1-raw is expected to hold. The holdout RMSE of 4.68h (covering 25 videos from 2025-02-06 to 2026-01-20) validates this: the model generalised well to the most recent content.

M3b's CV trend was not rising monotonically but was not flat either — it showed moderate fold-to-fold variation, indicating the same underlying instability without the clean story of a single maturation event. M3b is 0.26h worse on holdout.

**Why M1-raw over M3 (with dummies):**

M3 used `vtype_Playthrough` and `vtype_Rankings` dummies. These introduced a dummy-routing problem: the tree learned "Rankings → low hours" as a shortcut instead of the underlying driver (`complexity_delivery_style`). M3b's feature importance confirmed this — removing the dummies increased `complexity_delivery_style`'s weight, which is more generalisable as new video types with varied delivery styles are introduced.

**Why Ridge interpretability matters for this use case:**

M1-raw's coefficients are directly actionable for scheduling:
- `+4.45h per length tier step` (Short→Average→Long)
- `+5.86h for wide-scope media research`
- `+3.42h for scripted delivery`
- `+2.96h for new content`

These can be read off a planned video and summed to get a prediction without running the model. Tree predictions are opaque — you get a number but not a breakdown.

### Ongoing monitoring

The primary risk for M1-raw is renewed drift: if production pace changes again (new equipment, new workflow, new complexity flag combinations), the flag→hours coefficients will become stale. Monitor by:
- Tracking mean residual on new videos over rolling 10-video windows. If mean residual drifts consistently positive (underpredicting), refit.
- Re-evaluating M3b if `complexity_delivery_style` becomes the dominant driver — trees will handle non-linear interactions better if that flag starts interacting strongly with length tier.
