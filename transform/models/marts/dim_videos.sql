-- dim_videos  (views.md #2)
-- One row per video, with total and stratified duration, date spans,
-- and active days worked -- broken down overall and by processing type.
--
-- Processing types:
--   Pre-Processing  : Processing Raw Video
--   Processing      : Script, Editing, Recording Audio, Recording Video
--   Post-Processing : Thumbnail, Subtitles, Uploading
--   Uncategorised   : catch-all for any future categories

{{ config(materialized='view') }}

WITH with_processing_type AS (
    SELECT
        *,
        CASE
            WHEN creation_category IN (
                'Processing Raw Video', 'Script'
            ) THEN 'Pre-Processing'
            WHEN creation_category IN (
                'Editing', 'Recording Audio', 'Recording Video'
            ) THEN 'Processing'
            WHEN creation_category IN (
                'Thumbnail', 'Subtitles', 'Uploading'
            ) THEN 'Post-Processing'
            ELSE 'Uncategorised'
        END AS processing_type
    FROM {{ ref('combined_sessions') }}
)

SELECT -- noqa: LT08
    video_id,
    MIN(media_title) AS media_title,
    MIN(video_type) AS video_type,
    MIN(video_subtype) AS video_subtype,
    MIN(media_type) AS media_type,
    MIN(media_series) AS media_series,

    -- Overall totals
    ROUND(SUM(duration) / 60.0, 2) AS total_hours,
    MIN(date_workflow) AS date_first,
    MAX(date_workflow) AS date_last,
    DATEDIFF(
        'day', MIN(date_workflow), MAX(date_workflow)
    ) + 1 AS total_day_span,
    COUNT(DISTINCT date_workflow) AS active_days_worked,

    -- Hours by creation_category
    ROUND(SUM(CASE
        WHEN creation_category = 'Editing'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_editing,
    ROUND(SUM(CASE
        WHEN creation_category = 'Processing Raw Video'
            THEN duration
        ELSE 0
    END) / 60.0, 2)
        AS hours_processing_raw_video,
    ROUND(SUM(CASE
        WHEN creation_category = 'Recording Audio'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_recording_audio,
    ROUND(SUM(CASE
        WHEN creation_category = 'Recording Video'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_recording_video,
    ROUND(SUM(CASE
        WHEN creation_category = 'Script'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_script,
    ROUND(SUM(CASE
        WHEN creation_category = 'Subtitles'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_subtitles,
    ROUND(SUM(CASE
        WHEN creation_category = 'Thumbnail'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_thumbnail,
    ROUND(SUM(CASE
        WHEN creation_category = 'Uploading'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_uploading,

    -- Hours by processing type
    ROUND(SUM(CASE
        WHEN processing_type = 'Pre-Processing'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_pre_processing,
    ROUND(SUM(CASE
        WHEN processing_type = 'Processing'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_processing,
    ROUND(SUM(CASE
        WHEN processing_type = 'Post-Processing'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_post_processing,
    ROUND(SUM(CASE
        WHEN processing_type = 'Uncategorised'
            THEN duration
        ELSE 0
    END) / 60.0, 2) AS hours_uncategorised,

    -- Pre-Processing dates and spans
    MIN(CASE WHEN processing_type = 'Pre-Processing' THEN date_workflow END)
        AS pre_processing_date_first,
    MAX(CASE WHEN processing_type = 'Pre-Processing' THEN date_workflow END)
        AS pre_processing_date_last,
    DATEDIFF(
        'day',
        MIN(CASE
            WHEN processing_type = 'Pre-Processing'
                THEN date_workflow
        END),
        MAX(CASE
            WHEN processing_type = 'Pre-Processing'
                THEN date_workflow
        END)
    ) + 1 AS pre_processing_total_day_span,
    COUNT(DISTINCT CASE
        WHEN processing_type = 'Pre-Processing'
            THEN date_workflow
    END) AS pre_processing_active_days,

    -- Processing dates and spans
    MIN(CASE WHEN processing_type = 'Processing' THEN date_workflow END)
        AS processing_date_first,
    MAX(CASE WHEN processing_type = 'Processing' THEN date_workflow END)
        AS processing_date_last,
    DATEDIFF(
        'day',
        MIN(CASE WHEN processing_type = 'Processing' THEN date_workflow END),
        MAX(CASE WHEN processing_type = 'Processing' THEN date_workflow END)
    ) + 1 AS processing_total_day_span,
    COUNT(DISTINCT CASE
        WHEN processing_type = 'Processing'
            THEN date_workflow
    END) AS processing_active_days,

    -- Post-Processing dates and spans
    MIN(CASE WHEN processing_type = 'Post-Processing' THEN date_workflow END)
        AS post_processing_date_first,
    MAX(CASE WHEN processing_type = 'Post-Processing' THEN date_workflow END)
        AS post_processing_date_last,
    DATEDIFF(
        'day',
        MIN(CASE
            WHEN processing_type = 'Post-Processing'
                THEN date_workflow
        END),
        MAX(CASE
            WHEN processing_type = 'Post-Processing'
                THEN date_workflow
        END)
    ) + 1 AS post_processing_total_day_span,
    COUNT(DISTINCT CASE
        WHEN processing_type = 'Post-Processing'
            THEN date_workflow
    END) AS post_processing_active_days

FROM with_processing_type
GROUP BY video_id
ORDER BY MIN(date_workflow)
