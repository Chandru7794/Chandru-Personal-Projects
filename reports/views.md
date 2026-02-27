Views to create:
1) Combined session views
    a) Apply the full cleaning logic from the EDA that gets all the way to `workload_deduped` (just want one table). 
    b) If a row ends within 15 minutes (<=15) of the next row beginning and its the same workflow (combination of `media_title`, `video_type`, `video_subtype` and `creation_category`), i want the sessions to be combined (could be 2 or more).  Keep the start time as the minimum start time of the group and the end time as the maximum end time of the group but the duration should be the sum of `duration` across the group

2) Video views (need to define more)
3) Weekly views
4) monthly views