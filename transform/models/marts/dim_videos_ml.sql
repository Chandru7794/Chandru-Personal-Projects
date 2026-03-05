-- dim_videos_ml
-- Extends dim_videos with manually labeled ML features.
-- Join is on video_id (MD5 hash of media_title | video_type | video_subtype).

{{ config(materialized='view') }}

with videos as (
    select * from {{ ref('dim_videos') }}
),

labels as (
    select
        video_id,
        expected_length_mins,
        complexity_new,
        complexity_media_depth,
        complexity_delivery_style,
        complexity_logistics,
        complexity_worklife,
        is_complete
    from {{ ref('video_labels') }}
)

select
    v.*,
    l.expected_length_mins,
    l.complexity_new,
    l.complexity_media_depth,
    l.complexity_delivery_style,
    l.complexity_logistics,
    l.complexity_worklife,
    l.is_complete
from videos as v
left join labels as l on v.video_id = l.video_id
