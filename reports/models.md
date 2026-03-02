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
Total hours of Pre-Processing + Processing. Post-Processing excluded (mechanical, predictable on its own).
Secondary target to consider: total unique days worked on the video.

### Features - Must Be Known Before Starting the Video
`media_type` - Definitely will have an impact but does it even make sense to make a model including both?  or 2 separate models?
`media_series` - I think this probably useful ONLY in that maybe having an ordinal variable (like first, second, third in series) could be useful. Consider capping position (e.g. min(position, 5)) — position 1 vs 2 matters, position 12 vs 13 probably doesn't.
`media_title` - I dont think this will be useful
`video_type` - i think this is useful with `media_type` and `video_subtype`
`expected video duration` - likely one of the strongest predictors. A 30-min video almost certainly takes longer to produce than a 10-min one, and target length is known before starting.
`complexity` - High / Medium / Low. Needs a rules-based definition decided *before* labeling historical data — avoid letting outcome (how long it took) influence the label.

I need to figure out what features make sense. Obviously, i can build a regression model based on time duration of various editing processes BUT that won't lend itself to being a predictive model.  We need to have features that we know ahead of time.

I wonder if building a model that predicts # of hours or day span is really that useful?  because i can't use a lot of things because those things are only KNOWN after i build the video and have all the data (things like "time spent editing")

### Known Risks and Constraints

**Sample size** - ~108 usable videos after cleaning. Biggest practical constraint. Before modeling, validate row counts per `media_type x video_type x video_subtype` segment. Any cell under ~20 rows is a red flag. This is the most likely reason the project becomes impractical.

**Learning/temporal drift** - Production speed has likely improved over time through experience, independent of content type. A model trained equally on all historical data will underestimate current pace. Options: add a time-based feature, apply recency weighting, or restrict training to recent data.

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
