# Analysis for CUC C-2056
# This showcases the average 30 day sale price over the last two years
# as well as showing the probability that a price will land between a certain range
#
# Michael Miranda
# 2016-07-06


# Setting work directory...
setwd("C:/PricingProject/")

library(dplyr)
library(plotrix)
library(lubridate)
library(zoo)

source("src/DataProcessFunctions.R")

pricingData <- PreparePricingData("csv/CUC_C-2056_Data.csv")



# Taking only the columns we want

cleanData <- pricingData %>%
  select(
    date = T_Date,
    OwnerWarehouseID,
    SkuLevel,
    InStock,
    qty = SalesQty,
    SalePrice,
    ScreenPrice,
    PricingPlan,
    PricingPlanImpact,
    Style,
    CouponInd,
    CouponAmount
    )

# Summarize...

salesCounts <- summarise(
  cleanData,
  lookups = n(),
  totalQuant = sum(qty, na.rm = TRUE),
  transactions = lookups - sum(is.na(qty)),
  conversion = (lookups - sum(is.na(qty))) / lookups
  )


# Pricing Plan Summary
pricingPlanSummary <- cleanData %>%
  group_by(PricingPlan) %>%
  summarise(
    lookups = n(),
    totalQty = sum(qty, na.rm = T),
    saleCount = lookups - sum(is.na(qty)),
    revenue = sum(SalePrice, na.rm = T),
    conversion = saleCount / lookups,
    ASP = revenue / totalQty
  )





# Overall Summary
cleanData %>%
  summarise(
    lookups = n(),
    totalQty = sum(qty, na.rm = T),
    transactions = lookups - sum(is.na(qty)),
    revenue = sum(SalePrice * qty, na.rm = T),
    conversion = transactions / lookups,
    AvgSellPrice = revenue / totalQty
    )


# Style summary
styleSummary <- cleanData %>%
  group_by(Style) %>%
  summarise(
    lookups = n(),
    totalQuant = sum(qty, na.rm = TRUE),
    transactions = lookups - sum(is.na(qty)),
    sum(SalePrice * qty, na.rm = T),
    sum(SalePrice * qty, na.rm = T) / totalQuant
    )







# Rolling sales by day
## Need sales by day first....
salesByDay <- aggregate(cbind(qty, SalePrice) ~ date,
                        data = cleanData, FUN = sum)
salesByDay <- mutate(salesByDay, 
                     AvgSellPrice = SalePrice / qty, 
                     lookup = 1)

# Get rolling sales
rollingSalesByDay <- rollsum(salesByDay$SalePrice, 30, align = "right")
rollingQtyByDay <- rollsum(salesByDay$qty, 30, align = "right")
rollingData <- tbl_df(data.frame(cbind(date = salesByDay$date[30:length(salesByDay$date)],
                                       SMA30Sales = rollingSalesByDay,
                                       SMA30Qty = rollingQtyByDay)))


rollingData <- mutate(rollingData, 
                      AvgSellPrice = SMA30Sales / SMA30Qty)


# Plot rolling average of Price
plot(rollingData$date, rollingData$AvgSellPrice, type = "l")





# Filter on only style G when instock
styleG <- cleanData %>%
  filter(Style == "G", SalePrice > 50, SalePrice < 400, InStock == 1) %>%
  select(SalePrice)


# Get PDF of Style G's price
styleGDensity <- density(styleG$SalePrice)
styleGFunc <- approxfun(styleGDensity)


#### Plot PDF of Style G
#hist(styleG$SalePrice, breaks = 30, probability=T)
#lines(styleGDensity, col="red", lwd=2)

# Get PDF of Other Styles (Y)
styleY <- cleanData %>%
  filter(Style == "Y", SalePrice > 50, SalePrice < 400, InStock == 1) %>%
  select(SalePrice)



# Get PDF of Style Y's price
styleYDensity <- density(styleY$SalePrice)
styleYFunc <- approxfun(styleYDensity)

# Get PDF of Other Styles (S)
styleS <- cleanData %>%
  filter(Style == "S", SalePrice > 50, SalePrice < 400, InStock == 1) %>%
  select(SalePrice)

# Get PDF of Style S's price
styleSDensity <- density(styleS$SalePrice)
styleSFunc <- approxfun(styleSDensity)


# Get PDF for Total Data Set
allStyles <- cleanData %>%
  filter(SalePrice > 50, SalePrice < 400, InStock == 1) %>%
  select(SalePrice)

styleAllDensity <- density(allStyles$SalePrice)
styleAllFunc <- approxfun(styleAllDensity)


#### Final Graph

hist(
  allStyles$SalePrice,
  breaks = 30,
  probability = TRUE,
  ylim = c(0, 0.015),
  xlab = "Selling Price",
  ylab = "Probablity",
  main = "PDF of In-Stock Sale Prices, C-2056"
)
lines(styleGDensity, col = "green", lwd = 2)
lines(styleSDensity, col = "blue", lwd = 2)
#lines(styleYDensity, col = "yellow", lwd = 2)
lines(styleAllDensity, col = "red", lwd = 2)
legend(
  300,
  0.01,
  legend = c("Aftermarket", "RADX"
             #,"OEQ"
             , "All Styles"),
  col = c("green", "blue"
          #,"yellow"
          , "red"),
  lty = 1:1,
  cex = 1
)
