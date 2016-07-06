



DECLARE @GroupID INT
SET @GroupID = 25
	

--The following table displays the groups with their group IDs:
--					SELECT * FROM Accounting_11.dbo.BuyingGroup

--------------

DROP TABLE #MonthlyData
select distinct whse WarehouseID
       ,CU.CustomerID
       ,CU.companyname CompanyName
       ,9 GroupID
       ,BG.Name
       ,MAX(BGM.DateActivated) DateActivated
       ,RIGHT(dt.cal_MONTH,2) Month
       ,LEFT(dt.Cal_Month,4) Year
       ,CASE 
                     WHEN RIGHT(dt.cal_Month,2) BETWEEN 1 and 3 THEN 1
                     WHEN RIGHT(dt.cal_Month,2) BETWEEN 4 and 6 THEN 2
                     WHEN RIGHT(dt.cal_Month,2) BETWEEN 7 and 9 THEN 3
                     WHEN RIGHT(dt.cal_Month,2) BETWEEN 10 and 12 THEN 4
                           END Quarter
       ,ISNULL(SUM(s.SOMTotal),0) ExtAmount
       ,ISNULL(SUM(f.ROY),0) ROY
       ,ISNULL(SUM(f.NTL),0) NTL
       ,ISNULL(SUM(f.LOC),0) LOC
INTO #MonthlyData
from   accounting_11.dbo.buyinggroupmember BGM
       LEFT join     _julian.dbo.vw_customers CU                                                                                         --Customers...
              on     BGM.customerid=CU.customerid
       LEFT JOIN accounting_11.dbo.BuyingGroup BG                                                                                        --Used to identify which MSO
              ON  BGM.GroupID = BG.GroupID
       LEFT JOIN gxwizmo_10.dbo.GXSOM s                                                                                                         --Sales table
              ON s.ClientId = cu.customerid
              AND s.SOMDateTime >= CAST(YEAR(DATEADD(Year,-1,GETDATE())) AS VarChar(4)) + '-01-01'  --Only want from the start of the previous year
       LEFT JOIN misc_10.dbo.LU_DATE dt
              ON CONVERT(DATE,s.SomDateTime) = CONVERT(Date,dt.cal_DATE)
          left       join (
                                  select SaleOrderID
                                         ,SUM(CASE WHEN SaleOrderChargeFeeID IN (113, 114, 104, 105, 123, 133, 131,115, 116, 117) THEN SaleOrderChargeFeeAmount ELSE 0 END) ROY
                                         ,SUM(CASE WHEN SaleOrderChargeFeeID IN (110, 156, 124) THEN SaleOrderChargeFeeAmount ELSE 0 END) NTL
                                         ,SUM(CASE WHEN SaleOrderChargeFeeID IN (111) THEN SaleOrderChargeFeeAmount ELSE 0 END) LOC
                                  FROM gxstatement_23.dbo.SALEORDERCHARGE
                                  GROUP BY SaleOrderID
                           ) F                                                                                                                                             --Used to gather fees
                       ON f.SaleOrderID = s.SOMSo
where  BGM.DateDeactivated is null 
       and    CU.customerstatusid = 1
       AND s.SOMDateTime <= CONVERT(DATE, GETDATE() - DAY(GETDATE()))
       AND bgm.Groupid = @Groupid
group  by CU.CustomerID
       ,CU.companyname
       ,CU.whse
       ,BGM.GroupID
       ,BG.Name
       ,dt.cal_MONTH



--select * from #MonthlyData

------------------------Last Year Data

DROP TABLE #YearSales
SELECT Warehouseid
       ,CustomerID
       ,GroupID
       ,Year
       ,SUM(ExtAmount) LastYearSales
       ,SUM(ROY) Roy
       ,SUM(Loc) Loc
       ,SUM(NTL) Ntl
INTO #YearSales
FROM #MonthlyData
WHERE Year = YEAR(GETDATE())-1
GROUP BY WarehouseID
       ,customerid
       ,GroupID
       ,Year
       

---------------------- Quarter Data

DROP TABLE #QuarterSales
SELECT WarehouseID
       ,customerid
       ,MD.Year
       ,MD.Quarter
       ,GroupID
       ,SUM(ExtAmount) ExtAmount
       ,SUM(ROY) Roy
       ,SUM(Loc) Loc
       ,SUM(NTL) Ntl
INTO #QuarterSales
FROM #MonthlyData MD
       JOIN (
              -- Get complete quarters that have 3 months of full data
              select Year
                     ,Quarter
                     ,COUNT(Distinct Month) MonthCount
              from #MonthlyData
              GROUP BY YEAR
                     ,Quarter
              HAVING COUNT(Distinct Month) = 3
              ) CQ
         ON MD.Year = CQ.Year
          AND MD.Quarter = CQ.Quarter
GROUP BY WarehouseID
       ,customerid
       ,GroupID
       ,MD.Quarter
       ,MD.Year
order by customerid




-- Max Valid Quarter
DROP TABLE #LastQSales
SELECT WarehouseID
       ,Customerid
       ,Year
       ,Quarter
       ,GroupID
       ,ExtAmount
       ,ROY Roy
    ,Loc Loc
    ,NTL Ntl
INTO #LastQSales
FROM #QuarterSales
WHERE Quarter = (
                           SELECT MAX(quarter) Quarter
                           from #quartersales
                           WHERE YEAR = (SELECT MAX(Year) FROM #QuarterSales) 
                           GROUP BY Year
                           )
AND YEAR = (SELECT MAX(Year) From #QuarterSales)

---------------------------- Bi Monthly Data


--Need to find the right combinations of months to use

DROP TABLE #BiMonth
SELECT *
INTO #BiMonth
FROM (
              SELECT Year(DATEADD(Month,-1,GETDATE())) Year
                     ,MONTH(DATEADD(Month,-1,GETDATE())) Month
              UNION
              SELECT Year(DATEADD(Month,-2,GETDATE())) Year
                     ,MONTH(DATEADD(Month,-2,GETDATE())) Month
       ) x
       

       
DROP TABLE #BMSales
SELECT WarehouseID
       ,customerid
       ,GroupID
       ,SUM(extAmount) ExtAmount
       ,SUM(ROY) Roy
    ,SUM(Loc) Loc
    ,SUM(NTL) Ntl
INTO #BMSales
FROM #MonthlyData MD
       JOIN #BiMonth BM
              ON MD.Month = BM.Month
              AND MD.Year = BM.Year
GROUP BY WarehouseID
       ,customerid
       ,GroupID
       
       







---------------------Putting together which numbers are being pulled

DROP TABLE #Rebates
SELECT DISTINCT GroupID
       ,RebatePct
         ,Name
       ,CASE WHEN GroupID IN (22 --BC Group - Tiered
                                                ,25 --Brakes Plus
                                                ,7,9 --Carstar Canada
                                                ,26 --Christian Brothers
                                                ,20,21 --FIX - Tiered
                                                ,14 --ITDG
                                                ,8 --Meineke
                                                ) THEN 'Quarter'
                WHEN GroupID IN (17,18 --TBC - Tiered
                                                ,13 --Aplus - Tiered 
                                                ) THEN 'Annual'
                WHEN GroupID IN (4 --AASP
								,3 --Seidners
								) THEN 'Bi-Monthly'
				WHEN GroupID IN (2 --APN
								) THEN 'Monthly'
                     END Frequency
INTO #Rebates
FROM Accounting_11.dbo.BuyingGroup

UPDATE #Rebates
SET RebatePct = 2
WHERE Name = 'aasp_ma'



-----------------------

DROP TABLE #PreFinal
SELECT DISTINCT cu.customerid
	   ,cu.whse WarehouseID
       ,cu.companyname
       ,bgm.GroupID
       ,r.name
       ,ISNULL(CASE WHEN r.Frequency = 'Quarter' THEN qs.ExtAmount
				  WHEN r.Frequency = 'Bi-Monthly' THEN bs.ExtAmount
				  WHEN r.Frequency = 'Monthly' THEN md.ExtAmount
                  WHEN r.Frequency = 'Annual' THEN ys.LastYearSales
                       END,0) TotalSales
                     
       ,ISNULL(CASE WHEN r.Frequency = 'Quarter' THEN qs.Roy
				  WHEN r.Frequency = 'Bi-Monthly' THEN bs.Roy
				  WHEN r.Frequency = 'Monthly' THEN md.ROY
                  WHEN r.Frequency = 'Annual' THEN ys.Roy
                    END,0) ROY
                  
       ,ISNULL(CASE WHEN r.Frequency = 'Quarter' THEN qs.Ntl
				  WHEN r.Frequency = 'Bi-Monthly' THEN bs.Ntl
				  WHEN r.Frequency = 'Monthly' THEN md.NTL
                  WHEN r.Frequency = 'Annual' THEN ys.Ntl
                    END,0) NTL
                  
       ,ISNULL(CASE WHEN r.Frequency = 'Quarter' THEN qs.Loc
				  WHEN r.Frequency = 'Bi-Monthly' THEN bs.Loc
				  WHEN r.Frequency = 'Monthly' THEN md.Loc
                  WHEN r.Frequency = 'Annual' THEN ys.Loc
                    END,0) LOC
INTO #PreFinal
FROM  accounting_11.dbo.buyinggroupmember BGM
          LEFT JOIN #Rebates r
                       ON bgm.GroupID = r.GroupID
       LEFT join     _julian.dbo.vw_customers CU
              on     BGM.customerid=CU.customerid
       LEFT JOIN #BMSales BS                                                             --BiMonthly Sales Data
                       ON BS.customerid = cu.customerid
                       AND bs.GroupID = bgm.GroupID
          LEFT JOIN #LastQSales QS                                                    --Last Full Quarter Sales Data
                       ON QS.customerid = cu.customerid
                       AND qs.GroupID = bgm.GroupID
          LEFT JOIN #MonthlyData MD                                                   --Last Full Month Sales Data
                       ON MD.customerid = cu.customerid
                       AND md.Month = MONTH(DATEADD(Month,-1,GETDATE()))
                       AND md.Year = YEAR(DATEADD(Month,-1,GETDATE()))
                       AND qs.GroupID = bgm.GroupID
          LEFT JOIN #YearSales YS                                                        --Last Full Year Sales Data
                       ON YS.customerid = cu.customerid
                       AND ys.GroupID = bgm.GroupID
WHERE BGM.DateDeactivated is null 
       and    CU.customerstatusid = 1

------------------------Creation of Final table
DROP TABLE #Final
select r.Frequency
         ,r.Name
       ,r.GroupID
       ,pf.customerid
       ,pf.companyname
       ,pf.TotalSales
       ,pf.WarehouseID
       ,pf.ROY
       ,PF.NTL
       ,PF.LOC
       ,CASE WHEN r.GroupID = 22 AND pf.TotalSales BETWEEN 0 AND 3000 THEN 10 -- BC Group
                WHEN r.GroupID = 22 AND pf.TotalSales > 3000 THEN 15 -- BC Group
                WHEN r.GroupID = 13 AND pf.TotalSales > 3000 THEN 2 --Aplus
                WHEN r.GroupID IN (17,18) AND pf.TotalSales BETWEEN 1000 AND 1999.99 THEN 1 --TBC
                WHEN r.GroupID IN (17,18) AND pf.TotalSales BETWEEN 2000 AND 2999.99 THEN 2
                WHEN r.GroupID IN (17,18) AND pf.TotalSales BETWEEN 3000 AND 3499.99 THEN 3
                WHEN r.GroupID IN (17,18) AND pf.TotalSales > 3499.99 THEN 3.5
                WHEN r.GroupID IN (13) AND pf.TotalSales < 3000 THEN 0 --Aplus
                ELSE r.RebatePct
                     END NewRebatePct --Dynamic Tiered Rebates are included into this "new" rebate percentage
INTO #Final            
from #PreFinal pf
       JOIN #Rebates r
              ON pf.GroupID = r.GroupID
WHERE Frequency IS NOT NULL





-----------------------------------Transaction Summary---------------------


--Getting Start Dates
DROP TABLE #starts
SELECT distinct f.Frequency
	,CASE --Probably a better way to do this (AND could be done a LOT earlier)... 
		  WHEN f.Frequency = 'Quarter' AND MONTH(GETDATE()) BETWEEN 1 AND 3 THEN CAST(YEAR(DATEADD(Month,-3,GETDATE())) AS VARCHAR(4)) + '-10-01'
		  WHEN f.Frequency = 'Quarter' AND MONTH(GETDATE()) BETWEEN 4 AND 6 THEN CAST(YEAR(DATEADD(Month,-3,GETDATE())) AS VARCHAR(4)) + '-01-01'
		  WHEN f.Frequency = 'Quarter' AND MONTH(GETDATE()) BETWEEN 7 AND 9 THEN CAST(YEAR(DATEADD(Month,-3,GETDATE())) AS VARCHAR(4)) + '-04-01'
		  WHEN f.Frequency = 'Quarter' AND MONTH(GETDATE()) BETWEEN 10 AND 12 THEN CAST(YEAR(DATEADD(Month,-3,GETDATE())) AS VARCHAR(4)) + '-07-01'
		  WHEN f.Frequency = 'Bi-Monthly' THEN CONVERT(DATE,DATEADD(Month,-2,GETDATE() - DAY(GETDATE() - 1)))
		  WHEN f.Frequency = 'Monthly' THEN CONVERT(DATE,DATEADD(Month,-1,GETDATE() - DAY(GETDATE() - 1)))
		  WHEN f.Frequency = 'Annual' THEN CAST(YEAR(DATEADD(year,-1,GETDATE())) AS VARCHAR(4)) + '-01-01'
			END StartDate
INTO #Starts
FROM #Final f

	
--Final Transaction History w/ Rebate Table

SELECT f.customerid
	,f.WarehouseID
	,f.GroupID
	,f.Name
	,f.companyname
	,f.NewRebatePct
	,sa.somso SO_Number
	,sa.SOMTotal SO_Total
	,sa.SOMTotal * f.NewRebatePct/100 SO_Rebate
	,CONVERT(Date,sa.SOMDateTime) SO_Date
FROM (SELECT customerid, warehouseid, groupid, name, newrebatepct,Frequency,companyname FROM #Final) f
       JOIN (SELECT * FROM gxwizmo_10.dbo.GXSOM WHERE somdatetime BETWEEN CAST(YEAR(DATEADD(YEAR,-1,GETDATE())) AS VARCHAR(4)) + '-01-01' AND CONVERT(DATE,GETDATE() - DAY(GETDATE()))) sa
              ON sa.ClientId = f.customerid
       JOIN (
				select *,
						CASE WHEN Frequency = 'Quarter' THEN DATEADD(Month,3,StartDate)
							 WHEN Frequency = 'Annual' THEN DATEADD(Year,1,StartDate)
							 WHEN Frequency = 'Monthly' THEN DATEADD(Month,1,StartDate)
							 WHEN Frequency = 'Bi-Monthly' THEN DATEADD(Month,2,StartDate)
								END EndDate
						from #Starts
			) St --Start and End Dates
				ON st.Frequency = f.Frequency
WHERE f.Groupid = @GroupID
	AND CONVERT(Date,sa.SOMDateTime) BETWEEN StartDate AND DATEADD(Day,-1,EndDate)
	--AND  f.customerid NOT IN (200413462,300114987)


----Summary

select distinct f.Frequency
       ,f.Name
       ,f.GroupID
       ,f.NewRebatePct
       ,f.customerid
       ,f.companyname
       ,f.WarehouseID
       ,f.TotalSales
       ,f.TotalSales * (f.NewRebatePct/100) Rebate
       ,f.ROY * (NewRebatePct/100) ROY
       ,f.NTL * (NewRebatePct/100) NTL
       ,f.LOC * (NewRebatePct/100) LOC
FROM #Final    f
WHERE Groupid = @GroupID
	--AND  f.customerid NOT IN (200413462,300114987)