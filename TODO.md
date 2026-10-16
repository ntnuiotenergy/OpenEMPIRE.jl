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

One solution is to have annualization be mathematically equivalent to paying the investment cost upfront when the entire lifetime is represented. Such that the present value is based on evaluation at the end of a year, like the annuity. That is multiply the present value factor by `1/(1+model.discountrate)`:
```python
costperperiodPW=costperyearPW*1000*(1-(1+model.discountrate)**-(min(value((len(model.PeriodActive)-i+1)*LeapYearsInvestment), value(model.storageLifetime[b]))))/(1-(1/(1+model.discountrate)))/(1+model.discountrate)
```


## Missing in Julia version

The North Sea offshore transmission cap and the emission limits (both the CO2 cap
and the CO2 price) have since been implemented.

### Config options the Python version has and this one does not

These keys were removed from `config/*.yaml`, because carrying a setting that
nothing reads is worse than not having it: it looks supported, and setting it
silently does nothing. They are recorded here so the intent is not lost, and so
that the key names match the Python version if any of them is implemented later.

| key | what it does in the Python version |
| --- | --- |
| `compute_operational_duals` | after solving, fix the investment variables and re-solve, so the operational constraints yield dual values (shadow prices). Skipped for out-of-sample runs |
| `print_in_iamc_format` | additionally write selected results in the IAMC format used for cross-model comparison, alongside the normal EMPIRE output |
| `write_in_lp_format` | write the problem out as an `.lp` file, for inspecting or re-solving the model outside EMPIRE |
| `serialize_instance` | serialise the built model so a later run can reuse it instead of rebuilding |
| `use_temporary_directory` / `temporary_directory` | build in a temporary directory rather than in place, and where that directory should be |
| `moment_matching` | a scenario-generation method that selects trees by matching statistical moments of the source data |
| `n_tree_compare` | how many candidate trees moment matching and copula sampling compare before choosing |

Worth noting which of these are merely conveniences and which change results.
`compute_operational_duals` produces output the Julia version cannot currently
produce at all, and `moment_matching` would select a different scenario tree, so
those two are genuine functional gaps. The rest — LP export, IAMC formatting,
serialisation, temporary directories — affect how a run is carried out or
reported, not what it computes.

`number_of_gas_scenarios` was deliberately **not** removed: it is unused on
branches without the natural-gas module, but is read in four files once that
module is present.

The clarification points above are still open.
