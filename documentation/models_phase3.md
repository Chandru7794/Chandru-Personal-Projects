# Phase 3 - Lever Impact Evaluation

After changing behaviors based on Phase 2 findings, re-evaluate the Phase 1 model to see if predictions improve.

Note: need to separate lever-driven improvement from natural improvement over time (getting faster through experience). Use Phase 1 model residuals over time as a baseline drift metric before attributing gains to the levers.

---

## Secondary Models (Backlog)

1. Predicting How Long a Workflow Session Will be based on time started, creation category, day of week, etc.
    - This can be useful because MAYBE a prediction like this can be used to then be able to predict how many days a video will take?
    - Session-level data has far more rows than video-level — more tractable for ML than the primary model
    - Session model could feed into video-level estimates: predict session length, multiply by expected session count per video type
