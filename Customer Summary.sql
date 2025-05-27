Use Sales_Margin;
-- Clean up temporary tables
DROP TABLE if exists #cltrank;
DROP TABLE if exists #CustomerMainStore;
drop table if exists #cltrankall;
-- First, create your temporary table with all the details, including period-based aggregations
Select 
    h.CltID,
    h.DiscLevel,
    st.[Store Name],
    Min(f.date) FirstVisit,
    max(f.date) LastVisit,
    count(distinct h.TrxKey) as TtlVisits,
    SUM(d.TtlDollars) as TtlSpend,
    
    -- Period-based spending (using transaction date)
    SUM(CASE WHEN f.Date >= DATEADD(month, -3, getdate()) THEN d.TtlDollars ELSE 0 END) as Last3MonthsSpend,
    SUM(CASE WHEN f.Date >= DATEADD(month, -6, getdate()) AND f.Date < DATEADD(month, -3, getdate()) THEN d.TtlDollars ELSE 0 END) as Prior3MonthsSpend,
    SUM(CASE WHEN f.Date >= DATEADD(month, -6, getdate()) THEN d.TtlDollars ELSE 0 END) as Last6MonthsSpend,
    SUM(CASE WHEN f.Date < DATEADD(month, -6, getdate()) AND f.Date >= DATEADD(month, -12, getdate()) THEN d.TtlDollars ELSE 0 END) as Prior6MonthsSpend,
    
    -- Period-based visits
    COUNT(DISTINCT CASE WHEN f.Date >= DATEADD(month, -3, getdate()) THEN h.TrxKey ELSE NULL END) as Last3MonthsVisits,
    COUNT(DISTINCT CASE WHEN f.Date >= DATEADD(month, -6, getdate()) AND f.Date < DATEADD(month, -3, getdate()) THEN h.TrxKey ELSE NULL END) as Prior3MonthsVisits,
    
    -- Core metrics for types of spending
    count(distinct d.ItemDetailID) as DistinctItems,
    sum(case
            when d.DiscountType = 'No Discount' 
            and d.PriceType = 'REG'
            then d.TtlDollars
            else 0
        end) as FullPriceSpend,
    sum(case
        when d.DiscountType = 'Fare Point' 
        then d.TtlDollars
        else 0
    end) as FarePointSpend,
    sum(case
        when d.DiscountType = 'Seniors Discount' 
        then d.TtlDollars
        else 0
    end) as SeniorDaySpend,
    sum(case
            when d.DiscountType <> 'No Discount' 
            and  d.DiscountType <> 'Fare Point'
            and  d.DiscountType <> 'Seniors Discount'
            then d.TtlDollars
            else 0
        end) as OtherDiscountSpend,
    sum(case
        when d.DiscountType = 'No Discount' 
        and d.PriceType <> 'REG'
        then d.TtlDollars
        else 0
    end) as SalePriceSpend
into #cltrank
from Sales_Margin.[dbo].[SMS_SAL_Detail] d Join Sales_Margin.[dbo].[SMS_SAL_Header] h
On d.TrxKey = h.TrxKey
and d.TrxDateID = h.TrxDateID
and h.IsNetSalesH = 'Yes'
and d.IsNetSalesR = 'Yes'
JOIN [ItemMaster].[dbo].[Fiscal Calendar] f
ON d.TrxDateID = f.[Fiscal Calender ID]
JOIN [ItemMaster].[dbo].Store st on h.StoreID = st.[Store ID]
JOIN [ItemMaster].dbo.[Item Detail] id ON d.ItemDetailID = id.[Item Detail ID]
JOIN [ItemMaster].dbo.[Subdepartment] sd ON id.[Subdepartment ID] = sd.[Subdepartment ID]
JOIN [ItemMaster].dbo.[Department] dp ON sd.[Department ID] = dp.[Department ID]
where 
f.Date between '2024-01-01' and '2025-03-31' 
and d.ItemDetailID <> 29084 -- Exclude fare point trigger
and d.ItemDetailID <> 6417 -- Exclude bottle return
group by h.CltID,h.DiscLevel,st.[Store Name]
order by LastVisit desc;

-- Create a temporary table to find the main store for each customer
SELECT 
    CltID,
    [Store Name] as MainStore,
	DiscLevel as DiscLevel	
INTO #CustomerMainStore
FROM (
    SELECT 
        CltID,
        [Store Name],
		DiscLevel,
        TtlSpend,
        ROW_NUMBER() OVER (PARTITION BY CltID ORDER BY TtlSpend DESC) as StoreRank
    FROM #cltrank
	where CltID <> ''
) ranked
WHERE StoreRank = 1;

-- Final query with all recommended metrics for customer segmentation
Select 
    a.CltID,
    cms.MainStore as MainStore,
	case
		when cms.DiscLevel = 0
		then 'FarePoint'
		else 'Staff'
	end	as CltType,
    -- Core metrics
    SUM(a.TtlSpend) as TtlSpend,
    SUM(a.TtlVisits) as TtlVisit,
    
    -- Spending pattern metrics
    SUM(a.FullPriceSpend) as FullPriceSpend,
    SUM(a.FullPriceSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as FullPriceSpendPct,
    SUM(a.SeniorDaySpend) as SeniorDaySpend,
    SUM(a.SeniorDaySpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as SeniorDaySpendPct,
    SUM(a.FarePointSpend) as FarePointSpend,
    SUM(a.FarePointSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as FarePointSpendPct,
    SUM(a.OtherDiscountSpend) as OtherDiscountSpend,
    SUM(a.OtherDiscountSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as OtherDiscountSpendPct,
    SUM(a.SalePriceSpend) as SalePriceSpend,
    SUM(a.SalePriceSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as SalePriceSpendPct,
    
    -- Visit pattern metrics
    MAX(a.LastVisit) as LastVisit,
    DATEDIFF(day, MAX(a.LastVisit), GETDATE()) as DaysSinceLastVisit,
    MIN(a.FirstVisit) as FirstVisit,
    DATEDIFF(day, MIN(a.FirstVisit), GETDATE()) as DaysSinceFirstPurchase,
    DATEDIFF(day, MIN(a.FirstVisit), MAX(a.LastVisit)) as CustomerTenureDays,
    
    -- Purchase regularity
    CASE WHEN SUM(a.TtlVisits) > 1 THEN 
        DATEDIFF(day, MIN(a.FirstVisit), MAX(a.LastVisit)) / (SUM(a.TtlVisits) - 1)
        ELSE NULL END as AvgDaysBetweenVisits,
    
    -- Basket metrics
    SUM(a.TtlSpend) / NULLIF(SUM(a.TtlVisits), 0) as AvgSpendPerVisit,
    SUM(a.DistinctItems) as BasketDiversity,
    
    -- Properly aggregated time-based metrics
    SUM(a.Last3MonthsSpend) as Last3MonthsSpend,
    SUM(a.Prior3MonthsSpend) as Prior3MonthsSpend,
    SUM(a.Last6MonthsSpend) as Last6MonthsSpend,
    SUM(a.Prior6MonthsSpend) as Prior6MonthsSpend,
    SUM(a.Last3MonthsVisits) as Last3MonthsVisits,
    SUM(a.Prior3MonthsVisits) as Prior3MonthsVisits,
    
    -- Three-month comparison ratio 
    CASE 
        WHEN SUM(a.Prior3MonthsSpend) <> 0
        THEN (SUM(a.Last3MonthsSpend) / NULLIF(SUM(a.Prior3MonthsSpend), 0)) - 1
        when SUM(a.Prior3MonthsSpend) = 0 and sum(a.Last3MonthsSpend) = 0 
        THEN 0
        WHEN SUM(a.Prior3MonthsSpend) = 0 and sum(a.Last3MonthsSpend) <> 0 
        THEN 1 
        ELSE NULL 
    END as Last3MonthsGrowthRatio,
    
    -- Half-year comparison ratio
    CASE 
        WHEN SUM(a.Prior6MonthsSpend) <> 0
        THEN (SUM(a.Last6MonthsSpend) / NULLIF(SUM(a.Prior6MonthsSpend), 0)) -1
        WHEN SUM(a.Prior6MonthsSpend) = 0 and sum(a.Last6MonthsSpend) = 0 
        THEN 0
        WHEN SUM(a.Prior6MonthsSpend) = 0 and sum(a.Last6MonthsSpend) <> 0 
        THEN 1
        ELSE NULL
    END as Last6MonthsGrowthRatio,
    
    -- Last 3 months visit growth ratio
    CASE 
        WHEN SUM(a.Prior3MonthsVisits) <> 0
        THEN (SUM(a.Last3MonthsVisits) / NULLIF(SUM(a.Prior3MonthsVisits), 0)) - 1
        WHEN SUM(a.Prior3MonthsVisits) = 0 and sum(a.Last3MonthsVisits) = 0 
        THEN 0
        WHEN SUM(a.Prior3MonthsVisits) = 0 and sum(a.Last3MonthsVisits) <> 0 
        THEN 1
        ELSE NULL
    END as Last3MonthsVisitsGrowthRatio
into #cltrankall
from #cltrank a
left join #CustomerMainStore cms ON a.CltID = cms.CltID
where a.CltID <> ''
group by a.CltID, cms.MainStore, cms.DiscLevel
order by SUM(a.TtlSpend) desc;

--Insert blank customers into #cltrankall table
INSERT INTO #cltrankall
(
    CltID,
    MainStore,
    CltType,
    TtlSpend,
    TtlVisit,
    FullPriceSpend,
    FullPriceSpendPct,
    SeniorDaySpend,
    SeniorDaySpendPct,
    FarePointSpend,
    FarePointSpendPct,
    OtherDiscountSpend,
    OtherDiscountSpendPct,
    SalePriceSpend,
    SalePriceSpendPct,
    LastVisit,
    DaysSinceLastVisit,
    FirstVisit,
    DaysSinceFirstPurchase,
    CustomerTenureDays,  
    AvgDaysBetweenVisits,   
    AvgSpendPerVisit,
    BasketDiversity,  
    Last3MonthsSpend,
    Prior3MonthsSpend,
    Last6MonthsSpend,
    Prior6MonthsSpend,
    Last3MonthsVisits,
    Prior3MonthsVisits,
    Last3MonthsGrowthRatio,
    Last6MonthsGrowthRatio,
    Last3MonthsVisitsGrowthRatio
)
Select 
    a.CltID,
    a.[Store Name] as MainStore,
	'NA' as CltType, 
    -- Core metrics
    SUM(a.TtlSpend) as TtlSpend,
    SUM(a.TtlVisits) as TtlVisit,
    
    -- Spending pattern metrics
    SUM(a.FullPriceSpend) as FullPriceSpend,
    SUM(a.FullPriceSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as FullPriceSpendPct,
    SUM(a.SeniorDaySpend) as SeniorDaySpend,
    SUM(a.SeniorDaySpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as SeniorDaySpendPct,
    SUM(a.FarePointSpend) as FarePointSpend,
    SUM(a.FarePointSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as FarePointSpendPct,
    SUM(a.OtherDiscountSpend) as OtherDiscountSpend,
    SUM(a.OtherDiscountSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as OtherDiscountSpendPct,
    SUM(a.SalePriceSpend) as SalePriceSpend,
    SUM(a.SalePriceSpend) / NULLIF(SUM(a.TtlSpend), 0) * 100 as SalePriceSpendPct,
    
    -- Visit pattern metrics
    MAX(a.LastVisit) as LastVisit,
    DATEDIFF(day, MAX(a.LastVisit), GETDATE()) as DaysSinceLastVisit,
    MIN(a.FirstVisit) as FirstVisit,
    DATEDIFF(day, MIN(a.FirstVisit), GETDATE()) as DaysSinceFirstPurchase,
    DATEDIFF(day, MIN(a.FirstVisit), MAX(a.LastVisit)) as CustomerTenureDays,
    
    -- Purchase regularity
    CASE WHEN SUM(a.TtlVisits) > 1 THEN 
        DATEDIFF(day, MIN(a.FirstVisit), MAX(a.LastVisit)) / (SUM(a.TtlVisits) - 1)
        ELSE NULL END as AvgDaysBetweenVisits,
    
    -- Basket metrics
    SUM(a.TtlSpend) / NULLIF(SUM(a.TtlVisits), 0) as AvgSpendPerVisit,
    SUM(a.DistinctItems) as BasketDiversity,
    
    -- Properly aggregated time-based metrics
    SUM(a.Last3MonthsSpend) as Last3MonthsSpend,
    SUM(a.Prior3MonthsSpend) as Prior3MonthsSpend,
    SUM(a.Last6MonthsSpend) as Last6MonthsSpend,
    SUM(a.Prior6MonthsSpend) as Prios6MonthsSpend,
    SUM(a.Last3MonthsVisits) as Last3MonthsVisits,
    SUM(a.Prior3MonthsVisits) as Prior3MonthsVisits,
    
    -- Three-month comparison ratio 
    CASE 
        WHEN SUM(a.Prior3MonthsSpend) <> 0
        THEN (SUM(a.Last3MonthsSpend) / NULLIF(SUM(a.Prior3MonthsSpend), 0)) - 1
        when SUM(a.Prior3MonthsSpend) = 0 and sum(a.Last3MonthsSpend) = 0 
        THEN 0
        WHEN SUM(a.Prior3MonthsSpend) = 0 and sum(a.Last3MonthsSpend) <> 0 
        THEN 1 
        ELSE NULL 
    END as Last3MonthsGrowthRatio,
    
    -- Half-year comparison ratio
    CASE 
        WHEN SUM(a.Prior6MonthsSpend) <> 0
        THEN (SUM(a.Last6MonthsSpend) / NULLIF(SUM(a.Prior6MonthsSpend), 0)) -1
        WHEN SUM(a.Prior6MonthsSpend) = 0 and sum(a.Last6MonthsSpend) = 0 
        THEN 0
        WHEN SUM(a.Prior6MonthsSpend) = 0 and sum(a.Last6MonthsSpend) <> 0 
        THEN 1
        ELSE NULL
    END as Last6MonthsGrowthRatio,
    
    -- Last 3 months visit growth ratio
    CASE 
        WHEN SUM(a.Prior3MonthsVisits) <> 0
        THEN (SUM(a.Last3MonthsVisits) / NULLIF(SUM(a.Prior3MonthsVisits), 0)) - 1
        WHEN SUM(a.Prior3MonthsVisits) = 0 and sum(a.Last3MonthsVisits) = 0 
        THEN 0
        WHEN SUM(a.Prior3MonthsVisits) = 0 and sum(a.Last3MonthsVisits) <> 0 
        THEN 1
        ELSE NULL
    END as Last3MonthsVisitsGrowthRatio
from #cltrank a
where a.CltID = ''
group by a.CltID, a.[Store Name]
order by SUM(a.TtlSpend) desc;

--Final results
select *
from #cltrankall
order by TtlSpend desc