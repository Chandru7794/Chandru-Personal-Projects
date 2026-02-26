DROP TABLE IF EXISTS workload;

CREATE TABLE workload AS 
SELECT * FROM 'C:\Machine Learning Projects\YouTube Workload\data\Workload.csv';

---lets look at what we have
SELECT * FROM workload;



SELECT media_type, COUNT(*) FROM workload GROUP BY media_type, ORDER BY media_type;
---There is one record called "Channel", delete it
---Two versions of "Movies" in there, need to identify why
---Two versions of "Video Games"




SELECT creation_category, COUNT(*) FROM workload GROUP BY creation_category;
---Recording Audip --> Recording Audio
---Monetization:  Can probably drop
---Uploading Video --> Uploading
---Writing Scriot --> Script
---Subtitles
---Watching and Editing --> Editing
---Recording Vide0 --> Recording Video
---Video Notes --> Script
---Outline --> Script
---Writing Script --> Script
---Picture --> Thumbnail
---Research Youtube:  Drop
---Recording Video:  Fine
---Watching and Edits --> Editing
---Pictures --> Thumbnail
---Reporting:  Drop
---Recording Audio: Keep (but this is not in every video, especially recent ones)
---Banner:  Drop
---Promoting:  Drop
---Video Games:  Drop
---Recording Video:  There is 1 record of this...not sure why its different than the other "Recording Video"
---Editing Video --> Editing
---Writinng Script --> Script
---Video notes --> Script
---Processing Raw Video:  Not sure, look at what these are (looked at them, i think they are relevant for video games)
---Editing Audio --> Editing
---SEO:  drop
---Witing Script --> Script
---Stats:  Drop
---Recording Video:  Again don't know why there is just 1 record of this

SELECT COUNT(*), media_series FROM workload GROUP BY media_series;
--I've cleaned the csv so now just what are the nulls?

SELECT * FROM workload WHERE media_series IS NULL;
----Drop anything where media_series is NULL (6 rows)

SELECT COUNT(*), media_title FROM workload GROUP BY media_title ORDER BY media_title;
---Drop where missing, "None", or "Entire Channel" but might be covered by above (6 rows)

SELECT COUNT(*), video_type FROM workload GROUP BY video_type ORDER BY video_type;
---Drop where missing, (7 rows).  See why there's one more here.  (its an Elden Ring video that i dont know what it is, delete it)


SELECT * FROM workload WHERE video_type IS NULL;

SELECT COUNT(*), video_subtype FROM workload GROUP BY video_subtype ORDER BY video_subtype;
---weird names:  Multiple, N/A, None, Rebirth, Superman Movies, Terminator Movies
---None, Rebirth, Superman Movies, Terminator Movies fixed directly in source CSV
---Multiple and N/A dropped in cleaning rules

SELECT * FROM workload WHERE video_subtype IN ('Multiple','N/A');




-----Cleaning Rules:  
-----1) Address "creation_category" comments above.  
-----2) Drop where `media_series` IS NULL
-----3) Drop where `media_title` IS NULL, "None", or "Entire Channel"
-----4) Drop where `video_type` is NULL
-----5) Drop where 'video_subtype' is 'Multiple' or 'N/A'
-----6) Address media_type comments above

DROP TABLE IF EXISTS workload_clean;

CREATE TABLE workload_clean AS
SELECT * REPLACE (
    CASE
        WHEN TRIM(LOWER(media_type)) LIKE '%movie%'      THEN 'Movies'
        WHEN TRIM(LOWER(media_type)) LIKE '%video%game%' THEN 'Video Games'
        ELSE TRIM(media_type)
    END AS media_type,
    CASE
        WHEN creation_category = 'Recording Audip'                                          THEN 'Recording Audio'
        WHEN creation_category = 'Uploading Video'                                          THEN 'Uploading'
        WHEN creation_category IN ('Writing Scriot','Writing Script',
                                   'Writinng Script','Witing Script',
                                   'Video Notes','Video notes','Outline')                   THEN 'Script'
        WHEN creation_category IN ('Watching and Editing','Watching and Edits',
                                   'Editing Video','Editing Audio')                         THEN 'Editing'
        WHEN creation_category IN ('Recording Vide0','Recordinng Video','Recording  Video') THEN 'Recording Video'
        WHEN creation_category IN ('Picture','Pictures')                                    THEN 'Thumbnail'
        ELSE TRIM(creation_category)
    END AS creation_category,
    strftime(strptime(time_start, '%I:%M:%S %p'), '%H:%M:%S') AS time_start,
    strftime(strptime(time_end,   '%I:%M:%S %p'), '%H:%M:%S') AS time_end
)
FROM workload
WHERE media_series  IS NOT NULL
  AND media_title   IS NOT NULL
  AND media_title   NOT IN ('None', 'Entire Channel')
  AND video_type    IS NOT NULL
  AND video_subtype NOT IN ('Multiple', 'N/A')
  AND TRIM(LOWER(media_type)) != 'channel'
  AND creation_category NOT IN (
           'Monetization','Research Youtube','Banner',
           'Promoting','Video Games','Reporting','SEO','Stats'
       )
  AND creation_category IS NOT NULL;


SELECT * FROM workload_clean LIMIT 40;



----checking cleaned data
SELECT COUNT(*), media_type FROM workload_clean GROUP BY media_type;



SELECT COUNT(*), media_series FROM workload_clean GROUP BY media_series;



SELECT COUNT(*), media_title FROM workload_clean GROUP BY media_title ORDER BY media_title;


SELECT COUNT(*), video_type FROM workload_clean GROUP BY video_type ORDER BY video_type;



SELECT COUNT(*), video_subtype FROM workload_clean GROUP BY video_subtype ORDER BY video_subtype;

SELECT COUNT(*), creation_category FROM workload_clean GROUP BY creation_category ORDER BY creation_category;


---I want to look at the records where date is null
--- Inspect null date rows with 1 row of context before and after each


WITH numbered AS (
    SELECT ROW_NUMBER() OVER () AS rn, *
    FROM workload_clean
),
null_rns AS (
    SELECT rn FROM numbered WHERE date IS NULL
)
SELECT n.*
FROM numbered n
WHERE n.rn IN (
    SELECT nr.rn + delta
    FROM null_rns nr
    CROSS JOIN (VALUES (-1), (0), (1)) AS offsets(delta)
)
ORDER BY n.rn;


--- Forward-fill null dates with the last non-null date above each row
--- This only works because the few missings i had were from one date and it was clear what i needed to do.
---  But i should always do the above check to make sure
CREATE OR REPLACE TABLE workload_dates_filled AS
WITH numbered AS (
    SELECT ROW_NUMBER() OVER () AS rn, *
    FROM workload_clean
)
SELECT
    * EXCLUDE (rn, date),
    LAST_VALUE(date IGNORE NULLS) OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS date,
    strftime(LAST_VALUE(date IGNORE NULLS) OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), '%Y_%m') AS month_year
FROM numbered;

--- Verify no nulls remain
SELECT COUNT(*) AS remaining_null_dates FROM workload_dates_filled WHERE date IS NULL;


----Time Start and Time End.   The only thing left is if a workflow began between 12:00 AM and 4:00 AM, i want a rule that if the workflow starts within an hour of the 
----prior row ending and is on the same video (combination of "media_title", "video_type", and "video_subtype").  It now needs to look at the date of the row in question and
----see if its the same as that prior row.  If it is and the prior row started before midnight, it needs to change the date for the row in question to the next date.
----The justification for this is when i was tabulating my workload, if i was working late and finished one segment after midnight and then started another one soonafter
----i labeled it as the same date as the previous one because i considered it the same day mentally.  But for data analysis, i want it to be correct.
----i want you to start by looking at all segments that start between 12:00 AM and 4:00 AM and see how often this occurs.  And then evaluate whether this is a practical rule.



--- Inspect raw time_start format before filtering
SELECT DISTINCT time_start
FROM workload_dates_filled
ORDER BY time_start
LIMIT 30;

--- Step 1: How often do sessions start between midnight and 4 AM?
SELECT
    COUNT(*)                                                                              AS midnight_starts,
    (SELECT COUNT(*) FROM workload_dates_filled)                                          AS total_rows,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM workload_dates_filled), 2)            AS pct_of_total
FROM workload_dates_filled
WHERE HOUR(time_start::TIME) <= 4;

  ----0.9% of records start in this time period

--- Preview: 10 midnight-4AM records alongside their immediately preceding record
WITH ordered AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY date, time_start::TIME) AS rn,
        date, time_start, time_end, media_title, video_type, video_subtype
    FROM workload_dates_filled
),
midnight_rns AS (
    SELECT rn
    FROM ordered
    WHERE HOUR(time_start::TIME) <= 4
)
SELECT o.*
FROM ordered o
WHERE o.rn IN (SELECT rn     FROM midnight_rns)
   OR o.rn IN (SELECT rn - 1 FROM midnight_rns)
ORDER BY o.rn;

-----Midnight date correction verified as no longer an issue.

--- Session Duration Validation — using existing duration column
--- Negative durations occur when a session crosses midnight (end < start numerically in Excel)
--- Fix: add 24hrs when negative, then convert hours to minutes
--- Inspect zero and extreme sessions

CREATE OR REPLACE TABLE workload_durations_fixed AS
SELECT * REPLACE (
    CASE WHEN duration < 0 THEN duration + 1440 ELSE duration END AS duration
)
FROM workload_dates_filled;

SELECT COUNT(*), duration from workload_durations_fixed GROUP BY duration ORDER BY duration;




--- Counts of suspicious durations (using corrected duration)
SELECT
    COUNT(*) FILTER (WHERE CASE WHEN duration < 0 THEN duration + 1440 ELSE duration END <= 0)  AS zero_duration,
    COUNT(*) FILTER (WHERE CASE WHEN duration < 0 THEN duration + 1440 ELSE duration END > 240) AS over_4hrs
FROM workload_durations_fixed;


--- #3: Duplicate Row Detection
SELECT
    date, time_start, time_end,
    media_title, video_type, video_subtype, creation_category,
    COUNT(*) AS cnt
FROM workload_durations_fixed
GROUP BY date, time_start, time_end, media_title, video_type, video_subtype, creation_category
HAVING COUNT(*) > 1
ORDER BY cnt DESC;

--- Remove duplicates — keep one row per unique combination across all columns
DROP TABLE IF EXISTS workload_deduped;

CREATE TABLE workload_deduped AS
SELECT DISTINCT *
FROM workload_durations_fixed;



--- #4: Temporal Coverage — record counts by month and overall date range
SELECT month_year, COUNT(*) AS sessions
FROM workload_deduped
GROUP BY month_year
ORDER BY month_year;

SELECT
    MIN(date)                          AS earliest_date,
    MAX(date)                          AS latest_date,
    datediff('day', MIN(date), MAX(date)) AS date_span_days
FROM workload_deduped;





----Python Work:   

---I want to see the trend in # of creation categories by month_year



----Feature Engineering:



----Bin length of sessions (look at histograms to get this)
----Combine sessions if they start and end <10 minutes from eachother



----Combined Session EDA
----Logic: sessions in the same workflow (media_title, video_type, video_subtype, creation_category)
----       are combined when the gap from the end of the previous to the start of the current is <= 15 min.
----       ts_end is computed as ts_start + duration to handle midnight-crossing sessions correctly.



DROP TABLE IF EXISTS workload_islands;

CREATE TABLE workload_islands AS
WITH base AS (
    SELECT
        *,
        (date + time_start::TIME)                                     AS ts_start,
        (date + time_start::TIME) + (duration * INTERVAL '1 minute')  AS ts_end_computed
    FROM workload_deduped
),
with_gap AS (
    SELECT
        *,
        DATEDIFF('minute',
            LAG(ts_end_computed) OVER (
                PARTITION BY media_title, video_type, video_subtype, creation_category
                ORDER BY ts_start
            ),
            ts_start
        ) AS gap_from_prev_minutes
    FROM base
),
with_island AS (
    SELECT
        *,
        SUM(CASE WHEN gap_from_prev_minutes IS NULL OR gap_from_prev_minutes > 15 THEN 1 ELSE 0 END)
            OVER (
                PARTITION BY media_title, video_type, video_subtype, creation_category
                ORDER BY ts_start
                ROWS UNBOUNDED PRECEDING
            ) AS island_id
    FROM with_gap
)
SELECT * FROM with_island;


SELECT * FROM workload_islands;



---A) Frequency distribution: how many original sessions get grouped together
---   Sessions_combined=1 means the session was never combined with anything
SELECT
    sessions_combined,
    COUNT(*)                                                                             AS num_groups,
    SUM(sessions_combined)                                                               AS total_raw_sessions,
    ROUND(SUM(sessions_combined) * 100.0 / (SELECT COUNT(*) FROM workload_deduped), 2) AS pct_of_total_sessions
FROM (
    SELECT
        media_title, video_type, video_subtype, creation_category, island_id,
        COUNT(*) AS sessions_combined
    FROM workload_islands
    GROUP BY media_title, video_type, video_subtype, creation_category, island_id
) sizes
GROUP BY sessions_combined
ORDER BY sessions_combined;

---66% are solo sessions, 23% have 2 sessions, 9.5% have 3 or 4 sessions and last 1.5 sessions have 5-7 sessions



---B) Examples: show the raw rows that make up combined sessions (groups of 2+)
---   Pulls the first 10 combined groups found, displaying all their constituent rows
SELECT
    wi.media_title,
    wi.video_type,
    wi.video_subtype,
    wi.creation_category,
    wi.island_id,
    grp.sessions_combined,
    wi.date,
    wi.time_start,
    wi.time_end,
    wi.duration,
    wi.ts_start,
    wi.ts_end_computed,
    wi.gap_from_prev_minutes
FROM workload_islands wi
JOIN (
    SELECT
        media_title, video_type, video_subtype, creation_category, island_id,
        COUNT(*) AS sessions_combined
    FROM workload_islands
    GROUP BY media_title, video_type, video_subtype, creation_category, island_id
    HAVING COUNT(*) >= 2
    ORDER BY sessions_combined DESC, media_title, video_type, video_subtype, creation_category, island_id
    LIMIT 10
) grp
    ON  wi.media_title       = grp.media_title
    AND wi.video_type        = grp.video_type
    AND wi.video_subtype     = grp.video_subtype
    AND wi.creation_category = grp.creation_category
    AND wi.island_id         = grp.island_id
ORDER BY grp.sessions_combined DESC, wi.media_title, wi.video_type, wi.video_subtype, wi.creation_category, wi.island_id, wi.ts_start;


---C) Collapsed combined sessions — one row per combined group (all sessions, singles included)
---   Aggregation rules per views.md:
---     time_start = MIN(time_start)         earliest start in the group
---     time_end   = MAX(time_start)         start of the last session in the group (per spec)
---     duration   = SUM(duration)           total work time across all sessions

DROP TABLE IF EXISTS workload_combined;

CREATE TABLE workload_combined AS
SELECT
    media_title,
    video_type,
    video_subtype,
    creation_category,
    island_id,
    COUNT(*)          AS sessions_combined,
    MIN(date)         AS date,
    MIN(month_year)   AS month_year,
    MIN(media_type)   AS media_type,
    MIN(media_series) AS media_series,
    MIN(time_start)   AS time_start,
    MAX(time_start)   AS time_end,
    SUM(duration)     AS duration
FROM workload_islands
GROUP BY media_title, video_type, video_subtype, creation_category, island_id;

--- Verify against B: same top-10 groups, now shown as 1 collapsed row each
SELECT *
FROM workload_combined
WHERE sessions_combined >= 2
ORDER BY sessions_combined DESC, media_title, video_type, video_subtype, creation_category, island_id
LIMIT 10;



