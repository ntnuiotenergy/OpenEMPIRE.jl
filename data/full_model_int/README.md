# `full_model_int`

Self-contained CSV conversion of the InternalEMPIRE `full_model_int` input.
It contains the electricity model and the natural-gas inputs currently
implemented by OpenEMPIRE.jl. The horizon is 7 strategic periods.

`Generator/CCSCostTSVariable.csv` and `Generator/CCSCostTSFixed.csv` are zeroed
because InternalEMPIRE's declarations, input load, and objective terms for both CCS
transport-and-storage costs are commented out. The converter isolates this temporary
reference compatibility rule in
`INTERNALEMPIRE_OMITS_CCS_TRANSPORT_AND_STORAGE_COST`; remove it when the reference
starts charging those inputs.

`Generator/MaxInstalledCapacityByPeriod.csv` is a core input because
InternalEMPIRE uses it to tighten selected node/technology capacity ceilings by
strategic period. Omitting it materially understates the reduced Hydrogen/CO2
objective.

Regenerate it from the workspace root with:

```bash
conda run -n empire_env python \
  OpenEMPIRE.jl/scripts/convert_internalempire_xlsx.py
```

`conversion_manifest.json` records source-workbook and output-file SHA-256
hashes. `NaturalGas/terminal_cost_duplicate_audit.csv` records duplicate source
keys resolved with Pyomo-compatible last-row-wins semantics.
`NaturalGas/reserves_duplicate_audit.csv` records the same explicit resolution
for the duplicate Italy reserve.
