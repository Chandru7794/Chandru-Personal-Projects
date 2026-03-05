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
**Description:** What type of media video is on (video games, movies, may eventually include tv shows)
**Issue type:** Duplicate variants, invalid value
- Two distinct string variants existed for both `"Movies"` and `"Video Games"`, caused by internal extra whitespace in one variant of each.
- One record with value `"Channel"` was identified as structurally invalid (not a content type).

**Resolution:** Normalized via `TRIM(LOWER(...)) LIKE` pattern matching to canonical values. The `"Channel"` record was dropped in the `WHERE` clause.

---

### 3.2 `creation_category`
**Description:** The specific workflow (editing, recording video, thumbnail).  These need to be normalized
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

**NULL values:** Rows where `creation_category` IS NULL were also dropped explicitly.

---

### 3.3 `media_series`
**Description:** What series it belongs to (ie "Indiana Jones Series")
**Issue type:** NULL values
- 6 rows had a NULL `media_series`, indicating records that could not be attributed to any identifiable series.

**Resolution:** All NULL `media_series` rows dropped.

---

### 3.4 `media_title`
**Description:** Exact title of movie or video game
**Issue type:** NULL values, placeholder strings
- A number of rows contained NULL, `"None"`, or `"Entire Channel"` as the title — none of which represent a specific video.
- These rows were largely overlapping with the `media_series` NULL rows (6 rows).

**Resolution:** Rows with NULL, `"None"`, or `"Entire Channel"` in `media_title` dropped.

---

### 3.5 `video_type`
**Description:** A category for the type of video this is ("review", "ranking", "playthrough" etc)
**Issue type:** NULL values
- 7 rows had a NULL `video_type`. One additional NULL was traced to a specific Elden Ring video that could not be categorized.

**Resolution:** All NULL `video_type` rows dropped.

---

### 3.6 `video_subtype`
**Description:** This is more granular than video type but may not be super generalizable because it often is a one-off.
**Issue type:** Invalid and ambiguous values
- Values identified as problematic: `"Multiple"`, `"N/A"`, `"None"`, `"Rebirth"`, `"Superman Movies"`, `"Terminator Movies"`

**Resolution:** `"Multiple"` and `"N/A"` were dropped via the cleaning rules. `"None"`, `"Rebirth"`, `"Superman Movies"`, and `"Terminator Movies"` were corrected directly in the source CSV.

---

### 3.7 `date`
**Description:** When  the workflow began
**Issue type:** NULL values
- A small number of rows had NULL dates. Context inspection (one row before and after each NULL) confirmed the missing dates were unambiguous and could be forward-filled from the preceding row.

**Resolution:** Forward-fill applied using `LAST_VALUE(date IGNORE NULLS)` window function. Zero NULLs remain post-fill (verified).

> **Caveat:** Forward-fill is only appropriate here because the nulls were isolated and contextually clear. This approach was validated manually before applying.

---

### 3.8 `time_start` / `time_end`
**Description:** time stamps
**Issue type:** Storage format, midnight-crossing sessions

**Format:** Stored as 12-hour AM/PM strings (e.g., `"10:00:00 PM"`). Converted to 24-hour `HH:MM:SS` strings in `workload_clean` for correct lexicographic sorting and downstream compatibility.

**Midnight sessions:** ~0.9% of records start between 12:00 AM and 4:00 AM. Originally there was an issue with these records having the wrong date. Investigation confirmed this is no longer an issue — corrected in the source data.

---

### 3.9 `duration`
**Description:** a calculated field (within the csv that uses `time_start` and `time_end`)
**Issue type:** Negative values from midnight-crossing sessions
- The `duration` column (in minutes) was pre-existing in the source data.
- Midnight-crossing sessions produced negative values because Excel computed `end - start` as a negative fraction of a day.
- Zero-duration sessions and sessions exceeding 4 hours were also flagged for review.

**Resolution:** Negative values corrected by adding 1440 minutes in `workload_durations_fixed` (Stage 3 of the cleaning pipeline).

---

### 3.10 Duplicate Rows
**Issue type:** Exact duplicate records
- Exact duplicate rows were detected via `GROUP BY` on all key identifying columns.

**Resolution:** Duplicates removed using `SELECT DISTINCT *` into `workload_deduped`, which is the authoritative table for all downstream modeling.

---


---

## 4. Data Quality Summary

| Dimension | Assessment |
|---|---|
| Completeness | Good — NULLs identified and resolved in all key columns |
| Consistency | Good — categorical typos and variants fully normalized |
| Validity | Good — all invalid values corrected or removed |
| Accuracy | Good — midnight-crossing duration correction applied |
| Duplication | Good — exact duplicates detected and removed into `workload_deduped` |
| Temporal integrity | Good — date range and monthly coverage verified |

---



## 5. Combined Session Analysis

### 5.1 Concept

A **combined session** is a logical work block formed by merging two or more consecutive raw sessions that share the same workflow (identical `media_title`, `video_type`, `video_subtype`, and `creation_category`) and are separated by a gap of ≤15 minutes. The 15-minute threshold reflects the reality that short breaks within the same task (e.g., a quick pause mid-edit) are part of one continuous work effort rather than distinct sessions.

### 5.2 Distribution of Group Sizes

The frequency distribution of how many raw sessions get grouped into each combined session:

| Sessions in group | % of groups | Interpretation |
|---|---|---|
| 1 | ~66% | Solo sessions — not combined with anything |
| 2 | ~23% | Two consecutive sessions merged |
| 3–4 | ~9.5% | Longer uninterrupted work blocks |
| 5–7 | ~1.5% | Extended sessions across many short segments |

Roughly **34% of raw sessions are part of a combined group**, meaning a substantial share of the logged effort represents fragmented work on the same task within a single sitting.

### 5.3 Aggregation Rules

When sessions are merged, the combined row is constructed as follows:

- **Start time:** earliest `time_start` in the group
- **End time:** `time_start` of the last session in the group (per specification)
- **Duration:** sum of `duration` across all sessions in the group
- All workflow-identifying columns (`media_title`, `video_type`, `video_subtype`, `creation_category`) are unchanged — they are identical across all sessions in a group by definition
