/* Cat Dashboard v2
	Last updated 2016-07-13
	Michael Miranda

	Need:
	Ext Quant
	Ext Dollar
	Avg Unit Price
	Margin $
	Margin %
	Margin % with Rebate
	Coupon Redemption % - This is number of transactions with coupon attached
	
	Return %
	Admins
	Cancels
	Adjustments
	Warranties
	Fit Issues
	
	In Stock Lookup % - This will need to be the "adjusted" ISLU%
	Total Conversion - # of Transactions / In Stock lookups - need to adjust for resales and admins/cancels
	Application Conversion - Based on PID, Category, AppID, Date
	In Model Fill Rate - Based on ROH
	
	Distinct Customers - Number of Distinct Customers by Week
	
	Inventory Value
	
*/



/**************************************************************



			Gathering Sales Data...



**************************************************************/
DROP TABLE #SalesData
SELECT b.ClientId CustomerID
	,CONVERT(DATE,b.SOMDateTime) SaleDate
	,c.item
	,c.cuc
	,c.category
	,b.somso
	,b.SOMId
	,b.SOMSalesman
	,a.SODJobberPrice 
	,a.SODCarId
	,c.coretype
	,a.SODItemCost ItemCost
	,SUM(a.SODQuantity) QuantSold
	,a.SODPrice SalePrice
	,SUM(a.SODQuantity * SODPrice) ExtSold --There are cases where multiples of the same line item are split up, this fixes this
	,CASE WHEN ISNULL(adm.SOMSOSOURCE,1) = 1 THEN 0 ELSE 1 END WasAdmin
	,CASE WHEN ISNULL(adj.SOMSOSOURCE,1) = 1 THEN 0 ELSE 1 END WasAdjust
INTO #SalesData
FROM gxWizmo_10.dbo.GXSOMSOD a
	JOIN gxWizmo_10.dbo.GXSOM b
		ON a.SOMId = b.SOMId
	JOIN product_10.dbo.lu_item c
		ON a.SODItem = c.item
--	JOIN misc_10.dbo.LU_DATE LD					--Takes forever; we'll add this in later
--		ON CONVERT(DATE,b.SOMDateTime) = CONVERT(DATE,ld.cal_DATE)
	LEFT JOIN gxWizmo_10.dbo.SOMRELATION ADM
		ON b.SOMSo = adm.SOMSOSOURCE
		AND adm.SOMRELATIONTYPE = 6 --Admin
	LEFT JOIN gxWizmo_10.dbo.SOMRELATION ADJ
		ON b.SOMSo = ADJ.SOMSOSOURCE
		AND adJ.SOMRELATIONTYPE = 5 --Adjustment
	LEFT JOIN gxWizmo_10.dbo.SOMRELATION ADMT
		ON b.SOMSo = admT.SOMSOTARGET
		AND adm.SOMRELATIONTYPE = 6 
WHERE c.category = 'cat_conv'
	AND b.SOMDateTime >= '2015-01-01'
GROUP BY b.ClientId
	,CONVERT(DATE,b.SOMDateTime)
	,c.item
	,c.cuc
	,c.category
	,a.SODJobberPrice
	,b.somso
	,b.SOMId
	,b.SOMSalesman
	,a.SODCarId
	,c.coretype
	,a.SODItemCost
	,a.SODPrice
	,CASE WHEN ISNULL(adm.SOMSOSOURCE,1) = 1 THEN 0 ELSE 1 END
	,CASE WHEN ISNULL(adj.SOMSOSOURCE,1) = 1 THEN 0 ELSE 1 END



--Retreiving coupon information... this is based on any coupon used, not just CAT_CONV specific coupons		
DROP TABLE #CouponData
SELECT c.cuc
	,b.somso
	,a.SODQuantity QuantSold
	,a.SODPrice SalePrice
	,a.SODQuantity * SODPrice ExtSold
	,ROW_NUMBER () OVER (PARTITION BY b.somso ORDER BY b.Somso) Duplicate
INTO #CouponData
FROM gxWizmo_10.dbo.GXSOMSOD a
	JOIN gxWizmo_10.dbo.GXSOM b
		ON a.SOMId = b.SOMId
	JOIN product_10.dbo.lu_item c
		ON a.SODItem = c.item
	JOIN #SalesData SD
		ON b.SOMSo = sd.somSO
WHERE c.category = 'Promo'

--We need to distribute this evenly across all items on the SO. If it appears more than once in the data,
--	then it appears on an SO with multiple line items.
UPDATE a
SET a.QuantSold = a.quantsold/b.SOcount
	,a.saleprice = a.SalePrice/b.SOCount
	,a.extsold = a.ExtSold/b.SOCount
FROM #CouponData a
	JOIN (
			SELECT somSO
				,COUNT(*) SOCount
			FROM #CouponData
			GROUP BY somSO
			) b
		ON a.somSO = b.somSO
		
--Some coupons are showing a positive ExtSold price on returns with a positive Qsold (this should be negative). Fixing:
UPDATE #CouponData
SET QuantSold = ABS(QuantSold) * -1
WHERE ExtSold > 0


--Deleting duplicates....
DELETE FROM #CouponData
WHERE Duplicate > 1

ALTER TABLE #CouponData
DROP COLUMN Duplicate
GO

--Combining sales data with coupon data...
DROP TABLE #FinalSales
SELECT sd.*
	,cd.cuc CouponCode
	,ISNULL(cd.QuantSold,0) CouponQuant
	,ISNULL(cd.ExtSold,0) CouponAmount
INTO #FinalSales
FROM #SalesData SD
	LEFT JOIN #CouponData CD
		ON sd.somSO = cd.somSO

DROP TABLE #SalesData
SELECT *
INTO #SalesData
FROM #FinalSales





--Getting adjustments ready for analysis
DROP TABLE #Prep
SELECT DISTINCT a.somSO
	,b.SOMSOTARGET
	,a.SaleDate
	,CAST(NULL AS INT) DummySO
	,CAST(NULL AS INT) FinalSO
INTO #Prep
FROM #SalesData a
	JOIN gxwizmo_10.dbo.SOMRELATION b
		ON a.somSO = b.SOMSOSOURCE
WHERE b.SOMRELATIONTYPE = 6



/*
	Creating a loop to identify the "final" adjustment. we run this through 10 iterations, which should pick up (almost?) everything.
	This works by linking a "dummy" SO to the SOMrelation table until it doesn't have anything to join to, which is then considered the "Final" SO.
*/

DECLARE @Step INT
SET @Step = 1

WHILE @Step <= 10
BEGIN
	UPDATE #Prep
	SET DummySO = CASE WHEN DummySO IS NULL THEN a.SOMSOTARGET
					   WHEN DummySO IS NOT NULL AND b.Somsotarget IS NOT NULL THEN b.SOMSOTARGET
						   ELSE DummySO END 
		,FinalSO = CASE WHEN DummySO IS NOT NULL AND b.SOMSOTARGET IS NULL THEN DummySO
						   ELSE NULL END 
	FROM #Prep a
		LEFT JOIN gxwizmo_10.dbo.SOMRELATION b
			ON a.DummySO = b.SOMSOSOURCE
			AND SOMRELATIONTYPE = 6

	SET @Step = @Step + 1

END 	




--Need to delete admins...
DELETE FROM a
	FROM #SalesData a
		JOIN gxwizmo_10.dbo.SOMRELATION b
			ON a.somSO = b.SOMSOSOURCE
			AND b.SOMRELATIONTYPE IN (5)

DELETE FROM a
	FROM #SalesData a
		JOIN gxwizmo_10.dbo.SOMRELATION b
			ON a.somSO = b.SOMSOTARGET
			AND b.SOMRELATIONTYPE IN (5)





--Need to delete adjustment credit...
DELETE FROM a
	FROM #SalesData a
		JOIN gxwizmo_10.dbo.SOMRELATION b
			ON a.somSO = b.SOMSOTARGET
			AND b.SOMRELATIONTYPE IN (8)

--...and the adjustments, excluding the final SO	
DELETE FROM a
	FROM #SalesData a
		JOIN #Prep b
			ON a.somSO = b.somSO
	

--Final compilation
DROP TABLE #SalesRollout
SELECT sd.*
	,FirstSale
	,ld.fiscal_week WeekofFirstSale
	,NoOfAdjustments
	,sr.CreditCount --If the SO had a credit for some reason, this column will tell the corresponding credit. Usually for returns
	,sr.LastCredit LastCreditDate
	,w.ReasonName ReturnReason
--SELECT *
INTO #SalesRollout
FROM #SalesData SD
	LEFT JOIN (SELECT Finalso, MIN(SaleDate) FirstSale, COUNT(*) NoOfAdjustments FROM #Prep GROUP BY FinalSO) FP --This is to identify the week of the first sale of the final adjusted SO
		ON sd.somSO = fp.FinalSO
	LEFT JOIN misc_10.dbo.LU_DATE LD
		ON fp.FirstSale =ld.cal_DATE
	LEFT JOIN (
				SELECT SOMSosource
					,COUNT(*) CreditCount
					,MAX(somRelationDateTime) LastCredit 
				FROM gxWizmo_10.dbo.SOMRELATION 
				WHERE SOMRELATIONTYPE = 4 
				GROUP BY somsosource
				) SR
		ON sd.somSO = sr.SOMSOSOURCE
	LEFT JOIN (
				SELECT CAST(pl.pickupqty AS DEC(5,2)) warrantyqty 
					   ,p.pickupsomso OrigSO
					   ,pl.item
					   ,R.ReasonName
				FROM   gxwizmo_10..pickup p 
					   LEFT JOIN gxwizmo_10..pickupline pl 
						 ON p.pickupid = pl.pickupid 
						  LEFT JOIN gxwizmo_10.dbo.Reason R
							ON pl.reasonID = R.reasonID
				WHERE  p.pickuptype IN ( 9 ) 
					   AND ISNULL(p.pickuplogicaldelete,0) = 0
				) w
		ON sd.somSO = w.OrigSO
		AND sd.item = w.ITEM
				
		



--Setting Sale date to the "Original" sale date...
UPDATE #SalesRollout
SET SaleDate = CASE WHEN FirstSale IS NULL THEN SaleDate ELSE FirstSale END




---Removing "part" coupons by giving only one item on the SO full credit for it...
UPDATE a
SET a.CouponQuant = CASE WHEN b.CouponIndex > 1 THEN 0 
						 WHEN b.CouponIndex = 1 AND a.CouponQuant > 0 THEN 1
						 WHEN b.CouponIndex = 1 AND a.couponQuant < 0 THEN -1
						 ELSE 0 END
FROM #SalesRollout a
	JOIN (
			SELECT *
				,ROW_NUMBER () OVER (PARTITION BY Somso ORDER BY somSo) CouponIndex
			FROM #SalesRollout 
			WHERE 1 - ABS(couponquant) > 0
				AND CouponCode IS NOT NULL
		) b
		ON a.somSO = b.somSO
		AND a.item = b.item



/***********************************************************************************************************************


	Gathering Inventory and lookup data - need to calculate instock lookup
	
	
***********************************************************************************************************************/


--Gather data for inventory
SELECT *
INTO #Inventory
FROM (



--Last 30 days
SELECT cuc
	,DATEADD(Day,1,EffectiveDate) InventoryDate
	,SUM(StockWarehouseOnHand) OnHand
FROM RecentHistory_24.dbo.StockWarehouseHistory sw
	JOIN product_10.dbo.lu_item i
		ON sw.StockItem = i.item
WHERE Warehouseid = 30
	AND i.category = 'cat_conv'
	AND StockWarehouseOnHand > 0
GROUP BY cuc
	,DATEADD(Day,1,EffectiveDate) 
	
UNION 

--All other 2016
SELECT cuc
	,DATEADD(Day,1,EffectiveDate) InventoryDate
	,SUM(StockWarehouseOnHand) OnHand
FROM Archivedb.dbo.StockWarehouseHistory_2016 sw
	JOIN product_10.dbo.lu_item i
		ON sw.StockItem = i.item
WHERE Warehouseid = 30
	AND i.category = 'cat_conv'
	AND StockWarehouseOnHand > 0
GROUP BY cuc
	,DATEADD(Day,1,EffectiveDate) 

UNION 
	
--All 2015
SELECT cuc
	,DATEADD(Day,1,EffectiveDate) InventoryDate
	,SUM(StockWarehouseOnHand) OnHand
FROM Archivedb.dbo.StockWarehouseHistory_2015 sw
	JOIN product_10.dbo.lu_item i
		ON sw.StockItem = i.item
WHERE Warehouseid = 30
	AND i.category = 'cat_conv'
	AND StockWarehouseOnHand > 0
GROUP BY cuc
	,DATEADD(Day,1,EffectiveDate) 
)x



--Lookup Information.... This will eventually be our "Base", with our sales table joining onto this one...	
DROP TABLE #Lookups
SELECT DISTINCT CONVERT(DATE, a.lookupDate) LookupDate
	,a.pid
	,a.quoteuser
	,a.cuc
	,a.car_id
	,b.coretype
INTO #Lookups
FROM dw.dbo.LookupSummary  a
	JOIN (SELECT DISTINCT CUC, coretype, category FROM product_10.dbo.lu_item)  b
		ON a.cuc = b.cuc
WHERE b.category = 'cat_conv'


--Full table...
DROP TABLE #LookupRollout
SELECT *
	,0 Lookup
INTO #LookupRollout
FROM (


--Purchases...
SELECT 
	ISNULL(pid,Customerid) CustomerID
	,ISNULL(a.LookupDate, SaleDate) LookupDate
	,ISNULL(a.quoteuser, b.SOMSalesman) QuoteUser
	,ISNULL(a.cuc, b.cuc) CUC
	,ISNULL(a.car_id, b.SODCarId) CarID
	,ISNULL(a.coretype,b.coretype) CoreType
	,item
	,somso
	,SOMId
	,ItemCost
	,QuantSold
	,SalePrice
	,ExtSold
	,WasAdmin
	,WasAdjust
	,CouponCode
	,CouponQuant
	,CouponAmount
	,FirstSale
	,WeekofFirstSale
	,NoOfAdjustments
	,CreditCount
	,LastCreditDate
	,ReturnReason
FROM #SalesRollout b	
	RIGHT JOIN #Lookups a
		ON b.SaleDate = a.lookupDate
		AND b.CustomerID = a.pid
		AND b.SOMSalesman = a.quoteuser 
		AND b.cuc = a.cuc
		AND b.SODCarId = a.car_id
		AND b.QuantSold > 0


UNION
--For some reasons, not all purchases have a lookup... account for that here.

SELECT CustomerID
	,SaleDate
	,SOMSalesman
	,b.CUC
	,SODCarId
	,a.coretype
	,item
	,somso
	,SOMId
	,ItemCost
	,QuantSold
	,SalePrice
	,ExtSold
	,WasAdmin
	,WasAdjust
	,CouponCode
	,CouponQuant
	,CouponAmount
	,FirstSale
	,WeekofFirstSale
	,NoOfAdjustments
	,CreditCount
	,LastCreditDate
	,ReturnReason
FROM #SalesRollout b	
	LEFT JOIN #Lookups a
		ON b.SaleDate = a.lookupDate
		AND b.CustomerID = a.pid
		AND b.SOMSalesman = a.quoteuser 
		AND b.cuc = a.cuc
		AND b.SODCarId = a.car_id
WHERE a.pid IS NULL
	AND b.QuantSold > 0



UNION
--Returns also included

SELECT CustomerID
	,SaleDate
	,SOMSalesman
	,b.CUC
	,SODCarId
	,a.coretype
	,item
	,somso
	,SOMId
	,ItemCost
	,QuantSold
	,SalePrice
	,ExtSold
	,WasAdmin
	,WasAdjust
	,CouponCode
	,CouponQuant
	,CouponAmount
	,FirstSale
	,WeekofFirstSale
	,NoOfAdjustments
	,CreditCount
	,LastCreditDate
	,ReturnReason
FROM #SalesRollout b	
	LEFT JOIN #Lookups a
		ON b.SaleDate = a.lookupDate
		AND b.CustomerID = a.pid
		AND b.SOMSalesman = a.quoteuser 
		AND b.cuc = a.cuc
		AND b.SODCarId = a.car_id
WHERE b.QuantSold < 0


) 
x



--final rollout of combination... 
DROP TABLE #FinalRollout
SELECT CustomerID
	,LookupDate
	,CAST(NULL AS INT) Fiscal_week
	,CAST(NULL AS INT) Fiscal_Month
	,QuoteUser
	,a.CUC
	,a.item
	,CarID
	,CoreType
	,somSO
	,SOMId
	,ItemCost
	,QuantSold
	,ISNULL(QuantSold,0) * ISNULL(ItemCost,0)
	,SalePrice
	,ExtSold
	,CouponCode
	,CouponQuant
	,CouponAmount
	,FirstSale
	,WeekofFirstSale
	,NoOfAdjustments
	,CreditCount
	,LastCreditDate
	,ReturnReason
	,Lookup
	,CASE WHEN ISNULL(B.OnHand,0) > 0 THEN 1 ELSE 0 END InStock
INTO #FinalRollout
FROM #LookupRollout a
	LEFT JOIN #Inventory b
		ON a.CUC = b.cuc
		AND a.LookupDate = b.InventoryDate
		
		

--Adding fiscalweek, fiscalmonth...
UPDATE a
SET a.fiscal_week = d.fiscal_week
	,a.Fiscal_Month = d.FISCAL_MONTH
FROM #FinalRollout		 a
	JOIN misc_10.dbo.LU_DATE d
		ON a.LookupDate = d.cal_DATE



DROP TABLE #Final1
SELECT *
	,ROW_NUMBER () OVER (PARTITION BY Customerid, Lookupdate, CarID ORDER BY CustomerID) LookupCount
	,CAST(0 AS INT) SalesOpp
	,CAST(0 AS INT) InStockSalesOpp
	,CAST(0 AS INT) SalesOppConverted
INTO #Final1
FROM #FinalRollout
WHERE CustomerID NOT IN (300439964, 300413778)
	AND QuoteUser NOT LIKE 'ec%'



--Updating instock values. We are using this to not overstate lookups by only giving one lookup per day per pid per carID
UPDATE a
SET a.SalesOpp = b.SalesOpp
	,a.InStockSalesOpp = b.InStockSalesOpp
	,a.SalesOppConverted = b.SalesOppConverted
FROM #Final1 a
	JOIN (
		SELECT CustomerID
			,LookupDate
			,CASE WHEN CarID = 0 THEN '' ELSE CarID END CarID
			,CASE WHEN SUM(InStock) > 0 THEN 1 ELSE 0 END InStockSalesOpp
			,CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END SalesOpp
			,CASE WHEN SUM(QuantSold) > 0 THEN 1 ELSE 0 END SalesOppConverted
		FROM #FinalRollout
		WHERE QuoteUser NOT LIKE 'ec%'
			AND CustomerID NOT IN (300439964, 300413778)
		GROUP BY CustomerID
			,LookupDate
			,CASE WHEN CarID = 0 THEN '' ELSE CarID END 
		) b
		ON a.CustomerID = b.CustomerID
		AND a.LookupDate = b.LookupDate
		AND CASE WHEN a.CarID = 0 THEN '' ELSE a.CarID END  = b.CarID
WHERE a.CustomerID NOT IN (300439964, 300413778)
	AND QuoteUser NOT LIKE 'ec%'
	AND a.LookupCount = 1

UPDATE #Final1
SET SalesOpp = 0
	,InStock = 0
	,InStockSalesOpp = 0
WHERE ISNULL(QuantSold,0) < 0

--Creating table with "leftover" data	
DROP TABLE #Final2
SELECT *
INTO #Final2
FROM #FinalRollout
	WHERE CustomerID IN (300439964, 300413778)
	OR QuoteUser LIKE 'ec%'
	



--Need to clean up columns we used to give rows a proper value for instock lookups
ALTER TABLE #Final1
DROP COLUMN Lookup
ALTER TABLE #Final1
DROP COLUMN InStock
ALTER TABLE #Final1
DROP COLUMN LookupCount
ALTER TABLE #Final2
DROP COLUMN Lookup
ALTER TABLE #Final2
DROP COLUMN InStock
GO

	
--Final Output...

SELECT a.*
	,CASE WHEN a.InStockSalesOpp = 1 AND b.ROH > 0 THEN 1 ELSE 0 END InModelSaleOpp
	,CASE WHEN a.InStockSalesOpp = 1 AND a.SalesOppConverted = 1 THEN 1 ELSE 0 END InStockSale
	,CASE WHEN QuantSold > 0 THEN QuantSold ELSE 0 END PositiveSales
	,CASE WHEN CouponQuant > 0 THEN CouponQuant ELSE 0 END PositiveCouponQuant
	,CASE WHEN QuantSold < 0 THEN QuantSold ELSE 0 END NegativeSales
	,CASE WHEN CouponQuant < 0 THEN CouponQuant ELSE 0 END NegativeCouponQuant
	,CASE WHEN QuantSold > 0 THEN ExtSold ELSE 0 END GrossSalesDollar
	,CASE WHEN QuantSold < 0 THEN ExtSold ELSE 0 END GrossSalesReturn
FROM 
	(

	SELECT *
	FROM #Final1	
	UNION
	SELECT *
		,0
		,0
		,0
	FROM #Final2	
	 ) a
	 LEFT JOIN _mmiranda.dbo.cat_rohs b
		ON a.CUC = b.StockCUC
		AND a.Fiscal_week = b.EffectiveWeek
		AND b.warehouseid = 30
		
		
		
		
		
		
		