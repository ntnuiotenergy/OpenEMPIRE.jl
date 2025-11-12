# TODO list and notes for the Julia version of EMPIRE

## Clarification points vs. Python version of EMPIRE

When preprocessing stochastic loads (lines 477-480 of `empire.py`), peak season hours are skipped, but the ordinary `model.seasScale` is used for the weights. This seems
problematic as it will lead too low value for `noderawdemand`.

```python
for (s,h) in model.HoursOfSeason:
    if value(h) < value(FirstHoursOfRegSeason[-1] + model.lengthRegSeason):
        for sce in model.Scenario:
            noderawdemand += value(model.sceProbab[sce] * model.seasScale[s] *  model.sloadRaw[n,h,sce,i])
```

During preprocessing of investment costs (lines 334 - 364 of `empire.py`), the cost is split over each year of its lifetime using the wacc factor and an annuity calculation. The value is then collected using a present value calculation using the discount factor over the minimum of the lifetime and remaining years in the planning horizon. 
The problem is that the annuity is calculated at the end of each year and the present value is based on evaluation at the start of each year. Thus there will be a discrepency. If we consider an investment of 100 and a wacc and discount rate of 0.05, a value of 105 will be used as investment cost if its lifetime is within the planning horizon.

```python
costperyearPW=(model.WACC/(1-((1+model.WACC)**(-model.storageLifetime[b]))))*model.storPWCapitalCost[b,i]+model.storPWFixedOMCost[b,i]
costperperiodPW=costperyearPW*1000*(1-(1+model.discountrate)**-(min(value((len(model.PeriodActive)-i+1)*LeapYearsInvestment), value(model.storageLifetime[b]))))/(1-(1/(1+model.discountrate)))                
```

## Missing in Julia version
- [ ] North Sea extensions
- [ ] Implementation of emission limits