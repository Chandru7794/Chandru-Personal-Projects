# Exploratory Data Analysis Report: YouTube Workload Dataset

**Prepared by:** Data Science
**Date:** 2026-02-26
**Source file:** `eda/workload_eda.sql`
**Raw data:** `data/Workload.csv`

---

## 1. Executive Summary

The YouTube Workload dataset tracks the time and effort spent on individual video production tasks across a personal YouTube channel. The raw data contained a meaningful number of data quality issues — primarily typographical errors in categorical fields, inconsistent labeling conventions, and a small number of structurally invalid rows. All issues were identifiable and correctable through rule-based cleaning.

All identified data quality issues have been fully resolved. The cleaning pipeline produces `workload_deduped` after four stages of normalization and deduplication. A subsequent combined-session analysis (Section 8) groups consecutive same-workflow sessions separated by ≤15 minutes into single logical work blocks, producing the final modeling-ready table `workload_combined`.

---

## 2. Dataset Overview

| Property | Detail |
|---|---|
| Source | Manual workload log exported to CSV |
| Grain | One row per work session (a single creation activity on a single video) |
| Key columns examined | `media_type`, `media_series`, `media_title`, `video_type`, `video_subtype`, `creation_category`, `date`, `time_start`, `time_end` |

---

## 3. Column-by-Column Findings

### 3.1 `media_type`
**Issue type:** Duplicate variants, invalid value
- Two distinct string variants existed for both `"Movies"` and `"Video Games"`, caused by internal extra whitespace in one variant of each.
- One record with value `"Channel"` was identified as structurally invalid (not a content type).

**Resolution:** Normalized via `TRIM(LOWER(...)) LIKE` pattern matching to canonical values. The `"Channel"` record was dropped in the `WHERE` clause.

---

### 3.2 `creation_category`
**Issue type:** Typographical errors (most prevalent column), irrelevant categories
This was the most data quality-intensive column. Two classes of issues were found:

**Typos or over-descriptive names mapped to canonical values:**

| Raw Value(s) | Mapped To |
|---|---|
| `Recording Audip` | `Recording Audio` |
| `Uploading Video` | `Uploading` |
| `Writing Scriot`, `Writing Script`, `Writinng Script`, `Witing Script`, `Video Notes`, `Video notes`, `Outline` | `Script` |
| `Watching and Editing`, `Watching and Edits`, `Editing Video`, `Editing Audio` | `Editing` |
| `Recording Vide0`, `Recordinng Video`, `Recording  Video` (extra space) | `Recording Video` |
| `Picture`, `Pictures` | `Thumbnail` |

**Categories dropped as out-of-scope for modeling:**

`Monetization`, `Research Youtube`, `Banner`, `Promoting`, `Video Games`, `Reporting`, `SEO`, `Stats`

> **Note:** `Processing Raw Video` was retained after review, as it was deemed relevant in the context of video game content.
> **Note:** `Recording Audio` was also retained, despite being sparse in recent records, as it is a legitimate production step.

---

### 3.3 `media_series`
**Issue type:** NULL values
- 6 rows had a NULL `media_series`, indicating records that could not be attributed to any identifiable series.

**Resolution:** All NULL `media_series` rows dropped.

---

### 3.4 `media_title`
**Issue type:** NULL values, placeholder strings
- A number of rows contained NULL, `"None"`, or `"Entire Channel"` as the title — none of which represent a specific video.
- These rows were largely overlapping with the `media_series` NULL rows (6 rows).

**Resolution:** Rows with NULL, `"None"`, or `"Entire Channel"` in `media_title` dropped.

---

### 3.5 `video_type`
**Issue type:** NULL values
- 7 rows had a NULL `video_type`. One additional NULL was traced to a specific Elden Ring video that could not be categorized.

**Resolution:** All NULL `video_type` rows dropped.

---

### 3.6 `video_subtype`
**Issue type:** Invalid and ambiguous values
- Values identified as problematic: `"Multiple"`, `"N/A"`, `"None"`, `"Rebirth"`, `"Superman Movies"`, `"Terminator Movies"`

**Resolution:** `"Multiple"` and `"N/A"` were dropped via the cleaning rules. `"None"`, `"Rebirth"`, `"Superman Movies"`, and `"Terminator Movies"` were corrected directly in the source CSV.

---

### 3.7 `date`
**Issue type:** NULL values
- A small number of rows had NULL dates. Context inspection (one row before and after each NULL) confirmed the missing dates were unambiguous and could be forward-filled from the preceding row.

**Resolution:** Forward-fill applied using `LAST_VALUE(date IGNORE NULLS)` window function. Zero NULLs remain post-fill (verified).

> **Caveat:** Forward-fill is only appropriate here because the nulls were isolated and contextually clear. This approach was validated manually before applying.

---

### 3.8 `time_start` / `time_end`
**Issue type:** Storage format, midnight-crossing sessions

**Format:** Stored as 12-hour AM/PM strings (e.g., `"10:00:00 PM"`). Converted to 24-hour `HH:MM:SS` strings in `workload_clean` for correct lexicographic sorting and downstream compatibility.

**Midnight sessions:** ~0.9% of records start between 12:00 AM and 4:00 AM. Originally there was an issue with these records having the wrong date. Investigation confirmed this is no longer an issue — corrected in the source data.

---

## 4. Cleaning Rules Summary

| # | Rule | Action |
|---|---|---|
| 1 | `creation_category` typos and irrelevant values | Remap or drop |
| 2 | `media_series` IS NULL | Drop row |
| 3 | `media_title` IS NULL, `"None"`, or `"Entire Channel"` | Drop row |
| 4 | `video_type` IS NULL | Drop row |
| 5 | `video_subtype` IN (`"Multiple"`, `"N/A"`) | Drop row |
| 6 | `media_type` variants of `"Movies"`, `"Video Games"`, `"Channel"` | Normalize or drop |
| 7 | `date` NULLs | Forward-fill from prior row |
| 8 | `time_start` / `time_end` AM/PM string format | Convert to 24-hour `HH:MM:SS` |
| 9 | `creation_category` IS NULL | Drop row |
| 10 | `duration` negative for midnight-crossing sessions | Add 1440 minutes to correct |
| 11 | Exact duplicate rows | Deduplicated via `SELECT DISTINCT` into `workload_deduped` |

---

## 5. Gaps and Recommendations

All previously identified gaps have been resolved. The table below summarises their disposition:

### 5.1 `video_subtype` — Resolved
`"None"`, `"Rebirth"`, `"Superman Movies"`, and `"Terminator Movies"` were corrected directly in the source CSV.

### 5.2 Session Duration Validation — Resolved
A pre-existing `duration` column (in minutes) was validated. Negative values caused by midnight-crossing sessions (where Excel computed `end - start` as a negative fraction of a day) were corrected by adding 1440 minutes. Zero-duration and sessions exceeding 4 hours were flagged for review.

### 5.3 Duplicate Row Detection — Resolved
Exact duplicate rows were detected via `GROUP BY` on all key identifying columns. Duplicates were removed using `SELECT DISTINCT *` into a new table `workload_deduped`, which is the authoritative table for all downstream modeling.

### 5.4 Temporal Coverage — Resolved
Record counts by `month_year` and overall date range were queried to confirm dataset coverage and identify any gaps.

### 5.5 Midnight Date Correction — Resolved
Confirmed no longer an issue; corrected in source data.

### 5.6 `creation_category` NULL Handling — Resolved
NULL `creation_category` rows are now explicitly dropped in `workload_clean` via `AND creation_category IS NOT NULL`.

---

## 6. Data Quality Summary

| Dimension | Assessment |
|---|---|
| Completeness | Good — NULLs identified and resolved in all key columns |
| Consistency | Good — categorical typos and variants fully normalized |
| Validity | Good — all invalid values corrected or removed |
| Accuracy | Good — midnight-crossing duration correction applied |
| Duplication | Good — exact duplicates detected and removed into `workload_deduped` |
| Temporal integrity | Good — date range and monthly coverage verified |

---

## 7. Data Cleaning Pipeline

The raw CSV passes through four sequential cleaning stages before reaching the modeling-ready table. Each stage produces a named table that downstream steps build upon.

```
Workload.csv
    └── workload                   (raw load)
        └── workload_clean         (stage 1: column normalization + row filters)
            └── workload_dates_filled      (stage 2: null date fill + month_year)
                └── workload_durations_fixed   (stage 3: duration correction)
                    └── workload_deduped       (stage 4: deduplication)
                        └── workload_islands   (stage 5: gap detection + island assignment)
                            └── workload_combined  (stage 6: session aggregation) ← use this
```

---

### Stage 0 — Source CSV Fixes
Applied directly in `Workload.csv` before any SQL processing:

| Field | Fix |
|---|---|
| `video_subtype` | Removed invalid values: `"None"`, `"Rebirth"`, `"Superman Movies"`, `"Terminator Movies"` |
| `time_start` / `time_end` | Corrected midnight-crossing session dates |

---

### Stage 1 — `workload_clean`
Row filters (rows dropped if any condition is met):

| Column | Condition |
|---|---|
| `media_series` | IS NULL |
| `media_title` | IS NULL, `"None"`, or `"Entire Channel"` |
| `video_type` | IS NULL |
| `video_subtype` | IN (`"Multiple"`, `"N/A"`) |
| `media_type` | `"Channel"` |
| `creation_category` | IN (`"Monetization"`, `"Research Youtube"`, `"Banner"`, `"Promoting"`, `"Video Games"`, `"Reporting"`, `"SEO"`, `"Stats"`) |
| `creation_category` | IS NULL |

Column transformations:

| Column | Transformation |
|---|---|
| `media_type` | Normalized `"Movies"` and `"Video Games"` variants via pattern matching |
| `creation_category` | 14 typo/variant values remapped to 6 canonical labels |
| `time_start` | Converted from 12-hour AM/PM string to 24-hour `HH:MM:SS` |
| `time_end` | Converted from 12-hour AM/PM string to 24-hour `HH:MM:SS` |

---

### Stage 2 — `workload_dates_filled`

| Column | Transformation |
|---|---|
| `date` | NULL values forward-filled from the last non-null date above each row |
| `month_year` | New derived column added (`YYYY_MM` format) |

---

### Stage 3 — `workload_durations_fixed`

| Column | Transformation |
|---|---|
| `duration` | Negative values (midnight-crossing sessions) corrected by adding 1440 minutes |

---

### Stage 4 — `workload_deduped`

| Action | Detail |
|---|---|
| Exact duplicate removal | `SELECT DISTINCT *` applied across all columns |

---

### Stage 5 — `workload_islands`

Intermediate table used to detect which sessions belong to the same logical work block before aggregation.

| Column added | Description |
|---|---|
| `ts_start` | `date + time_start` cast to TIMESTAMP — the true session start |
| `ts_end_computed` | `ts_start + duration` in minutes — avoids midnight-crossing issues with the stored `time_end` |
| `gap_from_prev_minutes` | Minutes between the previous session's `ts_end_computed` and the current `ts_start`, within the same workflow partition |
| `island_id` | Cumulative sum of new-island flags within each workflow partition — uniquely identifies each combined group |

Partitioned by: `media_title`, `video_type`, `video_subtype`, `creation_category`
Ordered by: `ts_start`

---

### Stage 6 — `workload_combined`

One row per logical work block (island). Single sessions pass through unchanged (`sessions_combined = 1`).

| Column | Aggregation |
|---|---|
| `time_start` | `MIN(time_start)` — earliest start in the group |
| `time_end` | `MAX(time_start)` — start of the last session in the group |
| `duration` | `SUM(duration)` — total work time across all sessions in the group |
| `date`, `month_year`, `media_type`, `media_series` | `MIN(...)` — identical within a group; MIN selects one value |
| `sessions_combined` | Count of raw sessions merged into this row |

---

## 8. Combined Session Analysis

### 8.1 Concept

A **combined session** is a logical work block formed by merging two or more consecutive raw sessions that share the same workflow (identical `media_title`, `video_type`, `video_subtype`, and `creation_category`) and are separated by a gap of ≤15 minutes. The 15-minute threshold reflects the reality that short breaks within the same task (e.g., a quick pause mid-edit) are part of one continuous work effort rather than distinct sessions.

### 8.2 Distribution of Group Sizes

The frequency distribution of how many raw sessions get grouped into each combined session:

| Sessions in group | % of groups | Interpretation |
|---|---|---|
| 1 | ~66% | Solo sessions — not combined with anything |
| 2 | ~23% | Two consecutive sessions merged |
| 3–4 | ~9.5% | Longer uninterrupted work blocks |
| 5–7 | ~1.5% | Extended sessions across many short segments |

Roughly **34% of raw sessions are part of a combined group**, meaning a substantial share of the logged effort represents fragmented work on the same task within a single sitting.

### 8.3 Aggregation Rules

When sessions are merged, the combined row is constructed as follows:

- **Start time:** earliest `time_start` in the group
- **End time:** `time_start` of the last session in the group (per specification)
- **Duration:** sum of `duration` across all sessions in the group
- All workflow-identifying columns (`media_title`, `video_type`, `video_subtype`, `creation_category`) are unchanged — they are identical across all sessions in a group by definition
