"""Convert an InternalEMPIRE "Data handler" Excel dataset to the CSV dataset layout.

The CSV layout is the one used by ``OpenEMPIRE-csv/input_data/<dataset>`` and
``OpenEMPIRE.jl/data/<dataset>`` (see ``OpenEMPIRE-csv/scripts/xlsx_to_csv.py``,
which produced ``europe_v51``).  This script does the same job for the internal
datasets (``full_model_int`` and friends), which differ from ``europe_v51`` in a
few ways:

* ``Sets.xlsx`` has no ``Horizon`` and no ``OffshoreNodes`` sheet.  The horizon is
  a run parameter (``NoOfPeriods`` in ``run_EMPIRE_int.py``) and the offshore
  nodes are ``Nodes!Node`` minus ``Nodes!OnshoreNode``.
* ``Sets.xlsx!Generators`` calls the ramping subset ``RampingGenerators``; the
  open dataset calls the same set ``ThermalGenerators``.
* Natural-gas and natural-gas transport inputs are promoted into the runnable
  dataset root. Other internal modules (CO2, hydrogen, industry, heat) remain in
  a separate ``data_extra`` tree until their Julia ports exist.

Column selections and cleaning for the core tables follow ``reader.py``
(``skiprows=2``, positional columns, ``Period <= NoOfPeriods``, drop rows with
missing values, strip all whitespace inside cells) so that the CSV dataset holds
exactly the numbers InternalEMPIRE feeds to Pyomo.

Usage::

    conda run -n empire_env python scripts/convert_internalempire_xlsx.py
    conda run -n empire_env python scripts/convert_internalempire_xlsx.py \
        --source-root /path/to/InternalEMPIRE/'Data handler'
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import shutil
from pathlib import Path

import pandas as pd

logger = logging.getLogger("xlsx_to_csv_int")

OPENEMPIRE_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = OPENEMPIRE_ROOT.parent

ENCODING = "utf-8"

NATURAL_GAS_SET_FILES = (
    "NaturalGasNodes.csv",
    "NaturalGasTerminals.csv",
    "NaturalGasTerminalsOfNode.csv",
    "NaturalGasDirectionalLines.csv",
    "OnshoreNode.csv",
)
NATURAL_GAS_TRANSPORT_FILES = ("NaturalGasDemand.csv", "CurtailCost.csv")

# The `time_format` both CSV datasets and the Julia port assume for raw scenario data.
TIME_FORMAT = "%d/%m/%Y %H:%M"

# --------------------------------------------------------------------------------------
# Core dataset specification
#
# (sheet, usecols, component, output filename).  ``usecols`` are positions in the
# sheet read with ``skiprows=2``, matching ``reader.py``.
# --------------------------------------------------------------------------------------

CORE_TABLES: dict[str, list[tuple[str, list[int], str, str]]] = {
    "Sets.xlsx": [
        ("StorageOfNodes", [0, 1], "Sets", "StoragesOfNode"),
        ("GeneratorsOfNode", [0, 1], "Sets", "GeneratorsOfNode"),
        ("GeneratorsOfTechnology", [0, 1], "Sets", "GeneratorsOfTechnology"),
        ("DirectionalLines", [0, 1], "Sets", "DirectionalLink"),
        ("LineTypeOfDirectionalLines", [0, 1, 2], "Sets", "TransmissionTypeOfDirectionalLink"),
    ],
    "Generator.xlsx": [
        ("FixedOMCosts", [0, 1, 2], "Generator", "genFixedOMCost"),
        ("CapitalCosts", [0, 1, 2], "Generator", "genCapitalCost"),
        ("VariableOMCosts", [0, 1], "Generator", "genVariableOMCost"),
        ("FuelCosts", [0, 1, 2], "Generator", "genFuelCost"),
        ("CCSCostTSVariable", [0, 1], "Generator", "CCSCostTSVariable"),
        ("Efficiency", [0, 1, 2], "Generator", "genEfficiency"),
        ("RefInitialCap", [0, 1, 2], "Generator", "genRefInitCap"),
        ("ScaleFactorInitialCap", [0, 1, 2], "Generator", "genScaleInitCap"),
        ("InitialCapacity", [0, 1, 2, 3], "Generator", "genInitCap"),
        ("MaxBuiltCapacity", [0, 1, 2, 3], "Generator", "genMaxBuiltCap"),
        ("MaxInstalledCapacity", [0, 1, 2], "Generator", "genMaxInstalledCapRaw"),
        ("RampRate", [0, 1], "Generator", "genRampUpCap"),
        ("GeneratorTypeAvailability", [0, 1], "Generator", "genCapAvailTypeRaw"),
        ("CO2Content", [0, 1], "Generator", "genCO2TypeFactor"),
        ("Lifetime", [0, 1], "Generator", "genLifetime"),
    ],
    "Transmission.xlsx": [
        ("lineEfficiency", [0, 1, 2], "Transmission", "lineEfficiency"),
        ("MaxInstallCapacityRaw", [0, 1, 2, 3], "Transmission", "transmissionMaxInstalledCapRaw"),
        ("MaxBuiltCapacity", [0, 1, 2, 3], "Transmission", "transmissionMaxBuiltCap"),
        ("Length", [0, 1, 2], "Transmission", "transmissionLength"),
        ("TypeCapitalCost", [0, 1, 2], "Transmission", "transmissionTypeCapitalCost"),
        ("TypeFixedOMCost", [0, 1, 2], "Transmission", "transmissionTypeFixedOMCost"),
        ("InitialCapacity", [0, 1, 2, 3], "Transmission", "transmissionInitCap"),
        ("Lifetime", [0, 1, 2], "Transmission", "transmissionLifetime"),
    ],
    "Node.xlsx": [
        ("ElectricAnnualDemand", [0, 1, 2], "Node", "sloadAnnualDemand"),
        ("NodeLostLoadCost", [0, 1, 2], "Node", "nodeLostLoadCost"),
        ("HydroGenMaxAnnualProduction", [0, 1], "Node", "maxHydroNode"),
    ],
    "General.xlsx": [
        ("seasonScale", [0, 1], "General", "seasScale"),
        ("CO2Cap", [0, 1], "General", "CO2cap"),
        ("CO2Price", [0, 1], "General", "CO2price"),
    ],
    "Storage.xlsx": [
        ("StorageBleedEfficiency", [0, 1], "Storage", "storageBleedEff"),
        ("StorageChargeEff", [0, 1], "Storage", "storageChargeEff"),
        ("StorageDischargeEff", [0, 1], "Storage", "storageDischargeEff"),
        ("StoragePowToEnergy", [0, 1], "Storage", "storagePowToEnergy"),
        ("StorageInitialEnergyLevel", [0, 1], "Storage", "storOperationalInit"),
        ("InitialPowerCapacity", [0, 1, 2, 3], "Storage", "storPWInitCap"),
        ("PowerCapitalCost", [0, 1, 2], "Storage", "storPWCapitalCost"),
        ("PowerFixedOMCost", [0, 1, 2], "Storage", "storPWFixedOMCost"),
        ("PowerMaxBuiltCapacity", [0, 1, 2, 3], "Storage", "storPWMaxBuiltCap"),
        ("EnergyCapitalCost", [0, 1, 2], "Storage", "storENCapitalCost"),
        ("EnergyFixedOMCost", [0, 1, 2], "Storage", "storENFixedOMCost"),
        ("EnergyInitialCapacity", [0, 1, 2, 3], "Storage", "storENInitCap"),
        ("EnergyMaxBuiltCapacity", [0, 1, 2, 3], "Storage", "storENMaxBuiltCap"),
        ("EnergyMaxInstalledCapacity", [0, 1, 2], "Storage", "storENMaxInstalledCapRaw"),
        ("PowerMaxInstalledCapacity", [0, 1, 2], "Storage", "storPWMaxInstalledCapRaw"),
        ("Lifetime", [0, 1], "Storage", "storageLifetime"),
    ],
}

# Set sheets read with ``header=0`` and split per column (``reader.py:read_sets``).
# ``{sheet: {excel column: (output filename, output header)}}``
CORE_SET_COLUMNS: dict[str, dict[str, tuple[str, str]]] = {
    "Nodes": {"Node": ("Node", "Node")},
    "Generators": {
        "Generator": ("Generator", "Generator"),
        "HydroGenerator": ("HydroGenerator", "HydroGenerator"),
        "HydroGeneratorWithReservoir": ("RegHydroGenerator", "HydroGeneratorWithReservoir"),
        # InternalEMPIRE calls the ramping subset RampingGenerators; the open
        # dataset / Julia port call the very same set ThermalGenerators.
        "RampingGenerators": ("ThermalGenerators", "ThermalGenerators"),
        "ThermalGenerators": ("ThermalGenerators", "ThermalGenerators"),
    },
    "Storage": {
        "Storage": ("Storage", "Storage"),
        "DependentStorage": ("DependentStorage", "DependentStorage"),
    },
    "Technology": {"Technology": ("Technology", "Technology")},
    "LineType": {"LineType": ("TransmissionType", "LineType")},
}

SCENARIO_FILES = (
    "electricload.csv",
    "hydroror.csv",
    "hydroseasonal.csv",
    "solar.csv",
    "windoffshore.csv",
    "windonshore.csv",
    "sampling_key.csv",
)

# --------------------------------------------------------------------------------------
# data_extra specification
#
# Sheets of the *core* workbooks that InternalEMPIRE reads but that have no slot
# in the core CSV layout.  Same (sheet, usecols, component, filename) shape.
# --------------------------------------------------------------------------------------

EXTRA_CORE_TABLES: dict[str, list[tuple[str, list[int], str, str]]] = {
    "Sets.xlsx": [
        ("NaturalGasTerminalsOfNode", [0, 1], "Sets", "NaturalGasTerminalsOfNode"),
        ("NaturalGasDirectionalLines", [0, 1], "Sets", "NaturalGasDirectionalLines"),
    ],
    "Generator.xlsx": [
        ("MaxInstalledCapacityByPeriod", [0, 1, 2, 3], "Generator", "MaxInstalledCapacityByPeriod"),
        ("MaxBiomethaneAvailability", [0, 1, 2], "Generator", "MaxBiomethaneAvailability"),
        ("CO2Captured", [0, 1], "Generator", "CO2Captured"),
    ],
    "Transmission.xlsx": [
        ("OffshoreConverterCapitalCost", [0, 1], "Transmission", "OffshoreConverterCapitalCost"),
        ("OffshoreConverterOMCost", [0, 1], "Transmission", "OffshoreConverterOMCost"),
    ],
    "Node.xlsx": [
        ("Latitude", [0, 1], "Node", "Latitude"),
        ("Longitude", [0, 1], "Node", "Longitude"),
    ],
    "General.xlsx": [
        ("AvailableBioEnergy", [0, 1], "General", "AvailableBioEnergy"),
    ],
}

# --------------------------------------------------------------------------------------
# Offshore node classification
#
# InternalEMPIRE does not record this in the workbooks: `run_EMPIRE_int.py` carries two
# hardcoded Python lists, `windfarmNodes` and `offshoreNodesList`, and strips spaces from
# both before matching node ids.  They are mirrored here (already space-free) because
# "every node that is not onshore" mixes three things that are modelled differently:
# wind farms whose corridors are capped by their own generation, energy hubs capped by
# converter capacity instead, and platforms that get neither.
# --------------------------------------------------------------------------------------

WIND_FARM_NODES: frozenset[str] = frozenset({
    "MorayFirth", "FirthofForth", "DoggerBank", "Hornsea", "OuterDowsing", "Norfolk",
    "EastAnglia", "Borssele", "HollandseeKust", "HelgoländerBucht", "Nordsøen",
    "UtsiraNord", "SørligeNordsjøI", "SørligeNordsjøII", "BalticCountries_BalticSea",
    "BE_PrincessElisabeth", "DE_NorthSea", "DE_BalticSea", "DK_NorthSea", "FI_BalticSea",
    "FR_ChannelSea", "FR_Atlantic", "IE_Atlantic", "NL_Lagelander", "NO_Vestavind",
    "NO_Sørvest", "PL_BalticSea", "SE_BotnieGulf", "SE_BalticSea", "SE_Luleå",
    "GB_DoggerBank", "GB_ScotlandEast", "GB_SheppeyIsland", "GB_IrelandSea",
    "GB_CelticSea",
})

ENERGY_HUB_NODES: frozenset[str] = frozenset({
    "EnergyhubGreatBritain", "EnergyhubNorway", "EnergyhubEU",
})

# Set-style sheets of the core workbooks that belong to the internal modules.
EXTRA_CORE_SET_SHEETS: dict[str, list[str]] = {
    "Sets.xlsx": [
        "NaturalGasNodes",
        "NaturalGasTerminals",
        "SteelProducers",
        "AmmoniaProducers",
        "CementProducers",
        "OilProducers",
    ],
}

# Module workbooks: (sheet, usecols) for table sheets, and set sheets read per column.
MODULE_TABLES: dict[str, list[tuple[str, list[int]]]] = {
    "CO2.xlsx": [
        ("StorageSiteCapitalCost", [0, 1]),
        ("StorageSiteFixedOMCost", [0, 1]),
        ("StorageMaxCapacity", [0, 1, 2]),
        ("PipelineCapitalCost", [0]),
        ("PipelineFixedOM", [0]),
        ("PipelineLifetime", [0]),
        ("PipelineElectricityUsage", [0]),
        ("MaxSequestrationCapacity", [0, 1]),
    ],
    "NaturalGas.xlsx": [
        ("StorageCapacity", [0, 1]),
        ("PipelineCapacity", [0, 1, 2]),
        ("PipelineElectricityUse", [0]),
        ("TerminalCost", [0, 1, 2, 3, 4]),
        ("TerminalCost_stochastic", [0, 1, 2, 3, 4]),
        ("TerminalCapacity", [0, 1, 2, 3]),
        ("Reserves", [0, 1]),
    ],
    "Hydrogen.xlsx": [
        ("ReformerCapitalCost", [0, 1, 2]),
        ("ReformerFixedOMCost", [0, 1, 2]),
        ("ReformerVariableOMCost", [0, 1, 2]),
        ("ReformerEfficiency", [0, 1, 2]),
        ("ReformerElectricityUse", [0, 1, 2]),
        ("ReformerLifetime", [0, 1]),
        ("ReformerEmissionFactor", [0, 1, 2]),
        ("ReformerCO2CaptureFactor", [0, 1, 2]),
        ("ElectrolyzerPlantCapitalCost", [0, 1]),
        ("ElectrolyzerFixedOMCost", [0, 1]),
        ("ElectrolyzerStackCapitalCost", [0, 1]),
        ("ElectrolyzerLifetime", [0]),
        ("ElectrolyzerPowerUse", [0, 1]),
        ("PipelineCapitalCost", [0, 1]),
        ("PipelineOMCostPerKM", [0, 1]),
        ("PipelineCompressorPowerUsage", [0]),
        ("StorageCapitalCost", [0, 1, 2]),
        ("StorageFixedOMCost", [0, 1, 2]),
        ("StorageMaxCapacity", [0, 1, 2]),
        ("StorageLifetime", [0, 1]),
        ("H2TerminalsOfNode", [0, 1]),
        ("H2TerminalCapitalCost", [0, 1, 2, 3]),
        ("H2TerminalFixedOM", [0, 1, 2, 3]),
        ("H2TerminalLifetime", [0, 1]),
        ("H2TerminalPrice", [0, 1, 2, 3]),
        ("H2TerminalCapacity", [0, 1, 2, 3]),
        ("H2TerminalMaxBuild", [0, 1, 2, 3]),
    ],
    "Industry.xlsx": [
        ("ShedCost", [0]),
        ("Steel_PlantLifetime", [0, 1]),
        ("Steel_InitialCapacity", [0, 1, 2]),
        ("Steel_ScaleFactorInitialCap", [0, 1, 2]),
        ("Steel_InvCost", [0, 1, 2]),
        ("Steel_FixedOM", [0, 1, 2]),
        ("Steel_VarOpex", [0, 1, 2]),
        ("Steel_CoalConsumption", [0, 1, 2]),
        ("Steel_HydrogenConsumption", [0, 1, 2]),
        ("Steel_BioConsumption", [0, 1, 2]),
        ("Steel_OilConsumption", [0, 1, 2]),
        ("Steel_ElConsumption", [0, 1, 2]),
        ("Steel_CO2Emissions", [0, 1]),
        ("Steel_CO2Captured", [0, 1]),
        ("Steel_YearlyProduction", [0, 1, 2]),
        ("Cement_PlantLifetime", [0, 1]),
        ("Cement_InitialCapacity", [0, 1, 2]),
        ("Cement_ScaleFactorInitialCap", [0, 1, 2]),
        ("Cement_InvCost", [0, 1, 2]),
        ("Cement_FixedOM", [0, 1, 2]),
        ("Cement_FuelConsumption", [0, 1, 2]),
        ("Cement_CO2CaptureRate", [0, 1]),
        ("Cement_ElConsumption", [0, 1, 2]),
        ("Cement_YearlyProduction", [0, 1]),
        ("Ammonia_PlantLifetime", [0, 1]),
        ("Ammonia_InitialCapacity", [0, 1, 2]),
        ("Ammonia_ScaleFactorInitialCap", [0, 1, 2]),
        ("Ammonia_InvCost", [0, 1, 2]),
        ("Ammonia_FixedOM", [0, 1, 2]),
        ("Ammonia_FeedstockConsumption", [0, 1]),
        ("Ammonia_ElConsumption", [0, 1]),
        ("Ammonia_YearlyProduction", [0, 1, 2]),
        ("Refinery_HydrogenConsumption", [0]),
        ("Refinery_HeatConsumption", [0]),
        ("Refinery_YearlyProduction", [0, 1, 2]),
    ],
    "Transport.xlsx": [
        ("ElectricityDemand", [0, 1, 2]),
        ("HydrogenDemand", [0, 1, 2]),
        ("NaturalGasDemand", [0, 1, 2]),
        ("CurtailCost", [0]),
    ],
    "HeatModule/HeatModuleSets.xlsx": [
        ("StorageOfNodes", [0, 1]),
        ("ConverterOfNodes", [0, 1]),
        ("GeneratorsOfNode", [0, 1]),
        ("GeneratorsOfTechnology", [0, 1]),
    ],
    "HeatModule/HeatModuleGenerator.xlsx": [
        ("FixedOMCosts", [0, 1, 2]),
        ("CapitalCosts", [0, 1, 2]),
        ("VariableOMCosts", [0, 1]),
        ("FuelCosts", [0, 1, 2]),
        ("Efficiency", [0, 1, 2]),
        ("RefInitialCap", [0, 1, 2]),
        ("ScaleFactorInitialCap", [0, 1, 2]),
        ("InitialCapacity", [0, 1, 2, 3]),
        ("MaxBuiltCapacity", [0, 1, 2, 3]),
        ("MaxInstalledCapacity", [0, 1, 2]),
        ("RampRate", [0, 1]),
        ("GeneratorTypeAvailability", [0, 1]),
        ("CO2Content", [0, 1]),
        ("Lifetime", [0, 1]),
        ("CHPEfficiency", [0, 1, 2]),
    ],
    "HeatModule/HeatModuleStorage.xlsx": [
        ("StorageBleedEfficiency", [0, 1]),
        ("StorageChargeEff", [0, 1]),
        ("StorageDischargeEff", [0, 1]),
        ("StorageInitialEnergyLevel", [0, 1]),
        ("InitialPowerCapacity", [0, 1, 2, 3]),
        ("PowerCapitalCost", [0, 1, 2]),
        ("PowerFixedOMCost", [0, 1, 2]),
        ("PowerMaxBuiltCapacity", [0, 1, 2, 3]),
        ("EnergyCapitalCost", [0, 1, 2]),
        ("EnergyFixedOMCost", [0, 1, 2]),
        ("EnergyInitialCapacity", [0, 1, 2, 3]),
        ("EnergyMaxBuiltCapacity", [0, 1, 2, 3]),
        ("EnergyMaxInstalledCapacity", [0, 1, 2]),
        ("PowerMaxInstalledCapacity", [0, 1, 2]),
        ("Lifetime", [0, 1]),
        ("StoragePowToEnergy", [0, 1]),
    ],
    "HeatModule/HeatModuleNode.xlsx": [
        ("HeatAnnualDemand", [0, 1, 2]),
        ("NodeLostLoadCost", [0, 1, 2]),
        ("ElectricHeatShare", [0, 1]),
    ],
    "HeatModule/HeatModuleConverter.xlsx": [
        ("FixedOMCosts", [0, 1, 2]),
        ("CapitalCosts", [0, 1, 2]),
        ("InitialCapacity", [0, 1, 2, 3]),
        ("MaxBuildCapacity", [0, 1, 2, 3]),
        ("MaxInstallCapacity", [0, 1, 2]),
        ("Efficiency", [0, 1]),
        ("Lifetime", [0, 1]),
    ],
}

MODULE_SET_SHEETS: dict[str, list[str]] = {
    "CO2.xlsx": ["CO2SequestrationNodes"],
    "Hydrogen.xlsx": [
        "Generators",
        "ProductionNodes",
        "ReformerLocations",
        "ReformerPlants",
        "H2Storages",
        "H2Terminals",
        "H2TerminalNodes",
    ],
    "Industry.xlsx": ["Steel_Plants", "Cement_Plants", "Ammonia_Plants"],
    "HeatModule/HeatModuleSets.xlsx": ["Storage", "Generator", "Technology", "Converter"],
}

# Spreadsheet working areas: raw source data, pivots and calculation scratch that
# no reader touches.  Listed so the README can say what was deliberately left in
# the workbooks.
UNCONVERTED_SHEETS = {
    "Generator.xlsx": ["Pivot", "Capacity_factor", "Summary", "MaxInstalledCapacity_calc"],
    "General.xlsx": ["Sheet1", "Sheet2"],
    "Node.xlsx": ["TYNDP24_nodes", "TYNDP24_sector"],
    "Transport.xlsx": ["Heating", "Biomethane", "Data", "TYNDP24_Data", "Eurostat"],
    "HeatModule/HeatModuleStochastic.xlsx": ["HeatLoadRaw", "Ark1"],
    "HeatModule/HeatModuleNeighbourhood.xlsx": ["<all sheets>"],
}


# --------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------


def normalize_columns(columns) -> list[str]:
    """Match the column naming of ``xlsx_to_csv.py``: strip, then space -> underscore."""
    out = []
    for index, column in enumerate(columns):
        name = str(column).strip()
        if name.startswith("Unnamed:"):
            name = f"col{index}"
        out.append(name.replace(" ", "_"))
    return out


def strip_cell_whitespace(df: pd.DataFrame) -> pd.DataFrame:
    """Remove all whitespace inside string cells, as ``reader.py`` does."""
    return df.replace(r"\s", "", regex=True)


def integerize_period(df: pd.DataFrame) -> pd.DataFrame:
    """Write Period/Horizon columns as integers, not ``1.0``."""
    for column in df.columns:
        if str(column).split(".")[0] not in ("Period", "Horizon"):
            continue
        values = pd.to_numeric(df[column], errors="coerce")
        if values.notna().all() and (values % 1 == 0).all():
            df[column] = values.astype("int64")
    return df


def write_csv(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False, encoding=ENCODING)


def read_sheet(excel: pd.ExcelFile, sheet: str, skiprows: int) -> pd.DataFrame:
    return excel.parse(sheet, header=skiprows)


def select_table(
    raw: pd.DataFrame, usecols: list[int], periods: int | None
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return ``(selected, dropped_by_period_filter)`` following ``reader.py``."""
    dropped = raw.iloc[0:0]
    if periods is not None and "Period" in raw.columns:
        period = pd.to_numeric(raw["Period"], errors="coerce")
        beyond = period > periods
        if beyond.any():
            dropped = raw.loc[beyond].iloc[:, usecols].dropna()
        raw = raw.loc[period <= periods]

    selected = raw.iloc[:, usecols].dropna()
    return selected, dropped


def finalize(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = normalize_columns(df.columns)
    df = strip_cell_whitespace(df)
    return integerize_period(df)


def extra_columns_frame(raw: pd.DataFrame, usecols: list[int]) -> pd.DataFrame | None:
    """Leftover columns of a core sheet, prefixed by that sheet's key columns.

    ``europe_v51``'s ``data_extra`` holds the bare leftover columns; keeping the
    key columns in front makes the same data usable without opening the workbook.
    """
    keep = [i for i in range(raw.shape[1]) if i not in set(usecols)]
    keep = [i for i in keep if not raw.iloc[:, i].isna().all()]
    if not keep:
        return None

    key_cols = usecols[:-1] if len(usecols) > 1 else []
    frame = raw.iloc[:, key_cols + keep]
    frame = frame.dropna(how="all", subset=frame.columns[len(key_cols) :])
    return None if frame.empty else frame


# --------------------------------------------------------------------------------------
# Conversion steps
# --------------------------------------------------------------------------------------


def convert_core_tables(source: Path, out: Path, extra_out: Path, periods: int) -> None:
    for workbook, sheets in CORE_TABLES.items():
        path = source / workbook
        if not path.exists():
            raise FileNotFoundError(f"Missing workbook: {path}")
        excel = pd.ExcelFile(path)
        for sheet, usecols, component, filename in sheets:
            if sheet not in excel.sheet_names:
                raise KeyError(f"{workbook} has no sheet {sheet!r}")
            raw = read_sheet(excel, sheet, skiprows=2)
            selected, dropped = select_table(raw, usecols, periods)
            write_csv(finalize(selected), out / component / f"{filename}.csv")
            logger.info("%-18s [%-28s] -> %s/%s.csv (%d rows)",
                        workbook, sheet, component, filename, len(selected))

            if not dropped.empty:
                write_csv(
                    finalize(dropped),
                    extra_out / "_beyond_horizon" / f"{component}_{filename}.csv",
                )
                logger.info("    %d rows with Period > %d kept in _beyond_horizon/",
                            len(dropped), periods)

            extra = extra_columns_frame(raw, usecols)
            if extra is not None:
                write_csv(finalize(extra), extra_out / component / f"{sheet}_extra.csv")


# Pyomo Param defaults from InternalEMPIRE's empire.py. Pyomo fills every
# missing (key, period) cell of a sparse .tab with the parameter's `default=`;
# a CSV consumer that materializes one profile per key cannot reproduce that
# per-cell fallback, so the dataset must be explicit. The source workbooks
# frequently provide only period-1 rows (e.g. genMaxBuiltCap has 578 such keys,
# storENMaxBuiltCap all 65), which InternalEMPIRE silently completes with these
# defaults. Note transmissionMaxBuiltCap's default is 10000 in InternalEMPIRE
# versus 20000 in base OpenEMPIRE — this table follows the fork it was
# converted from.
PYOMO_PERIOD_DEFAULTS = {
    ("Generator", "genMaxBuiltCap"): ("500000.0", False),
    ("Transmission", "transmissionMaxBuiltCap"): ("10000.0", True),
    ("Storage", "storENMaxBuiltCap"): ("500000.0", False),
    ("Storage", "storPWMaxBuiltCap"): ("500000.0", False),
}


# InternalEMPIRE prices natural gas endogenously through its gas module, so its
# Generator!FuelCosts sheet has no row for any gas technology. Pyomo's genFuelCost
# default is 0, which means "gas is free" for anyone running with the gas module
# off — the failure mode the model owner asked us to close. Per his instruction
# ("Legg inn FuelCost fra v51 hvis det mangler"), the missing rows are filled from
# base OpenEMPIRE's europe_v51 fuel costs, which is what genFuelCost means in
# base EMPIRE. Only genuinely missing (technology, period) rows are added; every
# value the workbook provides is left untouched.
#
# This does not change any run with natural_gas=true: that path drops the ordinary
# fuel term for gas-fuelled generators and prices them through the module instead.
FUEL_COST_FALLBACK_DATASET = "europe_v51"


def fill_missing_gas_fuel_costs(out: Path, periods: int) -> None:
    target = out / "Generator" / "genFuelCost.csv"
    # Always read the reference costs from the repository's own dataset, not from
    # the (possibly temporary) output root used for a regeneration check.
    source = OPENEMPIRE_ROOT / "data" / FUEL_COST_FALLBACK_DATASET / "Generator" / "genFuelCost.csv"
    if not source.is_file():
        logger.warning("No %s fuel costs at %s; leaving genFuelCost.csv untouched",
                       FUEL_COST_FALLBACK_DATASET, source)
        return

    df = pd.read_csv(target, dtype=str)
    tech_col, period_col, value_col = df.columns[0], df.columns[1], df.columns[2]
    have = {(r[tech_col], int(r[period_col])) for _, r in df.iterrows()}
    present_techs = {t for t, _ in have}

    generators = set(pd.read_csv(out / "Sets" / "Generator.csv", dtype=str).iloc[:, 0])
    missing_techs = sorted(generators - present_techs)
    if not missing_techs:
        logger.info("genFuelCost.csv: every generator already has fuel costs")
        return

    ref = pd.read_csv(source, dtype=str)
    ref_lookup = {(r.iloc[0], int(r.iloc[1])): r.iloc[2] for _, r in ref.iterrows()}

    added, unresolved = [], []
    for tech in missing_techs:
        rows = [(tech, p, ref_lookup[(tech, p)]) for p in range(1, periods + 1)
                if (tech, p) in ref_lookup]
        if len(rows) == periods:
            added.extend(rows)
        else:
            unresolved.append(tech)

    if unresolved:
        raise SystemExit(
            f"{target}: no {FUEL_COST_FALLBACK_DATASET} fuel cost for {unresolved}; "
            "supply them explicitly rather than leaving them at Pyomo's 0 default"
        )

    extra = pd.DataFrame(added, columns=[tech_col, period_col, value_col])
    write_csv(pd.concat([df, extra], ignore_index=True), target)
    logger.info("genFuelCost.csv: added %d rows for %s from %s (was missing entirely)",
                len(added), ", ".join(missing_techs), FUEL_COST_FALLBACK_DATASET)


def materialize_pyomo_period_defaults(out: Path, periods: int) -> None:
    """Complete sparse (key, period) tables to the full period grid.

    For each configured table, every key present in the CSV receives explicit
    rows for all periods 1..`periods`, using the Pyomo default where the
    workbook supplied no value. When `full_domain` is set, keys absent from the
    table entirely (bidirectional arcs from Sets/DirectionalLink.csv) are also
    materialized — Pyomo constrains the whole domain, and for
    transmissionMaxBuiltCap the reference default (10000) actually binds,
    unlike a missing-key fallback of "no constraint".
    """
    arcs: list[tuple[str, str]] = []
    seen_arcs: set[frozenset[str]] = set()
    links = pd.read_csv(out / "Sets" / "DirectionalLink.csv", dtype=str)
    for _, row in links.iterrows():
        pair = frozenset((row.iloc[0], row.iloc[1]))
        if pair not in seen_arcs:
            seen_arcs.add(pair)
            arcs.append((row.iloc[0], row.iloc[1]))

    for (component, filename), (default, full_domain) in PYOMO_PERIOD_DEFAULTS.items():
        path = out / component / f"{filename}.csv"
        df = pd.read_csv(path, dtype=str)
        key_cols = list(df.columns[:2])
        period_col = df.columns[2]
        value_col = df.columns[3]
        provided: dict[tuple[str, str], dict[int, str]] = {}
        for _, row in df.iterrows():
            provided.setdefault((row[key_cols[0]], row[key_cols[1]]), {})[
                int(row[period_col])
            ] = row[value_col]

        keys = list(provided)
        if full_domain:
            covered = {frozenset(k) for k in provided}
            keys += [a for a in arcs if frozenset(a) not in covered]

        records = []
        added = 0
        for key in keys:
            values = provided.get(key, {})
            for period in range(1, periods + 1):
                value = values.get(period)
                if value is None:
                    value = default
                    added += 1
                records.append(
                    {
                        key_cols[0]: key[0],
                        key_cols[1]: key[1],
                        period_col: period,
                        value_col: value,
                    }
                )
        write_csv(pd.DataFrame.from_records(records), path)
        logger.info(
            "%s/%s.csv: materialized %d default cells (Pyomo default %s) "
            "across %d keys x %d periods",
            component, filename, added, default, len(keys), periods,
        )


def convert_core_sets(source: Path, out: Path, extra_out: Path, periods: int) -> None:
    excel = pd.ExcelFile(source / "Sets.xlsx")
    nodes: list[str] | None = None
    onshore: list[str] | None = None

    for sheet, mapping in CORE_SET_COLUMNS.items():
        if sheet not in excel.sheet_names:
            raise KeyError(f"Sets.xlsx has no sheet {sheet!r}")
        raw = read_sheet(excel, sheet, skiprows=0)
        handled: list[str] = []
        for column in raw.columns:
            name = str(column).strip()
            if name not in mapping:
                continue
            filename, header = mapping[name]
            values = strip_cell_whitespace(raw[[column]].dropna())
            values.columns = [header]
            write_csv(values, out / "Sets" / f"{filename}.csv")
            handled.append(name)
            logger.info("%-18s [%-28s] -> Sets/%s.csv (%d rows)",
                        "Sets.xlsx", f"{sheet}!{name}", filename, len(values))
            if sheet == "Nodes" and name == "Node":
                nodes = values[header].tolist()

        if sheet == "Nodes":
            for column in raw.columns:
                if str(column).strip() == "OnshoreNode":
                    frame = strip_cell_whitespace(raw[[column]].dropna())
                    onshore = frame[column].tolist()
                    frame.columns = ["OnshoreNode"]
                    write_csv(frame, extra_out / "Sets" / "OnshoreNode.csv")

        leftover = [c for c in raw.columns
                    if str(c).strip() not in handled
                    and not str(c).startswith("Unnamed")
                    and not raw[c].isna().all()
                    and str(c).strip() != "OnshoreNode"]
        if leftover:
            write_csv(finalize(raw[leftover].dropna(how="all")),
                      extra_out / "Sets" / f"{sheet}_extra.csv")

    if nodes is None or onshore is None:
        raise ValueError("Sets.xlsx!Nodes must have both a Node and an OnshoreNode column")

    unknown = [n for n in onshore if n not in set(nodes)]
    if unknown:
        raise ValueError(f"OnshoreNode entries missing from Node: {unknown}")
    offshore = [n for n in nodes if n not in set(onshore)]

    # "Node minus OnshoreNode" is not a usable offshore classification: it mixes wind
    # farms, energy hubs and gas platforms, and the three are modelled differently.
    # InternalEMPIRE keeps the split in two hardcoded lists in run_EMPIRE_int.py rather
    # than in the workbooks, so they are mirrored here. Anything offshore that is in
    # neither list (Sleipner, Draupner - GasOCGT platforms) is an ordinary node.
    wind_farms = [n for n in offshore if n in WIND_FARM_NODES]
    hubs = [n for n in offshore if n in ENERGY_HUB_NODES]

    # Read GeneratorsOfNode straight from the workbook: convert_core_tables, which writes
    # the CSV, has not run yet at this point.
    gen_raw = read_sheet(excel, "GeneratorsOfNode", skiprows=2)
    gen_nodes = set(strip_cell_whitespace(gen_raw.iloc[:, [0]].dropna()).iloc[:, 0])
    barren = [n for n in wind_farms if n not in gen_nodes]
    if barren:
        # The cap sums the farm's own generation, so this would force its corridors to
        # zero capacity and disconnect the node.
        raise ValueError(f"Offshore wind farms with no generators: {barren}")
    both = sorted(set(wind_farms) & set(hubs))
    if both:
        raise ValueError(f"Nodes listed as both wind farm and energy hub: {both}")

    write_csv(pd.DataFrame({"OffshoreWindFarmNode": wind_farms}),
              out / "Sets" / "OffshoreWindFarmNode.csv")
    write_csv(pd.DataFrame({"OffshoreEnergyHub": hubs}),
              out / "Sets" / "OffshoreEnergyHub.csv")
    unclassified = [n for n in offshore if n not in set(wind_farms) | set(hubs)]
    logger.info(
        "Derived offshore sets: %d wind farms, %d energy hubs, %d other offshore nodes (%s)",
        len(wind_farms), len(hubs), len(unclassified), ", ".join(unclassified) or "none",
    )

    write_csv(pd.DataFrame({"Horizon": range(1, periods + 1)}), out / "Sets" / "Period.csv")
    logger.info("Derived Sets/Period.csv: 1..%d", periods)


def normalize_time_column(path: Path, target: Path) -> bool:
    """Rewrite a raw scenario file's `time` column as ``dd/mm/yyyy HH:MM``.

    ``full_model_int`` stores hydroror/hydroseasonal with ISO timestamps and the
    other series with ``dd/mm/yyyy HH:MM``; ``scenario_random.py`` compensates by
    hardcoding a second format for those two files.  Both the CSV datasets and
    the Julia port take a single ``time_format`` from the config, so the
    timestamps are written in one format here.  Only the text changes — the
    instants, and every other column, are untouched.
    """
    frame = pd.read_csv(path, dtype=str, keep_default_na=False)
    if "time" not in frame.columns:
        shutil.copy2(path, target)
        return False

    parsed = pd.to_datetime(frame["time"], format=TIME_FORMAT, exact=True, errors="coerce")
    if parsed.notna().all():
        shutil.copy2(path, target)
        return False

    parsed = pd.to_datetime(frame["time"], format="mixed", dayfirst=True)
    frame["time"] = parsed.dt.strftime(TIME_FORMAT)
    frame.to_csv(target, index=False, encoding=ENCODING)
    return True


def copy_scenario_data(source: Path, out: Path, extra_out: Path) -> None:
    src = source / "ScenarioData"
    dst = out / "ScenarioData"
    dst.mkdir(parents=True, exist_ok=True)
    for name in SCENARIO_FILES:
        path = src / name
        if not path.exists():
            logger.warning("ScenarioData/%s not found", name)
            continue
        if normalize_time_column(path, dst / name):
            logger.info("ScenarioData/%s: rewrote 'time' as %s", name, TIME_FORMAT)
    logger.info("Copied %d ScenarioData files", len(list(dst.glob("*.csv"))))

    heat = src / "HeatModule"
    if heat.is_dir():
        heat_dst = extra_out / "ScenarioData" / "HeatModule"
        heat_dst.mkdir(parents=True, exist_ok=True)
        for path in sorted(heat.glob("*.csv")):
            shutil.copy2(path, heat_dst / path.name)
        logger.info("Copied HeatModule scenario data to data_extra")


def convert_extra_tables(source: Path, extra_out: Path, periods: int) -> None:
    for workbook, sheets in EXTRA_CORE_TABLES.items():
        excel = pd.ExcelFile(source / workbook)
        for sheet, usecols, component, filename in sheets:
            if sheet not in excel.sheet_names:
                logger.warning("%s has no sheet %r (skipped)", workbook, sheet)
                continue
            raw = read_sheet(excel, sheet, skiprows=2)
            selected, _ = select_table(raw, usecols, periods)
            write_csv(finalize(selected), extra_out / component / f"{filename}.csv")

    for workbook, sheets in EXTRA_CORE_SET_SHEETS.items():
        excel = pd.ExcelFile(source / workbook)
        for sheet in sheets:
            if sheet not in excel.sheet_names:
                logger.warning("%s has no sheet %r (skipped)", workbook, sheet)
                continue
            write_set_sheet(excel, sheet, extra_out / "Sets")


def write_set_sheet(excel: pd.ExcelFile, sheet: str, target: Path) -> None:
    """One file per column, named after the column — as ``reader.py:read_sets`` does.

    Sheet and column name often differ (`Industry!Steel_Plants` holds a column
    `SteelProductionPlants`); the column name is the one the model uses.
    """
    raw = read_sheet(excel, sheet, skiprows=0)
    columns = [c for c in raw.columns
               if not str(c).startswith("Unnamed") and not raw[c].isna().all()]
    for column in columns:
        values = strip_cell_whitespace(raw[[column]].dropna())
        name = str(column).strip().replace(" ", "_")
        values.columns = [name]
        write_csv(values, target / f"{name}.csv")


def convert_modules(source: Path, extra_out: Path, periods: int) -> None:
    for workbook, sheets in MODULE_TABLES.items():
        path = source / workbook
        if not path.exists():
            logger.warning("Module workbook %s not found (skipped)", workbook)
            continue
        component = Path(workbook).stem.replace("HeatModule", "") or "HeatModule"
        target = extra_out / (
            f"HeatModule/{component}" if workbook.startswith("HeatModule/") else component
        )
        excel = pd.ExcelFile(path)
        for sheet, usecols in sheets:
            if sheet not in excel.sheet_names:
                logger.warning("%s has no sheet %r (skipped)", workbook, sheet)
                continue
            raw = read_sheet(excel, sheet, skiprows=2)
            if max(usecols) >= raw.shape[1]:
                logger.warning("%s[%s] has %d columns, need %d (skipped)",
                               workbook, sheet, raw.shape[1], max(usecols) + 1)
                continue
            selected, _ = select_table(raw, usecols, periods)
            write_csv(finalize(selected), target / f"{sheet}.csv")
        logger.info("Converted %-38s -> %s", workbook, target.relative_to(extra_out))

    for workbook, sheets in MODULE_SET_SHEETS.items():
        path = source / workbook
        if not path.exists():
            continue
        component = Path(workbook).stem.replace("HeatModule", "") or "HeatModule"
        target = extra_out / (
            f"HeatModule/{component}" if workbook.startswith("HeatModule/") else component
        )
        excel = pd.ExcelFile(path)
        for sheet in sheets:
            if sheet not in excel.sheet_names:
                logger.warning("%s has no sheet %r (skipped)", workbook, sheet)
                continue
            write_set_sheet(excel, sheet, target)


def canonicalize_terminal_cost(path: Path, table: str) -> list[dict[str, object]]:
    """Make Pyomo DataPortal's last-row-wins behavior explicit and auditable."""
    frame = pd.read_csv(path)
    key_columns = list(frame.columns[:4])
    value_column = frame.columns[4]
    duplicate_mask = frame.duplicated(key_columns, keep=False)
    audit: list[dict[str, object]] = []

    for _, group in frame.loc[duplicate_mask].groupby(key_columns, sort=False):
        selected = group.iloc[-1]
        selected_row = int(group.index[-1]) + 2
        for source_index, discarded in group.iloc[:-1].iterrows():
            audit.append(
                {
                    "Table": table,
                    "Node": selected.iloc[0],
                    "Terminal": selected.iloc[1],
                    "Period": int(selected.iloc[2]),
                    "GasScenario": int(selected.iloc[3]),
                    "DiscardedSourceRow": int(source_index) + 2,
                    "DiscardedValue": float(discarded[value_column]),
                    "SelectedSourceRow": selected_row,
                    "SelectedValue": float(selected[value_column]),
                    "ValuesDiffer": bool(
                        float(discarded[value_column]) != float(selected[value_column])
                    ),
                }
            )

    canonical = frame.drop_duplicates(key_columns, keep="last")
    write_csv(canonical, path)
    return audit


def canonicalize_reserves(path: Path) -> list[dict[str, object]]:
    """Make duplicate node reserves explicit using DataPortal's last-row rule."""
    frame = pd.read_csv(path)
    key_column, value_column = frame.columns
    duplicate_mask = frame.duplicated([key_column], keep=False)
    audit: list[dict[str, object]] = []

    for node, group in frame.loc[duplicate_mask].groupby(key_column, sort=False):
        selected = group.iloc[-1]
        selected_row = int(group.index[-1]) + 2
        for source_index, discarded in group.iloc[:-1].iterrows():
            audit.append(
                {
                    "Table": "Reserves",
                    "Node": node,
                    "DiscardedSourceRow": int(source_index) + 2,
                    "DiscardedValue": float(discarded[value_column]),
                    "SelectedSourceRow": selected_row,
                    "SelectedValue": float(selected[value_column]),
                    "ValuesDiffer": bool(
                        float(discarded[value_column]) != float(selected[value_column])
                    ),
                }
            )

    canonical = frame.drop_duplicates([key_column], keep="last")
    write_csv(canonical, path)
    return audit


def promote_natural_gas_inputs(
    extra_out: Path,
    out: Path,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """Copy only the implemented natural-gas module into the runnable dataset."""
    gas_source = extra_out / "NaturalGas"
    gas_target = out / "NaturalGas"
    gas_target.mkdir(parents=True, exist_ok=True)
    for source in sorted(gas_source.glob("*.csv")):
        shutil.copy2(source, gas_target / source.name)

    sets_target = out / "Sets"
    for filename in NATURAL_GAS_SET_FILES:
        shutil.copy2(extra_out / "Sets" / filename, sets_target / filename)

    transport_target = out / "Transport"
    transport_target.mkdir(parents=True, exist_ok=True)
    for filename in NATURAL_GAS_TRANSPORT_FILES:
        shutil.copy2(extra_out / "Transport" / filename, transport_target / filename)

    audit: list[dict[str, object]] = []
    for filename in ("TerminalCost.csv", "TerminalCost_stochastic.csv"):
        audit.extend(
            canonicalize_terminal_cost(gas_target / filename, filename.removesuffix(".csv"))
        )
    write_csv(pd.DataFrame(audit), gas_target / "terminal_cost_duplicate_audit.csv")
    reserve_audit = canonicalize_reserves(gas_target / "Reserves.csv")
    write_csv(pd.DataFrame(reserve_audit), gas_target / "reserves_duplicate_audit.csv")
    return audit, reserve_audit


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_conversion_manifest(
    source: Path,
    out: Path,
    dataset: str,
    periods: int,
    duplicate_audit: list[dict[str, object]],
    reserve_duplicate_audit: list[dict[str, object]],
) -> None:
    files = sorted(
        path for path in out.rglob("*")
        if path.is_file() and path.name != "conversion_manifest.json"
    )
    duplicate_counts = {
        table: sum(row["Table"] == table for row in duplicate_audit)
        for table in ("TerminalCost", "TerminalCost_stochastic")
    }
    manifest = {
        "schema_version": 1,
        "dataset": dataset,
        "source_dataset": source.name,
        "periods": periods,
        "converter": "scripts/convert_internalempire_xlsx.py",
        "terminal_cost_duplicate_keys_by_table": duplicate_counts,
        "terminal_cost_duplicate_keys_total": len(duplicate_audit),
        "terminal_cost_conflicting_keys": sum(
            bool(row["ValuesDiffer"]) for row in duplicate_audit
        ),
        "reserve_duplicate_keys": len(reserve_duplicate_audit),
        "reserve_conflicting_keys": sum(
            bool(row["ValuesDiffer"]) for row in reserve_duplicate_audit
        ),
        "source_workbooks": [
            {
                "path": path.relative_to(source).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": file_sha256(path),
            }
            for path in sorted(source.rglob("*.xlsx"))
        ],
        "files": [
            {
                "path": path.relative_to(out).as_posix(),
                "bytes": path.stat().st_size,
                "rows": sum(1 for _ in path.open(encoding=ENCODING)) - 1
                if path.suffix == ".csv"
                else None,
                "sha256": file_sha256(path),
            }
            for path in files
        ],
    }
    target = out / "conversion_manifest.json"
    target.write_text(json.dumps(manifest, indent=2) + "\n", encoding=ENCODING)


def write_dataset_readme(out: Path, dataset: str, periods: int) -> None:
    text = f"""# `{dataset}`

Self-contained CSV conversion of the InternalEMPIRE `{dataset}` input.
It contains the electricity model and the natural-gas inputs currently
implemented by OpenEMPIRE.jl. The horizon is {periods} strategic periods.

Regenerate it from the workspace root with:

```bash
conda run -n empire_env python \\
  OpenEMPIRE.jl/scripts/convert_internalempire_xlsx.py
```

`conversion_manifest.json` records source-workbook and output-file SHA-256
hashes. `NaturalGas/terminal_cost_duplicate_audit.csv` records duplicate source
keys resolved with Pyomo-compatible last-row-wins semantics.
`NaturalGas/reserves_duplicate_audit.csv` records the same explicit resolution
for the duplicate Italy reserve.
"""
    (out / "README.md").write_text(text, encoding=ENCODING)


def write_readme(source: Path, extra_out: Path, dataset: str, periods: int) -> None:
    lines = [
        f"# `{dataset}` — data that does not fit the core CSV layout",
        "",
        f"Generated by `InternalEMPIRE/xlsx_to_csv_int.py` from `{source}`.",
        f"Horizon: {periods} investment periods (`NoOfPeriods` in `run_EMPIRE_int.py`).",
        "",
        "## Layout",
        "",
        "- `Sets/`, `Generator/`, `Transmission/`, `Node/`, `General/`, `Storage/` —",
        "  `<Sheet>_extra.csv` holds the columns of a core sheet that the model does not",
        "  read (sources, commentary, intermediate calculations), prefixed by the sheet's",
        "  key columns. The other files are sheets of the core workbooks that only the",
        "  internal modules read (`MaxInstalledCapacityByPeriod`, `AvailableBioEnergy`,",
        "  `OffshoreConverter*`, `Latitude`/`Longitude`, the natural-gas and industry sets).",
        "- `CO2/`, `NaturalGas/`, `Hydrogen/`, `Industry/`, `Transport/`, `HeatModule/` —",
        "  module tables, extracted with the exact sheet/column selections in",
        "  `InternalEMPIRE/reader.py`.",
        "- `ScenarioData/HeatModule/` — heat load and air-source heat-pump COP series.",
        "- `_beyond_horizon/` — rows dropped from the core tables because their `Period`",
        f"  exceeds {periods}; kept so nothing from the workbooks is lost.",
        "",
        "## Derived in the core dataset",
        "",
        "- `Sets/OffshoreWindFarmNode.csv` and `Sets/OffshoreEnergyHub.csv` split the",
        "  offshore nodes (`Sets.xlsx!Nodes!Node` minus `!OnshoreNode`) using the two",
        "  hardcoded lists in `run_EMPIRE_int.py` — the internal workbooks record the",
        "  classification nowhere. Wind farms have their corridors capped by their own",
        "  generation; hubs are capped by converter capacity instead; offshore nodes in",
        "  neither list (the Sleipner and Draupner gas platforms) get neither treatment.",
        "  The source `OnshoreNode` column is kept here as `Sets/OnshoreNode.csv`.",
        f"- `Sets/Period.csv` = 1..{periods} (the internal workbooks have no `Horizon` sheet).",
        "- `Sets/ThermalGenerators.csv` = `Sets.xlsx!Generators!RampingGenerators`, which is",
        "  the same set under the name the open dataset and the Julia port use.",
        "",
        "## Sheets left in the workbooks",
        "",
        "Spreadsheet working areas — raw source series, pivots and calculation scratch —",
        "that no EMPIRE reader touches:",
        "",
    ]
    for workbook, sheets in UNCONVERTED_SHEETS.items():
        lines.append(f"- `{workbook}`: {', '.join(sheets)}")
    lines.append("")
    path = extra_out / "README.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding=ENCODING)


# --------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-d", "--dataset", default="full_model_int",
                        help="dataset folder under 'Data handler/' (default: full_model_int)")
    parser.add_argument(
        "--source-root",
        type=Path,
        default=WORKSPACE_ROOT / "InternalEMPIRE" / "Data handler",
                        help="folder holding the Excel datasets")
    parser.add_argument("--data-root", type=Path,
                        default=OPENEMPIRE_ROOT / "data",
                        help="where the CSV dataset is written")
    parser.add_argument("--extra-root", type=Path,
                        default=OPENEMPIRE_ROOT / "data_extra",
                        help="where the non-core tables are written")
    parser.add_argument("--periods", type=int, default=7,
                        help="investment periods to keep (default: 7)")
    parser.add_argument("--skip-modules", action="store_true",
                        help="only build the core dataset")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s",
                        datefmt="%H:%M:%S")

    source = args.source_root / args.dataset
    if not source.is_dir():
        raise SystemExit(f"No such dataset: {source}")

    out = args.data_root / args.dataset
    extra_out = args.extra_root / args.dataset
    for folder in (out, extra_out):
        if folder.exists():
            shutil.rmtree(folder)

    logger.info("Converting %s -> %s", source, out)
    convert_core_sets(source, out, extra_out, args.periods)
    convert_core_tables(source, out, extra_out, args.periods)
    materialize_pyomo_period_defaults(out, args.periods)
    fill_missing_gas_fuel_costs(out, args.periods)
    copy_scenario_data(source, out, extra_out)
    convert_extra_tables(source, extra_out, args.periods)
    if not args.skip_modules:
        convert_modules(source, extra_out, args.periods)
        duplicate_audit, reserve_duplicate_audit = promote_natural_gas_inputs(
            extra_out,
            out,
        )
    else:
        duplicate_audit = []
        reserve_duplicate_audit = []
    write_dataset_readme(out, args.dataset, args.periods)
    write_conversion_manifest(
        source,
        out,
        args.dataset,
        args.periods,
        duplicate_audit,
        reserve_duplicate_audit,
    )
    write_readme(source, extra_out, args.dataset, args.periods)
    logger.info("Done. Core: %s | Extra: %s", out, extra_out)


if __name__ == "__main__":
    main()
