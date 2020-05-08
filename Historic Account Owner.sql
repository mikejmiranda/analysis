--Bug in salesforce is creating rows in a weird manner; whenever an account owner switches, it will create a duplicate row
--with the same "before" values. Need to find a way to dedupe and correctly order the history
CREATE TABLE userdata.account_owner_history AS (
WITH owners_1 AS (
SELECT DISTINCT dat.toplevelid top_level_id
  ,a.createddate account_created_date
  ,ah.createddate change_date
  ,ISNULL(u2.name, ah.oldvalue__string) old_owner
  ,ISNULL(u.name, ah.newvalue__string) new_owner
FROM sf.sf_account a
    LEFT JOIN report.daily_account_toplevel dat
        ON a.id = dat.id
    LEFT JOIN sf.sf_accounthistory ah
        ON dat.toplevelid = ah.accountid
        AND ah.field = 'Owner'
    LEFT JOIN sf.sf_user u
        ON ah.newvalue__string = u.id
    LEFT JOIN sf.sf_user u2
        ON ah.oldvalue__string = u2.id
)

, owners_2 AS (
SELECT *
  ,ROW_NUMBER() OVER (PARTITION BY top_level_id ORDER BY change_date ASC) row_rank
FROM owners_1
)

, owners_3 AS (
SELECT top_level_id
  ,change_date start_date
  ,LEAD(change_date) OVER (PARTITION BY top_level_id ORDER BY change_date) end_date
  ,new_owner
FROM owners_1

UNION ALL

SELECT top_level_id
  ,account_created_date start_date
  ,change_date end_date
  ,old_owner
FROM owners_2
WHERE row_rank = 1
)


--need to capture everyday for each account
, full_calendar AS (
SELECT DISTINCT a.*
  ,dd.cal_year_month
FROM owners_3 a
  LEFT JOIN userdata.dim_date dd
    ON CAST(a.start_date AS DATE) <= dd.calendar_date
    AND CAST(ISNULL(a.end_date,GETDATE()) AS DATE) >= dd.calendar_date
    AND dd.calendar_date >= TO_DATE('2017-01-01','yyyy-mm-dd')
    AND dd.calendar_date < DATE_TRUNC('MONTH',CONVERT_TIMEZONE('UTC','America/Los_Angeles',GETDATE()))
)

--row_number to get the most "youngest" row, based on start date
, final_owner AS (
SELECT *
  ,ROW_NUMBER() OVER (PARTITION BY top_level_id, cal_year_month ORDER BY start_date DESC) row_rank
FROM full_calendar
)

SELECT *
FROM final_owner
WHERE row_rank = 1
)
;
