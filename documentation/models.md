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

Secondary target to consider: total unique days worked on the video.

### Features - Must Be Known Before Starting the Video
`media_type` - Definitely will have an impact but does it even make sense to make a model including both?  or 2 separate models?
`media_series` - I think this probably useful ONLY in that maybe having an ordinal variable (like first, second, third in series) could be useful. Consider capping position (e.g. min(position, 5)) — position 1 vs 2 matters, position 12 vs 13 probably doesn't.

UPDATE:  `media_series` is too sparse.  I will handle this with it being a component of "complexity" (basically if its the first in a series that I'm doing, it adds to the complexity)

`media_title` - I dont think this will be useful
`video_type` - i think this is useful with `media_type` and `video_subtype`
`expected video duration` - likely one of the strongest predictors. A 30-min video almost certainly takes longer to produce than a 10-min one, and target length is known before starting.
**Complexity Flags** (binary 0/1 unless noted; all assigned prospectively before work begins)

`complexity_new` — 1 if: new video series, first time doing something on-camera or technically, or first time watching the source material. Captures startup/unfamiliarity overhead.

`complexity_media_depth` — Binary. 1 = wide range of topics covered (e.g. a full movie review covering themes, characters, plot); 0 = narrow/focused scope (e.g. a single boss review, a scene breakdown covering one scene).

`complexity_delivery_style` — 1 = fully scripted, not adlibbing recordings; 0 = notes-based with adlibbed delivery. Scripted (1) is the target standard for reviews going forward.

`complexity_logistics` — 1 if external circumstantial disruptions were present during production: vacation, travel, or major life events (new job, job loss, significant personal change). Caution: some events are not predictable at video start, making this partially retrospective. Expected to be a stronger predictor of `total_day_span` than `hours_creation`.

`complexity_worklife` — 0 = free to work on videos without constraints; 1 = forced to work in limited intervals due to work-life balance pressures. Primary predictor for `total_day_span` rather than `hours_creation`.






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
