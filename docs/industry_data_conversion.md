# Industry input conversion

The Industry CSV layer is generated independently from the gas/Hydrogen conversion.
The converter reads `Industry.xlsx`, `Sets.xlsx`, and `General.xlsx` from an
InternalEMPIRE checkout and never writes into that checkout.

```bash
/path/to/python-with-pandas scripts/convert_industry_inputs.py \
  --source "../InternalEMPIRE/Data handler/full_model_int" \
  --target data/full_model_int \
  --periods 7

python3 scripts/validate_full_model_int_dataset.py data/full_model_int
```

The conversion writes `industry_conversion_manifest.json` with source and output
SHA-256 hashes, schemas, row counts, constants, excluded inputs, and regeneration
arguments. `Industry/duplicate_input_audit.csv` records duplicate handling. The
current workbooks contain no duplicate Industry keys. The converter materializes
222 cells which Pyomo otherwise supplies through sparse `default=0` initial-capacity
and retirement grids; Julia therefore receives complete canonical grids and rejects
duplicates at runtime.

The active input scope is steel, cement, ammonia, refinery demand, the four producer
sets, and available biomass. Heat and unrelated Industry/Hydrogen sensitivity inputs
are excluded and listed in provenance. Refinery heat consumption is retained as
auditable data but is not a constraint while Heat is disabled.

The strict validator checks the complete 181-file `full_model_int` inventory,
schemas, periods, foreign keys, grids, values, duplicate audits, byte counts, and
hashes. It ignores recognized filesystem metadata only; an unlisted model input is
an error.
