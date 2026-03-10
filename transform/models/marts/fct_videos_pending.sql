-- fct_videos_pending
-- One row per planned video (is_complete = 0) with prediction-ready features.
-- Source of truth is video_labels (seed), NOT dim_videos, because videos with
-- no logged sessions yet do not appear in dim_videos at all.
--
-- length_tier_ord mirrors LENGTH_TIER_ORDINAL in src/constants.py:
--   Short  (7, 10 min)       → 0
--   Average (15 min)         → 1
--   Long   (20, 25, 30 min)  → 2
--
-- This model is consumed by src/predict.py to generate hour estimates
-- for the production model (yt_hours_ridge_v1).

{{ config(materialized='view') }}

with labels as (
    select * from {{ ref('video_labels') }}
    where is_complete = 0
),

videos as (
    select
        media_title,
        video_type,
        video_subtype,
        media_type,
        date_first
    from {{ ref('dim_videos') }}
)

select
    -- video_id is not stored in video_labels (avoids circular dependency);
    -- recompute here using the same hash as stg_workload.
    md5(
        l.media_title || '|' || l.video_type || '|' || l.video_subtype
    ) as video_id,
    l.media_title,
    l.video_type,
    l.video_subtype,
    v.media_type,                      -- null if no sessions logged yet
    v.date_first,                      -- null if no sessions logged yet

    -- Raw input
    l.expected_length_mins,

    -- Derived feature: length tier label
    case
        when l.expected_length_mins in (7, 10) then 'Short'
        when l.expected_length_mins = 15 then 'Average'
        when l.expected_length_mins in (20, 25, 30) then 'Long'
    end as length_tier,

    -- Derived feature: ordinal encoding (model input)
    case
        when l.expected_length_mins in (7, 10) then 0
        when l.expected_length_mins = 15 then 1
        when l.expected_length_mins in (20, 25, 30) then 2
    end as length_tier_ord,

    -- Complexity flags (model inputs)
    l.complexity_new,
    l.complexity_media_depth,
    l.complexity_delivery_style,

    -- Excluded from model but carried for context
    l.complexity_logistics,
    l.complexity_worklife

from labels as l
left join videos as v
        on l.media_title = v.media_title
        and l.video_type = v.video_type
        and l.video_subtype = v.video_subtype
order by l.media_title
