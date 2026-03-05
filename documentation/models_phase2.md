# Phase 2 - Retrospective Lever Analysis (Dashboard)

Retrospective statistical analysis of which working behaviors correlate with efficiency. Output is a refreshing dashboard, not a deployed model.

Note: the levers below are features computed *after* a video is complete. This makes them useless for the Phase 1 predictive model but valid for a retrospective statistical study. This is a regression/correlation analysis problem, not a machine learning problem — sample size doesn't support ML here. Output is a dashboard that refreshes as new videos are completed.

---

## Levers to Investigate

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

---

## Caution

Levers aren't randomly assigned. Working nights correlates with being busy overall, which correlates with content type. Observed correlations may be confounded — interpret carefully and avoid causal language without further analysis.
