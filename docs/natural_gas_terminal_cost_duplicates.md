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

## Resolved: the intended values, confirmed by the dataset owner (2026-07-30)

The correct profile for **every** RussianGas terminal is:

| Period | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---:|---:|---:|---:|---:|---:|---:|
| EUR/ton | **278** | 800 | 800 | 800 | 800 | 800 | 800 |

Cheap gas in the first period, then a sharp increase representing Russian gas after
the war in Ukraine. Italy's reserves are ~28 Mton (the smaller of the two duplicated
figures); proven Italian reserves are roughly 23-31 Mton, so the 2,182 Mton row is
wrong by a factor of about 75.

### Root cause

The workbook's RussianGas section has **8 periods per country**, but only 7
investment periods exist. Its value column was pasted on a **7-row stride** against
8-row country blocks, so the 278 drifts one period later for each successive country:
Hungary has it at period 1 *and* 8, Poland at 7, Romania at 6, Slovakia at 5,
Bulgaria at 4, Greece at 3, Croatia at 2, and so on. The five countries that appear
in both the original block (rows 228-276) and the appended block (rows 277-316) are
the 35 duplicate keys. The original block is correct; the appended block is the
damaged one.

### What was changed

`TerminalCost.csv` and `TerminalCost_stochastic.csv` in `data/full_model_int/` now
carry the confirmed profile: 16 corrected values in the deterministic table and 12 in
the stochastic one, where the 278 had been lost entirely (flat 800). `Reserves.csv`
already held the correct Italian figure, because last-source-row-wins happened to
select it.

The correction is recorded as `owner_confirmed_corrections` in
`conversion_manifest.json`, and `scripts/validate_full_model_int_dataset.py` enforces
it for every RussianGas row — not only the duplicated ones. The duplicate audit files
are unchanged: they remain the record of what the workbook says, which is now
deliberately distinct from what the CSV carries.

### The workbook itself was NOT modified

An attempt to repair `NaturalGas.xlsx` programmatically with `openpyxl` was made and
**reverted**. Round-tripping the file through `openpyxl` discards cached formula
results, and `Reserves`, `PipelineCapacity` and `TerminalCapacity` all contain
formulas. After saving, every value-reading consumer — `pandas.read_excel`,
`reader.py` — read `None` for those cells. The damage reached three sheets that were
never edited. The workbook was restored with `git checkout` and verified byte-clean.

Repair it in Excel instead, where formulas and their cached values both survive:

1. **`TerminalCost`** — delete rows **277-316** (the appended Hungary, Poland,
   Romania, Slovakia and Bulgaria blocks; the correct copies remain at rows 228-276).
2. **`TerminalCost`** — in the remaining appended blocks (Greece, Croatia, Macedonia,
   Serbia, Bosnia H, rows 317-356) delete each period-8 row and set the cost to 278
   for period 1 and 800 for periods 2-7.
3. **`TerminalCost_stochastic`** — apply steps 1 and 2 identically, and additionally
   set period 1 to 278 for Germany, Lithuania, Hungary, Poland, Romania, Slovakia and
   Bulgaria, which are currently 800 there.
4. **`Reserves`** — delete row **9** (`Italy`, 2181585300.486274), keeping row 13.

Afterwards the duplicate audits should regenerate empty, and the
`owner_confirmed_corrections` block can be dropped from the manifest.

### The workbook has since been repaired

The steps above were subsequently applied to `NaturalGas.xlsx` by editing the sheet
XML directly inside the zip, which — unlike `openpyxl` — preserves cached formula
results in the sheets that are not touched. Steps 1-3 were applied; step 4 was
deliberately skipped, because last-source-row-wins already selects Italy's correct
figure and the `Reserves` data column holds formulas whose relative references would
need rewriting after a row shift.

Verified afterwards: 12 RussianGas nodes at `[1:278, 2-7:800]` in both sheets, no
duplicate keys, no period 8, all other sheets value-identical, headers still on row 3,
and `pandas.read_excel(..., skiprows=2)` — the way `reader.py` reads it — returning
the corrected profile. Regenerating the `.tab` files through
`reader.generate_tab_files` and comparing key-by-key against the Julia CSV gives all
308 keys present on both sides with no real differences (only 16 one-ULP float
formatting differences on an unrelated `LNGImport` value).

So **Python and Julia read identical terminal costs**, and no correction needs to be
applied to the generated `.tab` files during comparison runs.

## Separate reserve duplicate

The source `Reserves` sheet also repeats Italy with
`2,181,585,300.486274` and `28,830,371.653353803` tonnes. Because the Pyomo
parameter is indexed only by node, InternalEMPIRE keeps the later, smaller
value. The converter writes that selected value once and records both source
rows in `NaturalGas/reserves_duplicate_audit.csv`. This is kept separate from
the terminal-cost audit because it has a different key schema.
