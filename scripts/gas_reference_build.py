"""Build an unmodified InternalEMPIRE gas-reference LP in an isolated directory.

The script generates tabs from the supplied workbook tree, drives InternalEMPIRE's
actual ``empire.py`` builder, and records code/data hashes beside the LP. Hydrogen is
enabled because the reference cannot build with it disabled; ``ng_forHydrogen`` is
enumerated explicitly by the comparator as the one out-of-scope gas-balance column.
No source workbook or file in the InternalEMPIRE checkout is modified.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

EXPECTED_INTERNAL_COMMIT = "14675a780129e11d03b9e9f4a03fb2649c715346"
HERE = Path(__file__).resolve().parent
REPO = ""
TABS = ""
RESULTS = ""
TEMP = ""

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


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_reference(repo, expected_commit):
    commit = subprocess.check_output(
        ["git", "-C", repo, "rev-parse", "HEAD"], text=True
    ).strip()
    if commit != expected_commit:
        raise RuntimeError(
            f"InternalEMPIRE commit mismatch: expected {expected_commit}, found {commit}"
        )
    code_files = ("empire.py", "reader.py", "scenario_random.py", "run_EMPIRE_int.py")
    changed = subprocess.run(
        ["git", "-C", repo, "diff", "--quiet", "--", *code_files]
    ).returncode
    if changed:
        raise RuntimeError(
            "InternalEMPIRE reference code is modified; refusing a non-reproducible comparison"
        )
    return commit, code_files


def prepare_tabs(reader_module, source_data):
    """Generate a fresh, unedited tab set in the isolated comparison directory."""
    if os.path.exists(TABS):
        shutil.rmtree(TABS)
    reader_module.generate_tab_files(
        filepath=source_data,
        tab_file_path=TABS,
        HEATMODULE=False,
        hydrogen=True,
        industry=False,
        periods=NoOfPeriods,
        gas_stochasticity_flag=False,
    )


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


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--internal-repo",
        type=Path,
        default=HERE.parents[1] / "InternalEMPIRE",
        help="InternalEMPIRE checkout (default: sibling workspace checkout)",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        help="isolated output directory (default: a retained temporary directory)",
    )
    parser.add_argument("--periods", type=int, choices=(2, 3), default=2)
    parser.add_argument("--weather-scenarios", type=int, choices=(1, 2), default=1)
    parser.add_argument("--expected-commit", default=EXPECTED_INTERNAL_COMMIT)
    parser.add_argument(
        "--solve",
        action="store_true",
        help="solve after writing the LP (not needed for structural assurance)",
    )
    return parser.parse_args(argv)


def main(argv=None):
    global REPO, TABS, RESULTS, TEMP, NoOfPeriods, NoOfScenarios
    args = parse_args(argv)
    repo = args.internal_repo.resolve()
    work_dir = (
        args.work_dir.resolve()
        if args.work_dir
        else Path(tempfile.mkdtemp(prefix="openempire-gas-reference-"))
    )
    work_dir.mkdir(parents=True, exist_ok=True)
    REPO = str(repo)
    TABS = str(work_dir / "tabs")
    RESULTS = str(work_dir / "results")
    TEMP = str(work_dir / "solver-temp")
    NoOfPeriods = args.periods
    NoOfScenarios = args.weather_scenarios

    commit, code_files = verify_reference(REPO, args.expected_commit)
    sys.path.insert(0, REPO)

    import empire
    import reader
    from scenario_random import generate_random_scenario

    source_data = os.path.join(REPO, "Data handler", "full_model_int")
    prepare_tabs(reader, source_data)

    provenance = {
        "internal_repo": REPO,
        "internal_commit": commit,
        "reference_code": [
            {"path": path, "sha256": sha256(os.path.join(REPO, path))}
            for path in code_files
        ],
        "source_workbooks": [
            {
                "path": str(path.relative_to(repo)),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in sorted((repo / "Data handler" / "full_model_int").rglob("*.xlsx"))
        ],
        "generated_tabs": [
            {
                "path": str(path.relative_to(work_dir)),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in sorted((work_dir / "tabs").rglob("*.tab"))
        ],
        "periods": NoOfPeriods,
        "weather_scenarios": NoOfScenarios,
        "gas_scenarios": NoOfGasScenarios,
        "regular_seasons": regular_seasons,
        "regular_season_hours": lengthRegSeason,
        "peak_seasons": NoOfPeakSeason,
        "peak_season_hours": lengthPeakSeason,
        "repurpose_cost_factor": 1.0,
        "repurpose_energy_flow_factor": 0.0,
        "fixed_out_of_scope_variables": {"repurposedPipelineBuilt": 0.0},
        "solve_requested": args.solve,
    }
    (work_dir / "reference_provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )

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

    class BuildComplete(Exception):
        """Stop the reference immediately after its unmodified builder writes the LP."""

    class BuildOnlySolver:
        def __init__(self):
            self.options = {}

        def solve(self, *_args, **_kwargs):
            raise BuildComplete

    original_solver_factory = empire.SolverFactory
    original_model_write = empire.ConcreteModel.write

    def write_gas_only_reference(model, *write_args, **write_kwargs):
        """Fix out-of-scope H2 repurposing before the reference exports its LP."""
        for variable in model.repurposedPipelineBuilt.values():
            variable.fix(0.0)
        return original_model_write(model, *write_args, **write_kwargs)

    empire.ConcreteModel.write = write_gas_only_reference
    if not args.solve:
        empire.SolverFactory = lambda *_args, **_kwargs: BuildOnlySolver()

    previous_directory = os.getcwd()
    os.chdir(work_dir)
    try:
        try:
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
                # Hydrogen pipeline repurposing is outside the deterministic gas port.
                # Zero is an existing reference configuration and removes its column
                # from gas-pipeline capacity rows without modifying reference code.
                repurposeEnergyFlowFactor=0.0,
                windfarmNodes=windfarm,
                hydrogen=True,
                HEATMODULE=False,
                industry=False,
                FLEX_IND=True,
                use_cvar=False,
                gas_stochasticity_flag=False,
            )
        except BuildComplete:
            pass
    finally:
        empire.SolverFactory = original_solver_factory
        empire.ConcreteModel.write = original_model_write
        os.chdir(previous_directory)

    lp_path = work_dir / "LP_gasparity.lp"
    if not lp_path.is_file() or lp_path.stat().st_size == 0:
        raise RuntimeError("InternalEMPIRE did not write a nonempty LP")

    print(f"reference work directory: {work_dir}")
    print(f"reference provenance: {work_dir / 'reference_provenance.json'}")
    print(f"reference LP: {work_dir / 'LP_gasparity.lp'}")


if __name__ == "__main__":
    main()
