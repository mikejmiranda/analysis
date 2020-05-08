--Data wrangling audit data to create historic tables for deals

WITH base_data_deals AS (
SELECT auditable_id deal_date_id
  ,associated_id deal_id
  ,created_at change_time
  ,CAST(CONVERT_TIMEZONE('UTC','America/Los_Angeles',created_at) AS DATE) change_date
  ,action action_type
  ,JSON_EXTRACT_PATH_TEXT(audited_changes_json, 'listing_id') listing_id
  ,JSON_EXTRACT_PATH_TEXT(audited_changes_json, 'listing_type') listing_type
  ,SUBSTRING(JSON_EXTRACT_PATH_TEXT(audited_changes_json, 'dtstart'), 1, 10) dtstart
  ,SUBSTRING(JSON_EXTRACT_PATH_TEXT(audited_changes_json, 'dtend'), 1, 10) dtend
  ,JSON_EXTRACT_PATH_TEXT(audited_changes_json, 'rrule') rrule
--   ,audited_changes_json
FROM audits.deal_date dd
)

, summarized_data_deals AS (
SELECT deal_date_id
  ,deal_id
  ,change_time
  ,change_date effective_date
  ,LEAD(change_date) OVER (PARTITION BY deal_date_id ORDER BY change_time ASC) ineffective_date
  ,action_type
  ,CASE WHEN listing_id = '' THEN NULL ELSE listing_id END listing_id
  ,CASE WHEN listing_type = '' THEN NULL ELSE listing_type END listing_type
  ,REPLACE(CASE WHEN action_type = 'update' THEN SPLIT_PART(dtstart, '","', 2) ELSE dtstart END, '"]', '') day_1_start
  ,REPLACE(CASE WHEN action_type = 'update' THEN SPLIT_PART(rrule, '","', 2) ELSE rrule END, '"]', '') new_value
FROM base_data_deals
)

, final_data_temp_deals AS (
SELECT deal_date_id
  ,deal_id
  ,effective_date
  ,ineffective_date
  ,action_type
  ,ISNULL(listing_id, LAG(listing_id) IGNORE NULLS OVER (PARTITION BY deal_date_id ORDER BY change_time)) listing_id
  ,ISNULL(listing_type, LAG(listing_type) IGNORE NULLS OVER (PARTITION BY deal_date_id ORDER BY change_time)) listing_type
  ,ISNULL(day_1_start, LAG(day_1_start) IGNORE NULLS OVER (PARTITION BY deal_date_id ORDER BY change_time)) day_1_start
  ,CASE WHEN new_value LIKE '%WEEKLY%' THEN 'Weekly'
        WHEN new_value LIKE '%DAILY%' THEN 'Daily'
        ELSE 'One Day' END frequency_rule
  ,CASE WHEN new_value LIKE '%BYDAY%' THEN SPLIT_PART(SPLIT_PART(CONCAT(new_value,';'), 'BYDAY=',2), ';', 1) ELSE NULL END day_rule
  ,CASE WHEN new_value LIKE '%UNTIL%' THEN SUBSTRING(new_value, POSITION('UNTIL=' IN new_value) + 6, 8) ELSE NULL END end_date
  ,new_value
FROM summarized_data_deals
)

, final_data_deals AS (
SELECT DISTINCT deal_date_id
  ,deal_id
  ,listing_id
  ,listing_type
  ,ISNULL(dd.calendar_date, CAST(day_1_start AS DATE)) active_date
FROM final_data_temp_deals a
  LEFT JOIN userdata.dim_date dd
    ON CAST(day_1_start AS DATE) <= dd.calendar_date
    AND ISNULL(CAST(end_date AS DATE), CAST(day_1_start AS DATE) + 1) >= dd.calendar_date
    AND LOWER(day_rule) LIKE '%'||LOWER(SUBSTRING(dd.day_name,1,2))||'%'
    AND dd.calendar_date >= a.effective_date
    AND dd.calendar_date <= ISNULL(a.ineffective_date, CAST(GETDATE() AS DATE))
    AND dd.calendar_date < CAST(GETDATE() AS DATE)
WHERE a.action_type != 'destroy'
  AND a.day_1_start != ''
)

SELECT listing_id
  ,listing_type
  ,COUNT(DISTINCT active_date) deals_active_past
FROM final_data_deals
WHERE active_date >= CAST(GETDATE() - 30 AS DATE)
  AND active_date < CAST(GETDATE() AS DATE)
GROUP BY listing_id
  ,listing_type
