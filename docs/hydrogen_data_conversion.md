# Hydrogen and CO2 CSV conversion

The deterministic Hydrogen evidence dataset extends `data/full_model_int` with the
active inputs from `Hydrogen.xlsx`, `CO2.xlsx`, `Transport.xlsx`, and
`Generator.xlsx::CO2Captured`. It does not import Industry or Heat inputs.

## Regeneration

Run from the repository root in the InternalEMPIRE Python environment:

```bash
conda run -n empire_env python scripts/convert_hydrogen_inputs.py \
  --source "../InternalEMPIRE/Data handler/full_model_int" \
  --target data/full_model_int

python3 scripts/validate_full_model_int_dataset.py data/full_model_int
```

The converter refuses modified Hydrogen, CO2, Transport, or Generator workbooks. It
does not read or write the locally modified natural-gas workbook. The resulting
`hydrogen_conversion_manifest.json` pins the InternalEMPIRE commit, source workbook
hashes, every output hash, seven-period dimensions, explicit exclusions, and audited
source semantics. The main conversion manifest retains the strict complete file
inventory.

Regeneration is byte-deterministic: repeated runs produce identical Hydrogen and
dataset manifest SHA-256 hashes.

## Explicit source decisions

- `ElectrolyzerStackCapitalCost` is excluded because InternalEMPIRE reads it but does
  not use it in the active electrolyzer investment-cost expression.
- `H2TerminalMaxBuild` is excluded because its reference parameter and constraints
  are commented out and its data is incomplete for all LH2 terminal pairs.
- Twenty-one `Greece × PipelineH2Import` rows are removed from terminal parameter
  tables because that pair is absent from `H2TerminalsOfNode`. The exact rows are in
  `Hydrogen/excluded_input_rows.csv`.
- `CO2::StorageMaxCapacity` supplies periods 1–3 only. InternalEMPIRE supplies zero
  through the Pyomo parameter default for periods 4–7. The converter materializes the
  same 24 zeros and records them in `CO2/generated_default_rows.csv`.
- Hydrogen generators are generated from `Sets/Generator.csv` using the reference's
  case-insensitive `"hydrogen"` name rule. Conversion fails if that set differs from
  `Hydrogen.xlsx::Generators`.

## Signed reformer electricity coefficient

`ReformerElectricityUse` is the one intentionally signed numeric input. Ordinary SMR
has `-0.6666666667 MWh/tonne H2`; InternalEMPIRE subtracts this value in the electric
balance, treating it as a small electricity credit. SMR-CCS and GHR/ATR-CCS have
positive electricity consumption.

The converter and validator preserve and pin this reference behavior for parity. It
conflicts with a blanket non-negativity rule and should be confirmed or corrected by
the model owner before delivery. No absolute-value or silent data correction is
applied.

The constants table also records InternalEMPIRE's otherwise implicit 40-year
Hydrogen-pipeline lifetime, so investment tracking and annuity calculations do not
depend on an undocumented Julia default.
