Views to create:
1) Combined session views
    a) Apply the full cleaning logic from the EDA that gets all the way to `workload_deduped` (just want one table). 
    b) If a row ends within 15 minutes (<=15) of the next row beginning and its the same workflow (combination of `media_title`, `video_type`, `video_subtype` and `creation_category`), i want the sessions to be combined (could be 2 or more).  Keep the start time as the minimum start time of the group and the end time as the maximum end time of the group but the duration should be the sum of `duration` across the group

2) Video views (need to define more)
    a) I want one row per video
    b) columns to include
        i) total minutes worked on
        ii) minutes stratified by creation category
        iii) day span (# of days)  and i want columns of this broken down by below
        iv) i want three different processing types which is determined by `creation_category` 
                A) "Processing Raw Video": "Pre-Processing"
                B) ("Thumbnail", "Subtitles", "Uploading"): "Post-Processing"
                C) ("Script", "Editing", "Recording Audio", "Recording Video): "Processing"
        v) I want min and max dates for overall video and each of the three processing types 

3) Overlapping videos view
    a) i wonder if the grain for this one should be by day, by week, by month, by video?
    b) overlapping should only be if processing is overlapping (not pre processing or post processing)


3) Weekly views
4) monthly views
5) Maybe a view of the earliest i start in a day and the latest i end in a day?
6) 