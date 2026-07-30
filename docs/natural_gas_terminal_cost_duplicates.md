# Duplicate natural-gas terminal costs in `full_model_int`

## What was found

Both terminal-cost sheets in `NaturalGas.xlsx` contain repeated parameter
keys. After restricting the dataset to periods 1–7, each sheet contains 343
rows but only 308 unique `(Node, Terminal, Period, GasScenario)` keys.

The 35 duplicated keys in each sheet are all seven periods of the
`RussianGas` terminal at:

- Bulgaria
- Hungary
- Poland
- Romania
- Slovakia

In the deterministic `TerminalCost` sheet, eight duplicated keys disagree.
For example, Poland period 7 first has a cost of 800 EUR/ton and later has 278
EUR/ton. The stochastic sheet repeats the same 35 keys, but its repeated values
are equal for gas scenario 1.

The complete row-level evidence is stored in
`data/full_model_int/NaturalGas/terminal_cost_duplicate_audit.csv`.

## What InternalEMPIRE does

InternalEMPIRE converts the Excel sheet to a tabular file and loads it through
Pyomo `DataPortal` as a parameter indexed by node, terminal, period, and gas
scenario. A parameter can hold only one value for each key. When `DataPortal`
encounters a repeated key, the later row replaces the earlier row without a
warning.

Consequently, the Python model does not use both values. Its effective input is
the last occurrence in source-row order.

## What the Julia conversion does

The OpenEMPIRE.jl converter applies the same last-source-row-wins rule
explicitly. It writes only the resulting 308 unique keys to each runnable CSV
and records every discarded and selected row in the audit file.

The Julia reader then requires unique keys. Any new duplicate in a runnable CSV
is rejected with a file, row, and key-specific error instead of being silently
overwritten.

This gives OpenEMPIRE.jl the same effective values as the current Python model
while making the data decision visible and reproducible.

## Validate the converted dataset

Run the standard-library validator after regeneration or transfer:

```bash
python3 scripts/validate_full_model_int_dataset.py
```

It checks the complete manifest inventory, byte counts, SHA-256 hashes and CSV
row counts; exact gas schemas; foreign keys; period coverage; uniqueness,
finiteness and non-negativity; terminal and transport completeness; and that
each audited selected value is the value present in the canonical CSV.

## Recommended upstream correction

The source workbook should eventually contain one intentional row per key.
Before deleting the duplicates, the workbook owner should confirm which
Russian-gas cost trajectory is intended. Once corrected, regeneration should
produce an empty duplicate audit; until then, the audited last-row-wins rule
preserves current InternalEMPIRE behavior.

## Separate reserve duplicate

The source `Reserves` sheet also repeats Italy with
`2,181,585,300.486274` and `28,830,371.653353803` tonnes. Because the Pyomo
parameter is indexed only by node, InternalEMPIRE keeps the later, smaller
value. The converter writes that selected value once and records both source
rows in `NaturalGas/reserves_duplicate_audit.csv`. This is kept separate from
the terminal-cost audit because it has a different key schema.
