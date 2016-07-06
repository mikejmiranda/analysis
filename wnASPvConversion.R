

#Analysis for Normal Average Sale Price vs Conversion
#Michael Miranda 
#2016-07-06



library(dplyr)
library(plotrix)
library(lubridate)
library(zoo)



setwd("C:/PricingProject")

source("src/analysis/DataProcessFunctions.R")


#Importing CSV
pricingData <- PreparePricingData("csv/All_Rad.csv")



###calculating conversion

#grouping data points....
appIDSummary <- pricingData %>%
                  group_by(T_Date, customerid, AppID, OwnerWarehouseID, Style, Category) %>%
                    summarise(salesQ = sum(SalesQty, na.rm = TRUE),
                              lookups = n())

#need number of distinct lookups and sales. we are grouping every lookup by date, pid, and application into one
##to get rid of double lookups
appIDSummary <- mutate(appIDSummary, distinctLookup = 1)

appIDSummary <- appIDSummary %>%
                  mutate(distinctSale = (salesQ > 0) * 1) 



#combining all pid level data  
pidSummary <- appIDSummary %>%
                group_by(customerid, OwnerWarehouseID, Category) %>%
                  summarise(totalXaction = sum(distinctSale), 
                            totalLookups = sum(distinctLookup),
                            salesQ = sum(salesQ),
                            conv = totalXaction / totalLookups)

###calculating average sale price

cucStyle <- pricingData %>%
            filter(SalesQty > 0) %>%
            group_by(CUC, Style) %>%
              summarise(totalSold = sum(SalesQty),
                        extSales = sum(SalesQty * SalePrice),
                        asp = mean(SalePrice))





          
# create matrix with CUC and scaled ASP
cucScale <- as.data.frame(matrix(c(CUC = cucStyle$CUC, Style = cucStyle$Style, nASP = scale(cucStyle$asp)),ncol = 3))





#renaming columns:
names(cucScale)[1] <- "CUC"
names(cucScale)[2] <- "Style"
names(cucScale)[3] <- "nASP"


aspSummary <- pricingData %>%
  group_by(customerid, Style, CUC) %>%
  summarise(salesQ = sum(SalesQty, na.rm = TRUE))



##combining CUC and customer info...
cucByCustomer <- inner_join(aspSummary,cucScale) %>%
                    filter(salesQ > 0)




#calcuting weighted nasp....

temp <- inner_join(cucByCustomer, cucByCustomer %>% group_by(customerid) %>% summarise(totalCustSales = sum(salesQ)))

temp <- temp %>%
  mutate(wnASP = salesQ / totalCustSales * as.numeric(levels(nASP)[nASP]))




finalAnalysis <- temp %>%
  group_by(customerid) %>%
    summarise(wnASP = sum(wnASP),
              totalQ = sum(salesQ)) %>%
      filter(totalQ > 4)



finalAnalysis2 <- pidSummary %>%
                    group_by(customerid) %>%
                      summarise(conv = sum(totalXaction) / sum(totalLookups))



#final df....
x <- inner_join(finalAnalysis, finalAnalysis2) 




#final plot
plot(x$wnASP, x$conv, main="ASP v Conversion", xlab = "Normalized ASP", ylab = "Conversion")

summary(lm(x$conv~x$wnASP))
