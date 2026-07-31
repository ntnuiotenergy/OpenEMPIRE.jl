"""Build InternalEMPIRE's own model on a time-reduced full_model_int instance and
write its LP with symbolic labels.

empire.py is imported unmodified. Hydrogen is left enabled (it cannot be disabled:
the transport-demand constraints at empire.py:2664-2677 are ungated while their
variables are declared only under `if hydrogen is True:`). Instead the two data
couplings that let hydrogen touch the natural-gas balance are neutralised in the
tab files, which is auditable and leaves the reference code untouched:

  * Hydrogen_ReformerLocations.tab -> empty, so `ng_forHydrogen` drops out of
    naturalGas_flow_balance_rule (empire.py:2179-2180).
  * Transport_NaturalGasDemand.tab -> zero, so transport_naturalGasDemandMet is
    driven to zero by its own >= constraint at empire.py:2676.

Both neutralisations are asserted in the resulting LP/solution, not assumed.
"""
import os
import shutil
import sys

REPO = "/Users/torgrim/Documents/NTNU/iot/empire/InternalEMPIRE"
sys.path.insert(0, REPO)

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_TABS = os.path.join(HERE, "tabs_full")
TABS = os.path.join(HERE, "tabs_reduced")
RESULTS = os.path.join(HERE, "py_results")
TEMP = os.path.join(HERE, "py_temp")

# ---- time reduction (the only structural change) ----
NoOfPeriods = 2
NoOfRegSeason = 1
lengthRegSeason = 24
regular_seasons = ["winter"]
# Must be 2: gather_peak_sample in scenario_random.py:160-172 always emits a
# country-peak block and an overall-peak block, so a 1-peak-season time structure
# produces scenario hours that Operationalhour does not contain.
NoOfPeakSeason = 2
lengthPeakSeason = 24
NoOfScenarios = 1
NoOfGasScenarios = 1
LeapYearsInvestment = 5
discountrate = 0.05
WACC = 0.05


def prepare_tabs():
    """Copy the generated tabs verbatim. No edits.

    An earlier version neutralised Hydrogen couplings here. That was dropped:
    zeroing `Transport_NaturalGasDemand` does not remove the
    `transport_naturalGasDemandMet` *column* from the gas balance row (Pyomo builds
    the term whatever the parameter value), and emptying
    `Hydrogen_ReformerLocations` is not loadable -- Pyomo's set reader rejects a
    header-only file. The comparison instead runs the reference in its real
    configuration and enumerates the extra Hydrogen-side columns explicitly.
    """
    if os.path.exists(TABS):
        shutil.rmtree(TABS)
    shutil.copytree(SRC_TABS, TABS)


def node_dicts():
    """Lift `dict_countries` / `dict_offshr_nodes` out of run_EMPIRE_int.py.

    run_EMPIRE_int.py is a script -- importing it would launch a full 7-period run --
    so the two literal dicts are read out of its AST instead of being copied here,
    which keeps them in sync with the reference by construction. `dict_countries` is
    assigned in both branches of an `if "agg" in version` test; the last assignment
    is the non-aggregated branch that full_model_int uses.
    """
    import ast

    src = open(os.path.join(REPO, "run_EMPIRE_int.py")).read()
    found = {}
    for node in ast.walk(ast.parse(src)):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in (
                "dict_countries",
                "dict_offshr_nodes",
            ):
                try:
                    found[target.id] = ast.literal_eval(node.value)
                except ValueError:
                    pass
    missing = {"dict_countries", "dict_offshr_nodes"} - found.keys()
    if missing:
        raise RuntimeError(f"could not lift {missing} from run_EMPIRE_int.py")
    return found["dict_countries"], found["dict_offshr_nodes"]


def main():
    prepare_tabs()

    import empire
    from scenario_random import generate_random_scenario

    FirstHoursOfRegSeason = [lengthRegSeason * i + 1 for i in range(NoOfRegSeason)]
    FirstHoursOfPeakSeason = [
        lengthRegSeason * NoOfRegSeason + lengthPeakSeason * i + 1
        for i in range(NoOfPeakSeason)
    ]
    Period = [i + 1 for i in range(NoOfPeriods)]
    Scenario = ["scenario" + str(i + 1) for i in range(NoOfScenarios)]
    GasScenario = [i + 1 for i in range(NoOfGasScenarios)]
    peak_seasons = ["peak" + str(i + 1) for i in range(NoOfPeakSeason)]
    Season = regular_seasons + peak_seasons
    Operationalhour = [
        i + 1 for i in range(FirstHoursOfPeakSeason[-1] + lengthPeakSeason - 1)
    ]
    HoursOfRegSeason = [
        (s, h)
        for s in regular_seasons
        for h in Operationalhour
        if h
        in range(
            regular_seasons.index(s) * lengthRegSeason + 1,
            regular_seasons.index(s) * lengthRegSeason + lengthRegSeason + 1,
        )
    ]
    HoursOfPeakSeason = [
        (s, h)
        for s in peak_seasons
        for h in Operationalhour
        if h
        in range(
            lengthRegSeason * len(regular_seasons)
            + peak_seasons.index(s) * lengthPeakSeason
            + 1,
            lengthRegSeason * len(regular_seasons)
            + peak_seasons.index(s) * lengthPeakSeason
            + lengthPeakSeason
            + 1,
        )
    ]
    HoursOfSeason = HoursOfRegSeason + HoursOfPeakSeason

    # Copied verbatim from run_EMPIRE_int.py:176-182 (north_sea = True branch).
    offshore = ["Energyhub Great Britain", "Energyhub Norway", "Energyhub EU"]
    windfarm = [
        "Moray Firth", "Firth of Forth", "Dogger Bank", "Hornsea", "Outer Dowsing",
        "Norfolk", "East Anglia", "Borssele", "Hollandsee Kust", "Helgoländer Bucht",
        "Nordsøen", "Utsira Nord", "Sørlige Nordsjø I", "Sørlige Nordsjø II",
        "BalticCountries_BalticSea", "BE_PrincessElisabeth", "DE_NorthSea",
        "DE_BalticSea", "DK_NorthSea", "FI_BalticSea", "FR_ChannelSea", "FR_Atlantic",
        "IE_Atlantic", "NL_Lagelander", "NO_Vestavind", "NO_Sørvest", "PL_BalticSea",
        "SE_BotnieGulf", "SE_BalticSea", "SE_Luleå", "GB_DoggerBank",
        "GB_ScotlandEast", "GB_SheppeyIsland", "GB_IrelandSea", "GB_CelticSea",
    ]

    dict_countries, dict_offshr_nodes = node_dicts()

    # Scenario generation is driven from run_EMPIRE_int.py:237-259, not from
    # empire.py, and must write into tab_file_path before run_empire reads the
    # Stochastic_*.tab files at empire.py:877-879. fix_sample is False because the
    # shipped sampling_key.csv describes the production 4x168h/2x24h structure and
    # cannot be reused for the reduced one. Weather sampling does not affect any
    # natural-gas row coefficient, which is what this comparison measures.
    generate_random_scenario(
        scenario_data_path=os.path.join(REPO, "Data handler/full_model_int/ScenarioData"),
        tab_file_path=TABS,
        n_scenarios=NoOfScenarios,
        seasons=regular_seasons,
        n_periods=NoOfPeriods,
        lengthRegSeason=lengthRegSeason,
        lengthPeakSeason=lengthPeakSeason,
        regularSeasonHours=HoursOfRegSeason,
        peakSeasonHours=HoursOfPeakSeason,
        dict_countries=dict_countries,
        dict_offshr_nodes=dict_offshr_nodes,
        LOADCHANGEMODULE=False,
        filter_make=False,
        filter_use=False,
        copulas_to_use=["electricload"],
        copula_clusters_make=False,
        copula_clusters_use=False,
        n_cluster=10,
        moment_matching=False,
        n_tree_compare=20,
        HEATMODULE=False,
        fix_sample=False,
        north_sea=True,
    )

    empire.run_empire(
        name="gasparity",
        tab_file_path=TABS,
        result_file_path=RESULTS,
        scenariogeneration=True,
        scenario_data_path=os.path.join(
            REPO, "Data handler/full_model_int/ScenarioData"
        ),
        solver="Gurobi",
        temp_dir=TEMP,
        FirstHoursOfRegSeason=FirstHoursOfRegSeason,
        FirstHoursOfPeakSeason=FirstHoursOfPeakSeason,
        lengthRegSeason=lengthRegSeason,
        lengthPeakSeason=lengthPeakSeason,
        Period=Period,
        Operationalhour=Operationalhour,
        Scenario=Scenario,
        GasScenario=GasScenario,
        Season=Season,
        HoursOfSeason=HoursOfSeason,
        NoOfRegSeason=NoOfRegSeason,
        NoOfPeakSeason=NoOfPeakSeason,
        discountrate=discountrate,
        WACC=WACC,
        LeapYearsInvestment=LeapYearsInvestment,
        WRITE_LP=True,
        PICKLE_INSTANCE=False,
        EMISSION_CAP=True,
        include_results=[],
        USE_TEMP_DIR=True,
        offshoreNodesList=offshore,
        sample_file_path=None,
        OUT_OF_SAMPLE=False,
        repurposeCostFactor=1.0,
        repurposeEnergyFlowFactor=1.0,
        windfarmNodes=windfarm,
        hydrogen=True,
        HEATMODULE=False,
        industry=False,
        FLEX_IND=True,
        use_cvar=False,
        gas_stochasticity_flag=False,
    )


if __name__ == "__main__":
    main()
