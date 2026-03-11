-- dim_videos_ml
-- Extends dim_videos with manually labeled ML features.
-- Join is on natural key (media_title, video_type, video_subtype).
-- video_id is computed in stg_workload and carried through dim_videos;
-- video_labels.csv no longer stores it to avoid the circular dependency.

{{ config(materialized='view') }}

with videos as (
    select * from {{ ref('dim_videos') }}
),

labels as (
    select
        expected_length_mins,
        complexity_new,
        complexity_media_depth,
        complexity_delivery_style,
        complexity_logistics,
        complexity_worklife,
        is_complete,
        media_title,
        video_type,
        video_subtype
    from {{ ref('video_labels') }}
)

select
    v.*,
    l.expected_length_mins,

    -- Derived features: mirror src/constants.py
    l.complexity_new,

    l.complexity_media_depth,

    l.complexity_delivery_style,
    l.complexity_logistics,
    l.complexity_worklife,
    l.is_complete,
    case
        when l.expected_length_mins in (7, 10) then 'Short'
        when l.expected_length_mins = 15 then 'Average'
        when l.expected_length_mins in (20, 25, 30) then 'Long'
    end as length_tier,
    case
        when l.expected_length_mins in (7, 10) then 0
        when l.expected_length_mins = 15 then 1
        when l.expected_length_mins in (20, 25, 30) then 2
    end as length_tier_ord
from videos as v
left join labels as l
    on
        v.media_title = l.media_title
        and v.video_type = l.video_type
        and v.video_subtype = l.video_subtype
