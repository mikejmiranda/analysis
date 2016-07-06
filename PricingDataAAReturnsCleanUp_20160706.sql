
/* Pricing Data clean up
   This SQL query cleans up noise that is left behind by adjustments, admins, cancels, warranties, etc.
   Further work can be done to reduce double lookups (based on application + category), but this is best done in R to retain CUC information
*/
	
	
--Identifying adjustments. Joining from TempPricing to reduce data set.
DROP TABLE #Prep
SELECT DISTINCT a.SO
	,b.SOMSOTARGET
	,a.T_Date
	,CAST(NULL AS INT) DummySO
	,CAST(NULL AS INT) FinalSO
INTO #Prep
FROM _PricingDev.dbo.PricingData a
	JOIN gxwizmo_10.dbo.SOMRELATION b
		ON a.SO = b.SOMSOSOURCE
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



--Finding the original date of the adjusted SO
DROP TABLE #FirstSODate
SELECT FinalSO
	,MIN(T_DAte) FirstSODate
INTO #FirstSODate
FROM #Prep
GROUP BY FinalSO




	
--Final Outpout
DROP TABLE #final
SELECT c.FirstSODate
	,a.*
INTO #Final
FROM _PricingDev.dbo.PricingData a
	LEFT JOIN #Prep b
		ON a.SO = b.SO
	LEFT JOIN #FirstSODate c
		ON a.SO = c.FinalSO
	LEFT JOIN crm_10.dbo.weekly_cust wc
		ON a.customerid = wc.pid
WHERE 1=1 
	AND b.FinalSO IS NULL							--When FinalSO is not NULL, it is not the "final" SO of the adjustment tree. This removes any SOs in the middle of the adjustment tree.
	AND wc.typ != 'Re'
	AND PricingPlan NOT IN ('b1','b2','b3','b4','f1','j2','vp','p3')
	AND QuoteUser NOT IN ('ecmccc','ecom','ecmnxprt','ecmaconx') --Remove Ecom
	AND wc.com NOT LIKE '%Test%'
	AND wc.com NOT LIKE '%1800 Radiator%'
	--AND c.FirstSODate IS NOT NULL					--Anything with a "FirstSO" will be the final adjusted SOs		
	AND QuoteUser NOT IN ('andrewb','davids','julian','jasonm','blakek','kyle','naldana','borisb','jpeter','billm','carlol','phillipc') --Remove as many corp people as possible so long as it does not affect sales



--Admins  -- Deleting from table. 
DELETE FROM a
FROM #Final a
	JOIN gxwizmo_10.dbo.SOMRELATION b
		ON a.SO = b.SOMSOSOURCE
		AND b.SOMRELATIONTYPE = 5
WHERE SalesQty > 0


--Removing various return reasons
DELETE FROM a
FROM #Final a
	JOIN (
			SELECT CAST(pl.pickupqty AS dec(5 ,2)) ReturnQty
				,p.pickupsomso
				,p.PickupCreatedDate
				,IT.category
				,pl.item
				,pl.PickupPrice
				,pl.PickupQty
				,pl.PickupPrice * pl.PickupQty Total
				,R.ReasonName
			FROM gxwizmo_10..pickup p
				LEFT JOIN gxwizmo_10..pickupline pl
					ON p.pickupid = pl.pickupid
				LEFT JOIN gxwizmo_10.dbo.REASON R
					ON pl.ReasonId = R.ReasonId
				LEFT JOIN product_10.dbo.lu_item IT
					ON pl.ITEM = IT.item
			WHERE p.pickuptype IN (9)
				AND p.pickuplogicaldelete IN (NULL ,'0')
				AND CONVERT(DATE,p.PickupCreatedDate) >= (SELECT MIN(T_DATE) FROM #Final)
				AND ReasonName IN ('Cust did not order','Cust refused Delivery','Cust Refused Price','Customer did not need the part','Customer Return / Reason Unknown',
									'Phone mistake','Quality of part Refused','Shop Lost Customer')
			) b
		ON a.Item = b.ITEM
		AND a.so = b.PickupSOMso
		
		
SELECT TOP 100000*
FROM #Final		
WHERE Category = 'comprex'