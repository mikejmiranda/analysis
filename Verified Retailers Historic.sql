WITH vr_base AS (
SELECT vr.id vr_id
  ,vr.status current_status
  ,vr.brand_id
  ,vr.listing_id
  ,vr.listing_type
  ,CAST(vr.created_at AS DATE) created_date
  ,CONVERT_TIMEZONE('UTC','PST',ISNULL(ar.created_at, vr.created_at)) start_date
  ,CONVERT_TIMEZONE('UTC','PST',LEAD(ar.created_at) OVER (PARTITION BY vr.id ORDER BY ar.created_at ASC)) end_date
  ,ISNULL(CASE WHEN ar.action = 'create' THEN JSON_EXTRACT_PATH_TEXT(ar.audited_changes_json,'status')
               ELSE REPLACE(REPLACE(SPLIT_PART(JSON_EXTRACT_PATH_TEXT(ar.audited_changes_json,'status'), ',',2),'"',''),']','')
               END, CAST(vr.status AS VARCHAR)) base_value
--   ,ar.audited_changes_json base_value
FROM public.verified_retailers vr
  LEFT JOIN audits.verified_retailer ar
    ON vr.id = ar.auditable_id
    AND ar.auditable_type = 'VerifiedRetailer'
WHERE vr.brand_id = 1335
)

, vr_history AS (
SELECT vr_id
  ,current_status
  ,brand_id
  ,listing_id
  ,listing_type
  ,created_date
  ,start_date
  ,end_date
  ,CASE WHEN base_value = '0' THEN 'Pending'
        WHEN base_value = '1' THEN 'Approved'
        WHEN base_value = '2' THEN 'Rejected'
        WHEN base_value = '3' THEN 'Expired'
        ELSE base_value END base_value
FROM vr_base
)

, base_sales AS (
SELECT o.id
  ,CAST(CONVERT_TIMEZONE('UTC','PST',o.order_date) AS DATE) order_date
  ,cm.id core_id
  ,cm.type_cd core_type
  ,cm.menu_override_id
  ,dr.region_name
  ,dr.super_region
  ,dd.cal_year_month
  ,CONCAT(CONCAT(LEFT(dd.month_name,3),'-'),RIGHT(LEFT(dd.calendar_year,4),2)) cal_month
  ,SUM(oi.price * oi.amount) total_rev
FROM oos.orders o
  JOIN oos.order_items oi
    ON o.id = oi.order_id
    AND oi.price < 50000
  JOIN public.brands br
    ON oi.brand_id = br.id
    AND br.id = 1335
  JOIN oos.listings l
    ON o.listing_id = l.id
    AND o.listing_type = l.listing_type - 2
  JOIN oos.accounts ac
    ON o.account_id = ac.id
    AND ac.email NOT LIKE '%weedmaps.com%'
  JOIN (SELECT *, 'Dispensary' type_cd FROM public.dispensaries UNION ALL SELECT *, 'Delivery' FROM public.deliveries) cm
    ON l.wmid = cm.wmid
  JOIN public.regions r
    ON cm.region_id = r.id
  JOIN userdata.dim_region dr
    ON LOWER(r.name) = LOWER(dr.region_name)
  JOIN userdata.dim_date dd
    ON CAST(CONVERT_TIMEZONE('UTC','PST',o.order_date) AS DATE) = dd.calendar_date
WHERE o.status != 0
  AND DATE_TRUNC('WEEK',CAST(CONVERT_TIMEZONE('UTC','PST',o.order_date) AS DATE)) >= GETDATE() - 60
  AND DATE_TRUNC('WEEK',CAST(CONVERT_TIMEZONE('UTC','PST',o.order_date) AS DATE)) <= GETDATE()
GROUP BY o.id
  ,CAST(CONVERT_TIMEZONE('UTC','PST',o.order_date) AS DATE)
  ,cm.id
  ,cm.type_cd
  ,dr.region_name
  ,dr.super_region
  ,cm.menu_override_id
  ,dd.cal_year_month
  ,CONCAT(CONCAT(LEFT(dd.month_name,3),'-'),RIGHT(LEFT(dd.calendar_year,4),2))
)


, audit_base AS (
SELECT DISTINCT core_id
  ,core_type
FROM base_sales
)

, audit_temp AS (
SELECT a.*
  ,b.created_at update_date
  ,SUBSTRING(b.audited_changes_json, POSITION('menu_override_id' IN b.audited_changes_json) + 19,  40) mo_field
FROM audit_base a
  LEFT JOIN audits.dispensary b
    ON a.core_id = b.auditable_id
    AND b.audited_changes_json LIKE '%menu_override_id%'
    AND b.action != 'create'
WHERE a.core_Type = 'Dispensary'

UNION

SELECT a.*
  ,b.created_at update_date
  ,SUBSTRING(b.audited_changes_json, POSITION('menu_override_id' IN b.audited_changes_json) + 19,  40) mo_field
FROM audit_base a
  LEFT JOIN audits.delivery b
    ON a.core_id = b.auditable_id
    AND b.audited_changes_json LIKE '%menu_override_id%'
    AND b.action != 'create'
WHERE a.core_Type = 'Delivery'
)

, final_audit_temp AS (
SELECT *
  ,REPLACE(SPLIT_PART(mo_field, ',', 1),'[','') old_value
  ,REPLACE(REPLACE(REPLACE(SPLIT_PART(mo_field, ',', 2), ']', ''),'}',''),' ','') new_value
FROM audit_temp
)

, final_audit AS (
SELECT core_id
  ,core_type
  ,update_date
  ,LEAD(update_date) OVER (PARTITION BY core_id, core_type ORDER BY update_date) end_date
  ,CASE WHEN LENGTH(old_value) < 9 THEN NULL ELSE old_value*1 END old_override
  ,CASE WHEN LENGTH(new_value) < 9 THEN NULL ELSE new_value*1 END new_override
FROM final_audit_temp
)

, final_data AS (
SELECT a.*
  ,CASE WHEN ab.core_id = a.core_id THEN TRUE ELSE FALSE END has_audit
  ,b.update_date
  ,b.end_date
  ,b.old_override
  ,b.new_override
FROM base_sales a
  LEFT JOIN final_audit b
    ON a.core_id = b.core_id
    AND a.core_type = b.core_type
    AND a.order_date >= CONVERT_TIMEZONE('UTC','PST',b.update_date)
    AND a.order_date <= ISNULL(CONVERT_TIMEZONE('UTC','PST',b.end_date), GETDATE())
  LEFT JOIN (SELECT DISTINCT core_id, core_type FROM final_audit WHERE update_date IS NOT NULL) ab
    ON a.core_id = ab.core_id
    AND a.core_Type = ab.core_type
)

SELECT fd.*
  ,cm.id override_id
  ,cm.core_type override_type
  ,vr.start_date
  ,vr.end_date
  ,vr.base_value
FROM final_data fd
  LEFT JOIN (SELECT *, 'Delivery' core_type FROM core.deliveries UNION SELECT *, 'Dispensary' FROM core.dispensaries) cm
    ON CASE WHEN has_audit IS TRUE THEN fd.new_override ELSE fd.menu_override_id END = cm.wmid
  LEFT JOIN vr_history vr
    ON ISNULL(cm.id, fd.core_id) = vr.listing_id
    AND ISNULL(cm.core_type, fd.core_type) = vr.listing_type
    AND fd.order_date >= vr.start_date
    AND fd.order_date < ISNULL(vr.end_date, GETDATE())
