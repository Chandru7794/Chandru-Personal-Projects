-- combined_sessions  (views.md #1)
-- Collapses consecutive same-workflow sessions separated by <= 15 minutes
-- into a single logical work block.
--
-- Aggregation rules (per views.md):
--   time_start       = MIN(time_start) across the group
--   time_end         = MAX(time_end) across the group
--   duration         = SUM(duration)  across the group
--   sessions_combined = count of raw sessions merged
--
-- TODO: implement (translate workload_eda.sql combined-session logic into CTEs)

{{ config(materialized='view') }}

select *
from {{ ref('stg_workload') }}
