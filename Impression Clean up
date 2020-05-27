INSERT INTO userdata.mm_seg_impressions (
--CREATE TABLE userdata.mm_seg_impressions AS (
WITH base_data_temp AS (
SELECT a.context_event_Location
    ,a.context_region_name
    ,CONVERT_TIMEZONE('UTC','America/Los_Angeles',a.timestamp) impression_date
    ,a.anonymous_id
    ,a.events
FROM seg_web_weedmaps.impression_batched a
WHERE CONVERT_TIMEZONE('UTC','America/Los_Angeles',a.timestamp) >= CAST(GETDATE() AS DATE) - 1
    AND CONVERT_TIMEZONE('UTC','America/Los_Angeles',a.timestamp) < CAST(GETDATE() AS DATE)
    AND a.context_event_location = 'Home'
)

, base_data AS (
SELECT a.context_event_Location
    ,a.context_region_name
    ,a.impression_date
    ,a.anonymous_id
    ,REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(SPLIT_PART(events, '}', b.n_seq), '{', ''), '"', ''), '[', ''), ']', ''), '}','') impression_data
FROM base_data_temp a
    CROSS JOIN (SELECT date_id n_seq FROM userdata.dim_date WHERE date_id <= 100)  b
WHERE LENGTH(a.events) - LENGTH(REPLACE(a.events,'}','')) >= b.n_seq
)

, cleaned_data AS (
SELECT context_event_location
    ,context_region_name
    ,impression_date
    ,anonymous_id
    ,CASE WHEN SUBSTRING(impression_data,1,1) = ',' THEN SUBSTRING(impression_data, 2, LENGTH(impression_data)) ELSE impression_data END impression_data
FROM base_data
)

, section_data AS (
SELECT *
    ,REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('section_name:' IN impression_data), 100), ',', 1), 'section_name:', '') section_name
FROM cleaned_data
)

, final_data AS (
SELECT CONVERT_TIMEZONE('UTC','America/Los_Angeles',CAST(REPLACE(REPLACE(RIGHT(impression_data, 24), 'T', ' '), 'Z', '00') AS TIMESTAMP)) impression_datetime
    ,CAST('Web' AS VARCHAR(7)) platform
    ,anonymous_id
    ,context_event_Location
    ,context_region_name
    ,section_name
    ,CASE WHEN section_name IN ('Deals Nearby','Delivery Services','Dispensary Storefronts','Doctors','Mail Order / Delivery Services', 'CBD Stores') THEN
                REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('listing_id:' IN impression_data), 30), ',', 1), 'listing_id:', '')
          ELSE NULL END listing_id
    ,CASE WHEN section_name IN ('Deals Nearby','Delivery Services','Dispensary Storefronts','Doctors','Mail Order / Delivery Services', 'CBD Stores') THEN
                REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('listing_type:' IN impression_data), 30), ',', 1), 'listing_type:', '')
          ELSE NULL END listing_type
    ,CASE WHEN section_name IN ('Deals Nearby') THEN
                REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('deal_id:' IN impression_data), 30), ',', 1), 'deal_id:', '')
          ELSE NULL END deal_id
    ,CASE WHEN section_name NOT IN ('Deals Nearby','Delivery Services','Dispensary Storefronts','Doctors','Mail Order / Delivery Services', 'CBD Stores') THEN
                REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('brand_id:' IN impression_data), 30), ',', 1), 'brand_id:', '')
          ELSE NULL END brand_id
    ,CASE WHEN section_name NOT IN ('Deals Nearby','Delivery Services','Dispensary Storefronts','Doctors','Mail Order / Delivery Services', 'Featured Brands', 'CBD Stores') THEN
                REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('product_id:' IN impression_data), 30), ',', 1), 'product_id:', '')
          ELSE NULL END product_id
    ,REPLACE(SPLIT_PART(SUBSTRING(impression_data, POSITION('position:' IN impression_data), 30), ',', 1), 'position:', '') section_position
FROM section_data
)

SELECT *
FROM final_data
)
;
