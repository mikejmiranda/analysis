--All pids within five miles of the warehouse.



--Compile pid list
DROP TABLE #Temp1												
SELECT wc.pid												
	,wc.rte_wh											
	,wc.com Companyname											
	,wc.typ Shoptype											
	,wc.price_360																														
	,wc.ad1											
	,wc.city											
	,wc.state											
	,wc.zip											
	,wc.Status											
	,wc.rte_ups											
	,a.latitude PIDLat											
	,a.longitude PIDlong			
	,gwh.WHSELatitude WHLat
	,gwh.WHSELongitude WHLong
	,CAST(NULL as INT) Distance																					
INTO #Temp1												
FROM crm_10.dbo.weekly_cust	wc
	JOIN _boris.dbo.VW_Warehouse wh
		ON wc.rte_wh = wh.warehouseid		
	JOIN wizmo2005_10.dbo.customergeocode a
		ON wc.pid = a.customerID
	JOIN wizmo2005_10.dbo.customergeocodestatus b
		ON a.statusid = b.id
	JOIN gxWizmo_24.dbo.WAREHOUSE gwh
		ON wh.warehouseid = gwh.Warehouseid
WHERE rte_wh != 4												
	AND rte_wh != 16											
	AND rte_ups IN ('a','b','c','d')	
	AND status NOT IN ('x','m','v')		
	and com NOT LIKE ('%800%')
	AND com	NOT LIKE ('%Test%')
	AND com	NOT LIKE ('%Insurance%')
	AND pid != 600251981						
							
																
--Calculating Distance																	
												
UPDATE #Temp1											
SET Distance = Round(3963.1676 * Acos(Sin(round(WHLat,5) --WH LAT												
									 / 57.29577951			
						) * Sin( 						
                       round(PidLAT,5)  --Customer LAT												
                       / 57.29577951) 												
                       + Cos( 												
                                         round(WHLat,5) --WH LAT												
                                         / 57.29577951) * Cos( 												
                             round(PidLAT,5) --Customer LAT												
                             / 57.29577951 												
                                                                     ) * 												
                                          Cos(( 												
                                              round(WHLong,5) --WH LONG												
                                              - round(PidLONG,5) --customer LONG												
                                              ) / 												
                                              57.29577951)), 1) 												

	
	
							
			
SELECT *
FROM #Temp1
WHERE Distance <= 5			
