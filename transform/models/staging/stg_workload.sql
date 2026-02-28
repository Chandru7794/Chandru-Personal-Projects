-- stg_workload
-- Applies all cleaning logic from the EDA (stages 1-5):
--   1. Normalise media_type and creation_category, convert time strings to 24hr
--   2. Drop invalid / out-of-scope rows
--   3. Forward-fill null dates
--   4. Fix negative durations (midnight-crossing sessions)
--   5. Deduplicate via DISTINCT

{{ config(materialized='view') }}

WITH cleaned AS (
    SELECT
        * REPLACE (
            CASE
                WHEN TRIM(LOWER(media_type)) LIKE '%movie%' THEN 'Movies'
                WHEN
                    TRIM(LOWER(media_type)) LIKE '%video%game%'
                    THEN 'Video Games'
                ELSE TRIM(media_type)
            END AS media_type,
            CASE
                WHEN
                    creation_category = 'Recording Audip'
                    THEN 'Recording Audio'
                WHEN creation_category = 'Uploading Video' THEN 'Uploading'
                WHEN creation_category IN (
                    'Writing Scriot', 'Writing Script',
                    'Writinng Script', 'Witing Script',
                    'Video Notes', 'Video notes', 'Outline'
                ) THEN 'Script'
                WHEN creation_category IN (
                    'Watching and Editing', 'Watching and Edits',
                    'Editing Video', 'Editing Audio'
                ) THEN 'Editing'
                WHEN creation_category IN (
                    'Recording Vide0', 'Recordinng Video', 'Recording  Video'
                ) THEN 'Recording Video'
                WHEN
                    creation_category IN ('Picture', 'Pictures')
                    THEN 'Thumbnail'
                ELSE TRIM(creation_category)
            END AS creation_category,
            STRFTIME(STRPTIME(time_start, '%I:%M:%S %p'), '%H:%M:%S')
                AS time_start,
            STRFTIME(STRPTIME(time_end, '%I:%M:%S %p'), '%H:%M:%S') AS time_end
        )
    FROM {{ source('raw', 'workload') }}
    WHERE
        media_series IS NOT NULL
        AND media_title IS NOT NULL
        AND media_title NOT IN ('None', 'Entire Channel')
        AND video_type IS NOT NULL
        AND video_subtype NOT IN ('Multiple', 'N/A')
        AND TRIM(media_type) != 'Channel'
        AND creation_category NOT IN (
            'Monetization', 'Research Youtube', 'Banner',
            'Promoting', 'Video Games', 'Reporting', 'SEO', 'Stats'
        )
        AND creation_category IS NOT NULL
),

numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER () AS rn
    FROM cleaned
),

dates_filled AS (
    SELECT
        * EXCLUDE (rn, date),
        LAST_VALUE(date IGNORE NULLS)
            OVER (
                ORDER BY rn
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
            AS date_workflow
    FROM numbered
),

durations_fixed AS (
    SELECT
        * REPLACE (
            CASE WHEN duration < 0 THEN duration + 1440 ELSE duration END
                AS duration
        )
    FROM dates_filled
)

SELECT DISTINCT
    media_title,
    video_type,
    video_subtype,
    creation_category,
    date_workflow,
    time_start,
    time_end,
    duration,
    media_type,
    media_series
FROM durations_fixed
ORDER BY date_workflow::DATE, time_start
