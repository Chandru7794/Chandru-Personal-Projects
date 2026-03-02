-- combined_sessions  (views.md #1)
-- Collapses consecutive same-workflow sessions separated by <= 15 minutes
-- into a single logical work block.
--
-- Aggregation rules (per views.md):
--   time_start        = MIN(time_start) across the group
--   time_end          = MAX(time_end)   across the group
--   duration          = SUM(duration)   across the group
--   sessions_combined = count of raw sessions merged

{{ config(materialized='view') }}

WITH base AS (
    SELECT
        *,
        (date_workflow + time_start::TIME) AS ts_start,
        (date_workflow + time_start::TIME)
        + (duration * INTERVAL '1 minute') AS ts_end_computed
    FROM {{ ref('stg_workload') }}
),

with_gap AS (
    SELECT
        *,
        DATEDIFF(
            'minute',
            LAG(ts_end_computed) OVER (
                PARTITION BY
                    video_id, creation_category
                ORDER BY ts_start
            ),
            ts_start
        ) AS gap_from_prev_minutes
    FROM base
),

with_session AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN
                    gap_from_prev_minutes IS NULL
                    OR gap_from_prev_minutes > 15
                    THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY
                video_id, creation_category
            ORDER BY ts_start
            ROWS UNBOUNDED PRECEDING
        ) AS session_id
    FROM with_gap
)
SELECT -- noqa: LT08
    video_id,
    -- several columns are constant within a video_id group;
    -- MIN() is used to satisfy GROUP BY without adding redundant keys
    MIN(media_title) AS media_title,
    MIN(video_type) AS video_type,
    MIN(video_subtype) AS video_subtype,
    creation_category,
    session_id,
    MIN(date_workflow)::DATE AS date_workflow,
    COUNT(*) AS sessions_combined,
    MIN(media_type) AS media_type,
    MIN(media_series) AS media_series,
    MIN(time_start) AS time_start,
    MAX(time_end) AS time_end,
    SUM(duration) AS duration
FROM with_session
GROUP BY video_id, creation_category, session_id
ORDER BY MIN(date_workflow)::DATE, MIN(time_start)
