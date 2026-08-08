function _assert_profile_lengths(profile, periods)
    for strategic_period in strat_periods(periods)
        for representative_period in repr_periods(strategic_period)
            for operational_scenario in opscenarios(representative_period)
                @test length([profile[t] for t in operational_scenario]) == length(operational_scenario)
            end
        end
    end
end

function _scenario_test_sets(test_nodes = ["A"])
    test_generators = ["Solar", "Windonshore", "Windoffshore", "Hydrorun-of-the-river"]
    return OpenEMPIRE.EmpireSets(
        Generator = test_generators,
        HydroGenerator = ["Hydrorun-of-the-river"],
        RegHydroGenerator = String[],
        Storage = String[],
        DependentStorage = String[],
        Technology = ["SolarTech", "WindOnTech", "WindOffTech", "HydroRorTech"],
        Node = collect(String.(test_nodes)),
        DirectionalLink = Tuple{String, String}[],
        TransmissionType = String[],
        TransmissionTypeOfDirectionalLink = Tuple{String, String, String}[],
        GeneratorsOfTechnology = [
            ("SolarTech", "Solar"),
            ("WindOnTech", "Windonshore"),
            ("WindOffTech", "Windoffshore"),
            ("HydroRorTech", "Hydrorun-of-the-river"),
        ],
        GeneratorsOfNode = [(node, generator) for node in test_nodes for generator in test_generators],
        StoragesOfNode = Tuple{String, String}[],
    )
end

function _scenario_time_rows(year::Int = 2020)
    starts = DateTime[
        DateTime(year, 1, 1),
        DateTime(year, 4, 1),
        DateTime(year, 7, 1),
        DateTime(year, 10, 1),
    ]
    rows = String[]
    value = 1
    for start in starts
        for h in 0:29
            timestamp = Dates.format(start + Dates.Hour(h), dateformat"dd/mm/yyyy HH:MM")
            push!(rows, "$timestamp,$value")
            value += 1
        end
    end
    return rows
end

function _write_raw_scenario_file(path, rows; scale = 1.0)
    scaled = String[]
    for row in rows
        timestamp, value = split(row, ",")
        push!(scaled, "$timestamp,$(parse(Float64, value) * scale)")
    end
    _write_csv(path, "time,A\n" * join(scaled, "\n") * "\n")
end

function _write_fixed_sample_scenario_data(root)
    scenario_dir = joinpath(root, "ScenarioData")
    rows = _scenario_time_rows()
    _write_raw_scenario_file(joinpath(scenario_dir, "electricload.csv"), rows)
    _write_raw_scenario_file(joinpath(scenario_dir, "hydroseasonal.csv"), rows; scale = 10.0)
    _write_raw_scenario_file(joinpath(scenario_dir, "solar.csv"), rows; scale = 0.01)
    _write_raw_scenario_file(joinpath(scenario_dir, "windonshore.csv"), rows; scale = 0.02)
    _write_raw_scenario_file(joinpath(scenario_dir, "windoffshore.csv"), rows; scale = 0.03)
    _write_raw_scenario_file(joinpath(scenario_dir, "hydroror.csv"), rows; scale = 0.04)
    _write_csv(
        joinpath(scenario_dir, "sampling_key.csv"),
        """
Period,Scenario,Season,Year,Month,Hour
1,1,winter,2020,1,1
1,1,spring,2020,4,0
1,1,summer,2020,7,0
1,1,fall,2020,10,0
1,1,peak,2020,0,0
""",
    )
end

function _copula_cluster_time_rows()
    starts = DateTime[
        DateTime(2020, 1, 1), DateTime(2020, 4, 1), DateTime(2020, 7, 1), DateTime(2020, 10, 1),
        DateTime(2021, 1, 1), DateTime(2021, 4, 1), DateTime(2021, 7, 1), DateTime(2021, 10, 1),
    ]
    rows = String[]
    for start in starts
        for h in 0:39
            timestamp = Dates.format(start + Dates.Hour(h), dateformat"dd/mm/yyyy HH:MM")
            value = h < 20 ? 10.0 + h * 0.1 : 1000.0 + h * 0.1
            push!(rows, "$timestamp,$value")
        end
    end
    return rows
end

# Two years of data, each regular season made of a "low" block of 20 hours
# followed by a "high" block of 20 hours, so copula clustering (k=2) has a
# clearly separable candidate space to work with.
function _write_copula_cluster_scenario_data(root)
    scenario_dir = joinpath(root, "ScenarioData")
    rows = _copula_cluster_time_rows()
    _write_raw_scenario_file(joinpath(scenario_dir, "electricload.csv"), rows)
    _write_raw_scenario_file(joinpath(scenario_dir, "hydroseasonal.csv"), rows; scale = 10.0)
    _write_raw_scenario_file(joinpath(scenario_dir, "solar.csv"), rows; scale = 0.01)
    _write_raw_scenario_file(joinpath(scenario_dir, "windonshore.csv"), rows; scale = 0.02)
    _write_raw_scenario_file(joinpath(scenario_dir, "windoffshore.csv"), rows; scale = 0.03)
    _write_raw_scenario_file(joinpath(scenario_dir, "hydroror.csv"), rows; scale = 0.04)
    return scenario_dir
end

function _copula_test_empire_params()
    return OpenEMPIRE.EmpireParams(
        genCapAvailType = Dict(
            "Solar" => 0.0,
            "Windonshore" => 0.0,
            "Windoffshore" => 0.0,
            "Hydrorun-of-the-river" => 0.0,
        ),
    )
end

function _parity_time_rows()
    starts = DateTime[
        DateTime(2020, 1, 1),
        DateTime(2020, 4, 1),
        DateTime(2020, 7, 1),
        DateTime(2020, 10, 1),
    ]
    rows = Tuple{String, Int}[]
    row_index = 0
    for start in starts
        for h in 0:7
            timestamp = Dates.format(start + Dates.Hour(h), dateformat"dd/mm/yyyy HH:MM")
            push!(rows, (timestamp, row_index))
            row_index += 1
        end
    end
    return rows
end

function _write_two_node_scenario_file(path, rows, value_function)
    lines = ["time,A,B"]
    for (timestamp, row_index) in rows
        a, b = value_function(row_index)
        push!(lines, "$timestamp,$a,$b")
    end
    return _write_csv(path, join(lines, "\n") * "\n")
end

function _write_python_parity_scenario_data(root)
    scenario_dir = joinpath(root, "ScenarioData")
    rows = _parity_time_rows()
    _write_two_node_scenario_file(joinpath(scenario_dir, "electricload.csv"), rows, row_index -> begin
        if row_index == 12
            return (10000.0, 200.0 + row_index)
        elseif row_index == 20
            return (7000.0, 7000.0)
        end
        return (100.0 + row_index, 200.0 + row_index)
    end)
    _write_two_node_scenario_file(joinpath(scenario_dir, "hydroseasonal.csv"), rows, row_index -> begin
        return (1000.0 + row_index, 2000.0 + row_index)
    end)
    _write_two_node_scenario_file(joinpath(scenario_dir, "solar.csv"), rows, row_index -> begin
        return (0.01 + row_index / 1000, 0.51 + row_index / 1000)
    end)
    _write_two_node_scenario_file(joinpath(scenario_dir, "windonshore.csv"), rows, row_index -> begin
        return (0.02 + row_index / 1000, 0.52 + row_index / 1000)
    end)
    _write_two_node_scenario_file(joinpath(scenario_dir, "windoffshore.csv"), rows, row_index -> begin
        return (0.03 + row_index / 1000, 0.53 + row_index / 1000)
    end)
    _write_two_node_scenario_file(joinpath(scenario_dir, "hydroror.csv"), rows, row_index -> begin
        return (0.04 + row_index / 1000, 0.54 + row_index / 1000)
    end)
    _write_csv(
        joinpath(scenario_dir, "sampling_key.csv"),
        """
Period,Scenario,Season,Year,Month,Hour
1,1,winter,2020,1,1
1,1,spring,2020,4,2
1,1,summer,2020,7,3
1,1,fall,2020,10,4
1,1,peak,2020,0,0
""",
    )
    return scenario_dir
end

function _write_filter_parity_load(path; years = 2015:2016)
    lines = ["time,A,B"]
    value = 1
    for year in years
        starts = DateTime[
            DateTime(year, 1, 1),
            DateTime(year, 4, 1),
            DateTime(year, 7, 1),
            DateTime(year, 10, 1),
        ]
        for start in starts, hour in 0:7
            timestamp = Dates.format(start + Dates.Hour(hour), dateformat"dd/mm/yyyy HH:MM")
            push!(lines, "$timestamp,$value,$(2 * value + (value % 3))")
            value += 1
        end
    end
    return _write_csv(path, join(lines, "\n") * "\n")
end

function _python_filter_metrics_script()
    return raw"""
import pathlib
import sys

import pandas as pd

reference_repo = pathlib.Path(sys.argv[1])
input_path = pathlib.Path(sys.argv[2])
output_path = pathlib.Path(sys.argv[3])
regular_hours = int(sys.argv[4])
sys.path.insert(0, str(reference_repo))

from empire.core.scenario_random import make_mean, make_ws
from empire.core.scenario_utils import make_datetime

seasons = ["winter", "spring", "summer", "fall"]
data = make_datetime(pd.read_csv(input_path), "%d/%m/%Y %H:%M")
metrics = make_ws(data, regular_hours, seasons)
means = make_mean(data, regular_hours, seasons)
metrics.insert(len(metrics.columns), "Value2", means["Value"])
metrics.to_csv(output_path, index=False)
"""
end

function _run_python_filter_metrics(input_path, output_path, workdir; regular_hours::Int = 2)
    reference_repo = joinpath(dirname(pkgdir(OpenEMPIRE)), "OpenEMPIRE-csv")
    python = _python_reference_executable(reference_repo)
    if python === nothing || !isfile(joinpath(reference_repo, "empire", "core", "scenario_random.py"))
        return false
    end
    script_path = joinpath(workdir, "python_filter_metrics.py")
    write(script_path, _python_filter_metrics_script())
    try
        command = Cmd([
            python,
            script_path,
            reference_repo,
            input_path,
            output_path,
            string(regular_hours),
        ])
        run(addenv(command, "MPLBACKEND" => "Agg"))
    catch err
        @warn "Python filter metric generation failed; skipping parity check" exception = err
        return false
    end
    return true
end

function _python_reference_script()
    return raw"""
import importlib.util
import pathlib
import sys
import types

reference_repo = pathlib.Path(sys.argv[1])
scenario_data_path = pathlib.Path(sys.argv[2])
output_path = pathlib.Path(sys.argv[3])

def module(name):
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod

# The fixed-sample path does not use these optional scientific routines, but
# scenario_random imports them at module load time.
scipy = module("scipy")
stats = module("scipy.stats")
stats.kurtosis = lambda *args, **kwargs: 0.0
stats.skew = lambda *args, **kwargs: 0.0
stats.wasserstein_distance = lambda *args, **kwargs: 0.0
spatial = module("scipy.spatial")
spatial.Voronoi = type("Voronoi", (), {"__init__": lambda self, *args, **kwargs: None})
sklearn = module("sklearn")
cluster = module("sklearn.cluster")
cluster.KMeans = type("KMeans", (), {"__init__": lambda self, *args, **kwargs: None})
decomposition = module("sklearn.decomposition")
decomposition.PCA = type(
    "PCA",
    (),
    {
        "__init__": lambda self, *args, **kwargs: None,
        "fit_transform": lambda self, values: values,
        "explained_variance_ratio_": [],
    },
)
try:
    import matplotlib.pyplot
except Exception:
    matplotlib = module("matplotlib")
    pyplot = module("matplotlib.pyplot")
    null_axis = types.SimpleNamespace(
        scatter=lambda *args, **kwargs: None,
        set_xlabel=lambda *args, **kwargs: None,
        set_ylabel=lambda *args, **kwargs: None,
        set_zlabel=lambda *args, **kwargs: None,
        set_xticklabels=lambda *args, **kwargs: None,
        set_yticklabels=lambda *args, **kwargs: None,
        set_zticklabels=lambda *args, **kwargs: None,
    )
    pyplot.figure = lambda *args, **kwargs: types.SimpleNamespace(add_subplot=lambda *args, **kwargs: null_axis)
    pyplot.close = lambda *args, **kwargs: None
    pyplot.savefig = lambda *args, **kwargs: None
mpl_toolkits = module("mpl_toolkits")
mplot3d = module("mpl_toolkits.mplot3d")
mplot3d.Axes3D = type("Axes3D", (), {})

empire = module("empire")
empire.__path__ = [str(reference_repo / "empire")]
core = module("empire.core")
core.__path__ = [str(reference_repo / "empire" / "core")]

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

config_mod = load_module("empire.core.config", reference_repo / "empire" / "core" / "config.py")
load_module("empire.core.constants", reference_repo / "empire" / "core" / "constants.py")
load_module("empire.core.scenario_utils", reference_repo / "empire" / "core" / "scenario_utils.py")
load_module("empire.core.voronoi_sgr", reference_repo / "empire" / "core" / "voronoi_sgr.py")
scenario_mod = load_module("empire.core.scenario_random", reference_repo / "empire" / "core" / "scenario_random.py")

config = config_mod.EmpireConfiguration.from_dict({
    "use_temporary_directory": True,
    "temporary_directory": ".",
    "forecast_horizon_year": 2025,
    "number_of_scenarios": 1,
    "length_of_regular_season": 2,
    "discount_rate": 0.05,
    "wacc": 0.05,
    "optimization_solver": "HiGHS",
    "use_scenario_generation": True,
    "use_fixed_sample": True,
    "load_change_module": False,
    "filter_make": False,
    "filter_use": False,
    "n_cluster": 10,
    "moment_matching": False,
    "copula_clusters_make": False,
    "copula_clusters_use": False,
    "copulas_to_use": ["electricload"],
    "n_tree_compare": 1,
    "use_emission_cap": False,
    "compute_operational_duals": False,
    "print_in_iamc_format": False,
    "write_in_lp_format": False,
    "serialize_instance": False,
    "north_sea": False,
    "regular_seasons": ["winter", "spring", "summer", "fall"],
    "n_peak_seasons": 2,
    "len_peak_season": 4,
    "leap_years_investment": 5,
    "time_format": "%d/%m/%Y %H:%M",
})
scenario_mod.generate_random_scenario(
    empire_config=config,
    dict_countries={},
    scenario_data_path=scenario_data_path,
    output_path=output_path,
)
"""
end

function _python_reference_executable(reference_repo)
    python = joinpath(reference_repo, ".venv", "bin", "python")
    isfile(python) && return python
    return Sys.which("python3")
end

function _run_python_reference_generator(reference_repo, scenario_data_path, output_path, workdir)
    python = _python_reference_executable(reference_repo)
    if python === nothing || !isfile(joinpath(reference_repo, "empire", "core", "scenario_random.py"))
        return false
    end

    script_path = joinpath(workdir, "generate_python_reference.py")
    write(script_path, _python_reference_script())
    try
        run(Cmd([python, script_path, reference_repo, scenario_data_path, output_path]))
    catch err
        @warn "Python scenario reference generation failed; skipping parity check" exception = err
        return false
    end
    return true
end

_scenario_float(value) = round(Float64(value); digits = 12)

_load_rows(path) = sort!(
    [
        (
            String(row.Node),
            Int(row.Operationalhour),
            String(row.Scenario),
            Int(row.Period),
            _scenario_float(row.ElectricLoadRaw_in_MW),
        )
        for row in CSV.File(path; normalizenames = false)
    ],
)

_hydro_rows(path) = sort!(
    [
        (
            String(row.Node),
            Int(row.Period),
            String(row.Season),
            Int(row.Operationalhour),
            String(row.Scenario),
            _scenario_float(row.HydroGeneratorMaxSeasonalProduction),
        )
        for row in CSV.File(path; normalizenames = false)
    ],
)

_availability_rows(path) = sort!(
    [
        (
            String(row.Node),
            String(row.IntermitentGenerators),
            Int(row.Operationalhour),
            String(row.Scenario),
            Int(row.Period),
            _scenario_float(row.GeneratorStochasticAvailabilityRaw),
        )
        for row in CSV.File(path; normalizenames = false)
    ],
)

function test_read_raw_csv_scenarios()
    cfg = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"))
    periods = OpenEMPIRE.create_timestruct(
        2,
        cfg["leap_years_investment"],
        4,
        cfg["length_of_regular_season"],
        2,
        24,
        cfg["number_of_scenarios"],
    )
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)
        sets, params = OpenEMPIRE.read_data(dataset; format = :csv)

        OpenEMPIRE.generate_scenario_csv!(
            dataset,
            periods,
            params,
            sets,
            cfg;
            rng = MersenneTwister(1),
        )

        scenario_dir = joinpath(dataset, "ScenarioData")
        @test isfile(joinpath(scenario_dir, "sloadRaw.csv"))
        @test isfile(joinpath(scenario_dir, "maxRegHydroGenRaw.csv"))
        @test isfile(joinpath(scenario_dir, "genCapAvailStochRaw.csv"))
        @test isfile(joinpath(scenario_dir, "sampling_key.csv"))

        @test haskey(params.sloadRaw, "Germany")
        @test haskey(params.maxRegHydroGenRaw, "Germany")
        @test haskey(params.genCapAvail, ("Germany", "Solar"))
        @test haskey(params.genCapAvail, ("Denmark", "Windoffshore"))
        _assert_profile_lengths(params.sloadRaw["Germany"], periods)
        _assert_profile_lengths(params.maxRegHydroGenRaw["Germany"], periods)
        _assert_profile_lengths(params.genCapAvail[("Germany", "Solar")], periods)

        loaded_params = OpenEMPIRE.EmpireParams(genCapAvailType = copy(params.genCapAvailType))
        load_cfg = merge(cfg, Dict("use_scenario_generation" => false))
        OpenEMPIRE.read_scenario_data!(
            dataset,
            periods,
            loaded_params,
            sets,
            load_cfg,
            Dict(h => h <= 96 ? cld(h, 24) : 4 + cld(h - 96, 24) for h in 1:144),
        )
        @test loaded_params.sloadRaw["Germany"][first(opscenarios(first(repr_periods(first(strat_periods(periods))))))[1]] ==
              params.sloadRaw["Germany"][first(opscenarios(first(repr_periods(first(strat_periods(periods))))))[1]]
    end
end

function test_fixed_sample_raw_csv_scenarios()
    mktempdir() do root
        _write_fixed_sample_scenario_data(root)
        sets = _scenario_test_sets()
        params = OpenEMPIRE.EmpireParams(
            genCapAvailType = Dict(
                "Solar" => 0.0,
                "Windonshore" => 0.0,
                "Windoffshore" => 0.0,
                "Hydrorun-of-the-river" => 0.0,
            ),
        )
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "length_of_regular_season" => 2,
            "number_of_scenarios" => 1,
            "use_fixed_sample" => true,
            "filter_use" => true,
            "n_cluster" => 2,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 2, 2, 24, 1)

        OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))

        scenario_dir = joinpath(root, "ScenarioData")
        @test isfile(joinpath(scenario_dir, "sloadRaw.csv"))
        @test isfile(joinpath(scenario_dir, "maxRegHydroGenRaw.csv"))
        @test isfile(joinpath(scenario_dir, "genCapAvailStochRaw.csv"))

        strategic_period = first(strat_periods(periods))
        winter = collect(repr_periods(strategic_period))[1]
        spring = collect(repr_periods(strategic_period))[2]
        sc_winter = first(opscenarios(winter))
        sc_spring = first(opscenarios(spring))

        @test params.sloadRaw["A"][sc_winter[1]] == 2.0
        @test params.sloadRaw["A"][sc_winter[2]] == 3.0
        @test params.sloadRaw["A"][sc_spring[1]] == 31.0
        @test params.maxRegHydroGenRaw["A"][sc_winter[1]] == 20.0
        @test params.genCapAvail[("A", "Solar")][sc_winter[1]] == 0.02
        @test params.genCapAvail[("A", "Windoffshore")][sc_spring[1]] ≈ 0.93

        generated_files = ("sloadRaw.csv", "maxRegHydroGenRaw.csv", "genCapAvailStochRaw.csv")
        filtered_outputs = Dict(
            filename => read(joinpath(scenario_dir, filename), String)
            for filename in generated_files
        )
        unfiltered_params = OpenEMPIRE.EmpireParams(
            genCapAvailType = copy(params.genCapAvailType),
        )
        OpenEMPIRE.generate_scenario_csv!(
            root,
            periods,
            unfiltered_params,
            sets,
            merge(cfg, Dict("filter_use" => false));
            rng = MersenneTwister(1),
        )
        @test all(
            read(joinpath(scenario_dir, filename), String) == filtered_outputs[filename]
            for filename in generated_files
        )
    end
end

function test_copula_clusters_make_writes_csv()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        dateformat = OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M")
        load_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "electricload.csv"), dateformat)
        hydro_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "hydroseasonal.csv"), dateformat)
        generator_sources = OpenEMPIRE._raw_generator_sources(root, dateformat, sets)

        rows = OpenEMPIRE.make_copula_clusters(
            root,
            OpenEMPIRE.REGULAR_SCENARIO_SEASONS,
            4,
            ["electricload"],
            2,
            load_table,
            hydro_table,
            generator_sources,
            MersenneTwister(1);
            n_init = 5,
        )

        path = joinpath(root, "Copulas", "CopulaClusters", "copula_clusters.csv")
        @test isfile(path)
        @test !isempty(rows)
        @test all(r -> r.ClusterGroup in (0, 1), rows)
        @test Set(r.Season for r in rows) == Set(String.(OpenEMPIRE.REGULAR_SCENARIO_SEASONS))
        @test length(Set(r.ClusterGroup for r in rows)) == 2

        csv_rows = collect(CSV.File(path; normalizenames = false))
        @test length(csv_rows) == length(rows)
        # Column layout and order match Python's make_copula_filter, including the
        # rank-value columns the clustering ran on. The fixture has one node
        # column per variable, so a single copula variable gives one Value column.
        @test string.(propertynames(csv_rows[1])) ==
            ["Year", "Season", "SampleIndex", "Value1", "ClusterGroup"]
        @test all(r -> 0.0 < r.Value1 <= 1.0, csv_rows)

        # Clustering consumes the scenario RNG, so an equal seed reproduces the
        # catalog exactly, including the canonical ClusterGroup labels.
        repeated = OpenEMPIRE.make_copula_clusters(
            root,
            OpenEMPIRE.REGULAR_SCENARIO_SEASONS,
            4,
            ["electricload"],
            2,
            load_table,
            hydro_table,
            generator_sources,
            MersenneTwister(1);
            n_init = 5,
        )
        @test repeated == rows
    end
end

function test_copula_clusters_use_samples_from_clusters()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        dateformat = OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M")
        load_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "electricload.csv"), dateformat)
        hydro_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "hydroseasonal.csv"), dateformat)
        generator_sources = OpenEMPIRE._raw_generator_sources(root, dateformat, sets)
        OpenEMPIRE.make_copula_clusters(
            root,
            OpenEMPIRE.REGULAR_SCENARIO_SEASONS,
            4,
            ["electricload"],
            2,
            load_table,
            hydro_table,
            generator_sources,
            MersenneTwister(1);
            n_init = 5,
        )
        clusters = OpenEMPIRE._read_copula_clusters(root)
        clusters_by_season = Dict{String, Vector{OpenEMPIRE.CopulaClusterRow}}()
        for c in clusters
            push!(get!(clusters_by_season, c.Season, OpenEMPIRE.CopulaClusterRow[]), c)
        end

        params = _copula_test_empire_params()
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "length_of_regular_season" => 4,
            "number_of_scenarios" => 2,
            "copula_clusters_use" => true,
            "n_cluster" => 2,
            "copulas_to_use" => ["electricload"],
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 24, 2)

        OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))

        _assert_profile_lengths(params.sloadRaw["A"], periods)

        sampling_key_path = joinpath(root, "ScenarioData", "sampling_key.csv")
        @test isfile(sampling_key_path)
        regular_rows = [r for r in CSV.File(sampling_key_path; normalizenames = false) if String(r.Season) != "peak"]
        @test !isempty(regular_rows)

        used_clusters = Set{Int}()
        for row in regular_rows
            season = String(row.Season)
            year = Int(row.Year)
            hour = Int(row.Hour)
            match = findfirst(c -> c.Year == year && c.SampleIndex == hour, clusters_by_season[season])
            @test match !== nothing
            push!(used_clusters, clusters_by_season[season][match].ClusterGroup)
        end
        @test used_clusters == Set([0, 1])
    end
end

function test_copula_clusters_multiple_variables()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        dateformat = OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M")
        load_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "electricload.csv"), dateformat)
        hydro_table = OpenEMPIRE._read_raw_scenario_table(joinpath(root, "ScenarioData", "hydroseasonal.csv"), dateformat)
        generator_sources = OpenEMPIRE._raw_generator_sources(root, dateformat, sets)

        # Several variables at once: the joint distribution gains one dimension
        # per (variable, node) pair, which is the case the empirical copula is for.
        rows = OpenEMPIRE.make_copula_clusters(
            root,
            OpenEMPIRE.REGULAR_SCENARIO_SEASONS,
            4,
            ["electricload", "solar", "windoffshore"],
            2,
            load_table,
            hydro_table,
            generator_sources,
            MersenneTwister(1);
            n_init = 5,
        )
        @test !isempty(rows)
        @test all(r -> r.ClusterGroup in (0, 1), rows)
        @test Set(r.Season for r in rows) == Set(String.(OpenEMPIRE.REGULAR_SCENARIO_SEASONS))

        # Every listed variable must resolve to a raw table.
        for name in ("electricload", "hydroseasonal", "solar", "windonshore", "windoffshore", "hydroror")
            @test OpenEMPIRE._copula_source_table(name, load_table, hydro_table, generator_sources) !== nothing
        end
    end
end

# The scenario filter outranks copula clustering, so a run driven by the filter
# must not fail on a leftover `copula_clusters_use: true` with no catalog present.
function test_filter_takes_precedence_over_copula_clusters()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        params = _copula_test_empire_params()
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "length_of_regular_season" => 4,
            "number_of_scenarios" => 1,
            "filter_make" => true,
            "filter_use" => true,
            "copula_clusters_use" => true,
            "n_cluster" => 2,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 24, 1)

        OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))

        # The filter catalog drove sampling, and no copula catalog was created.
        @test isfile(joinpath(root, "ScenarioData", "filter_result.csv"))
        @test !isfile(OpenEMPIRE._copula_cluster_path(root))
        _assert_profile_lengths(params.sloadRaw["A"], periods)

        filter_rows = collect(CSV.File(joinpath(root, "ScenarioData", "filter_result.csv"); normalizenames = false))
        filter_keys = Set((String(r.Season), Int(r.Year), Int(r.SampleIndex)) for r in filter_rows)
        for row in CSV.File(joinpath(root, "ScenarioData", "sampling_key.csv"); normalizenames = false)
            String(row.Season) == "peak" && continue
            @test (String(row.Season), Int(row.Year), Int(row.Hour)) in filter_keys
        end
    end
end

function test_copula_clusters_use_without_make_errors()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        params = _copula_test_empire_params()
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "length_of_regular_season" => 4,
            "number_of_scenarios" => 1,
            "copula_clusters_use" => true,
            "n_cluster" => 2,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 24, 1)

        @test_throws ArgumentError OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))
    end
end

function test_copula_clusters_invalid_copula_name_errors()
    mktempdir() do root
        _write_copula_cluster_scenario_data(root)
        sets = _scenario_test_sets()
        params = _copula_test_empire_params()
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "length_of_regular_season" => 4,
            "number_of_scenarios" => 1,
            "copula_clusters_make" => true,
            "n_cluster" => 2,
            "copulas_to_use" => ["windpower"],
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 24, 1)

        @test_throws ArgumentError OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))
    end
end

function test_configurable_regular_scenario_seasons()
    mktempdir() do root
        _write_fixed_sample_scenario_data(root)
        _write_csv(
            joinpath(root, "ScenarioData", "sampling_key.csv"),
            """
Period,Scenario,Season,Year,Month,Hour
1,1,winter,2020,1,1
1,1,spring,2020,4,0
""",
        )

        sets = _scenario_test_sets()
        params = OpenEMPIRE.EmpireParams(
            genCapAvailType = Dict(
                "Solar" => 0.0,
                "Windonshore" => 0.0,
                "Windoffshore" => 0.0,
                "Hydrorun-of-the-river" => 0.0,
            ),
        )
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "regular_seasons" => ["winter", "spring"],
            "n_peak_seasons" => 0,
            "len_peak_season" => 24,
            "length_of_regular_season" => 2,
            "number_of_scenarios" => 1,
            "use_fixed_sample" => true,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 2, 2, 0, 24, 1)

        OpenEMPIRE.generate_scenario_csv!(root, periods, params, sets, cfg; rng = MersenneTwister(1))

        strategic_period = first(strat_periods(periods))
        winter = collect(repr_periods(strategic_period))[1]
        spring = collect(repr_periods(strategic_period))[2]
        winter_scenario = first(opscenarios(winter))
        spring_scenario = first(opscenarios(spring))

        @test params.sloadRaw["A"][winter_scenario[1]] == 2.0
        @test params.sloadRaw["A"][spring_scenario[1]] == 31.0
    end
end

function test_scenario_filter_metrics_and_clustering()
    @test OpenEMPIRE._wasserstein_distance_1d([0.0, 1.0], [0.0, 2.0]) == 0.5
    @test OpenEMPIRE._wasserstein_distance_1d([1.0, 1.0], [1.0]) == 0.0
    @test_throws ArgumentError OpenEMPIRE._wasserstein_distance_1d(Float64[], [1.0])
    @test_throws ArgumentError OpenEMPIRE._wasserstein_distance_1d([NaN], [1.0])
    @test OpenEMPIRE._wasserstein_distance_sorted(
        [0.0, 1.0, 1.0, 3.0],
        [0.0, 2.0],
    ) ≈ 0.75
    @test OpenEMPIRE._wasserstein_distance_sorted([1.0], [1.0, 1.0, 1.0]) == 0.0
    @test_throws ArgumentError OpenEMPIRE._wasserstein_distance_sorted(
        Float64[],
        [1.0],
    )

    mktempdir() do root
        load_path = joinpath(root, "electricload.csv")
        _write_filter_parity_load(load_path)
        table = OpenEMPIRE._read_raw_scenario_table(
            load_path,
            OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M"),
        )
        seasons = ("winter", "spring", "summer", "fall")
        metrics = OpenEMPIRE._filter_metric_rows(table, seasons, 2, [2015, 2016])
        @test length(metrics) == 40
        @test all(count(row -> row.Season == season, metrics) == 10 for season in seasons)
        @test [row.SampleIndex for row in metrics if row.Season == "winter"] ==
              vcat(collect(0:4), collect(0:4))

        restricted_metrics = OpenEMPIRE._filter_metric_rows(table, seasons, 2, [2016])
        @test length(restricted_metrics) == 20
        @test all(row.Year == 2016 for row in restricted_metrics)

        clustered = OpenEMPIRE._cluster_filter_rows(
            metrics,
            seasons,
            2,
            MersenneTwister(19);
            n_init = 5,
        )
        repeated = OpenEMPIRE._cluster_filter_rows(
            metrics,
            seasons,
            2,
            MersenneTwister(19);
            n_init = 5,
        )
        @test clustered == repeated
        for season in seasons
            groups = sort!(unique(row.ClusterGroup for row in clustered if row.Season == season))
            @test groups == [0, 1]
        end
        @test_throws ArgumentError OpenEMPIRE._cluster_filter_rows(
            metrics,
            seasons,
            11,
            MersenneTwister(1);
            n_init = 1,
        )

        python_output = joinpath(root, "python_filter_metrics.csv")
        if _run_python_filter_metrics(load_path, python_output, root)
            python_rows = collect(CSV.File(python_output; normalizenames = false))
            @test length(python_rows) == length(metrics)
            for (julia_row, python_row) in zip(metrics, python_rows)
                @test (
                    julia_row.Year,
                    julia_row.Season,
                    julia_row.SampleIndex,
                ) == (
                    Int(python_row.Year),
                    String(python_row.Season),
                    Int(python_row.SampleIndex),
                )
                @test julia_row.Value ≈ Float64(python_row.Value) rtol = 1e-12 atol = 1e-12
                @test julia_row.Value2 ≈ Float64(python_row.Value2) rtol = 1e-12 atol = 1e-12
            end
        else
            @test_skip "Python/SciPy filter reference is unavailable"
        end

        future_path = joinpath(root, "electricload_2021.csv")
        _write_filter_parity_load(future_path; years = (2021,))
        future_table = OpenEMPIRE._read_raw_scenario_table(
            future_path,
            OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M"),
        )
        future_metrics = OpenEMPIRE._filter_metric_rows(
            future_table,
            seasons,
            2,
            [2021],
        )
        @test length(future_metrics) == 20
        @test all(row.Year == 2021 for row in future_metrics)
    end
end

function test_scenario_filter_make_and_use()
    mktempdir() do root
        first_root = joinpath(root, "first")
        second_root = joinpath(root, "second")
        mkpath(first_root)
        _write_fixed_sample_scenario_data(first_root)
        _write_raw_scenario_file(
            joinpath(first_root, "ScenarioData", "electricload.csv"),
            vcat(_scenario_time_rows(2019), _scenario_time_rows(2020)),
        )
        cp(first_root, second_root)
        rm(joinpath(first_root, "ScenarioData", "sampling_key.csv"))
        rm(joinpath(second_root, "ScenarioData", "sampling_key.csv"))

        sets = _scenario_test_sets()
        config = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "regular_seasons" => ["winter", "spring", "summer", "fall"],
            "n_peak_seasons" => 0,
            "len_peak_season" => 0,
            "length_of_regular_season" => 2,
            "number_of_scenarios" => 3,
            "use_fixed_sample" => false,
            "filter_make" => true,
            "filter_use" => true,
            "n_cluster" => 3,
        )
        periods = OpenEMPIRE.create_timestruct(2, 5, 4, 2, 0, 0, 3)

        function generate_filtered(root_path, run_config = config)
            params = OpenEMPIRE.EmpireParams(
                genCapAvailType = Dict(
                    "Solar" => 0.0,
                    "Windonshore" => 0.0,
                    "Windoffshore" => 0.0,
                    "Hydrorun-of-the-river" => 0.0,
                ),
            )
            OpenEMPIRE.generate_scenario_csv!(
                root_path,
                periods,
                params,
                sets,
                run_config;
                rng = MersenneTwister(7),
            )
        end

        generate_filtered(first_root)
        generate_filtered(second_root)
        first_filter = joinpath(first_root, "ScenarioData", "filter_result.csv")
        second_filter = joinpath(second_root, "ScenarioData", "filter_result.csv")
        @test read(first_filter, String) == read(second_filter, String)

        filter_rows = collect(CSV.File(first_filter; normalizenames = false))
        @test string.(propertynames(first(filter_rows))) ==
              ["Year", "Season", "SampleIndex", "Value", "Value2", "ClusterGroup"]
        @test all(Int(row.Year) == 2020 for row in filter_rows)
        @test all(0 <= Int(row.ClusterGroup) < 3 for row in filter_rows)

        candidate_groups = Dict(
            (String(row.Season), Int(row.Year), Int(row.SampleIndex)) => Int(row.ClusterGroup)
            for row in filter_rows
        )
        first_sampling_key = joinpath(first_root, "ScenarioData", "sampling_key.csv")
        second_sampling_key = joinpath(second_root, "ScenarioData", "sampling_key.csv")
        @test read(first_sampling_key, String) == read(second_sampling_key, String)
        sampling_rows = collect(CSV.File(
            first_sampling_key;
            normalizenames = false,
        ))
        @test length(sampling_rows) == 24
        for (index, row) in enumerate(sampling_rows)
            expected_group = (index - 1) % 3
            key = (String(row.Season), Int(row.Year), Int(row.Hour))
            @test haskey(candidate_groups, key)
            @test candidate_groups[key] == expected_group
        end

        generate_filtered(first_root, merge(config, Dict("filter_make" => false)))
        reused_rows = collect(CSV.File(
            joinpath(first_root, "ScenarioData", "sampling_key.csv");
            normalizenames = false,
        ))
        @test length(reused_rows) == 24
        for (index, row) in enumerate(reused_rows)
            key = (String(row.Season), Int(row.Year), Int(row.Hour))
            @test haskey(candidate_groups, key)
            @test candidate_groups[key] == (index - 1) % 3
        end

        missing_root = joinpath(root, "missing")
        mkpath(joinpath(missing_root, "ScenarioData"))
        cp(
            joinpath(first_root, "ScenarioData", "electricload.csv"),
            joinpath(missing_root, "ScenarioData", "electricload.csv"),
        )
        load_table = OpenEMPIRE._read_raw_scenario_table(
            joinpath(missing_root, "ScenarioData", "electricload.csv"),
            OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M"),
        )
        @test_throws ArgumentError OpenEMPIRE._filter_candidate_groups(
            joinpath(missing_root, "ScenarioData"),
            ("winter",),
            2,
            load_table,
            2,
            [2020],
        )
        _write_csv(
            joinpath(missing_root, "ScenarioData", "filter_result.csv"),
            "Year,Season,SampleIndex,Value,Value2\n2020,winter,0,1.0,2.0\n",
        )
        @test_throws ArgumentError OpenEMPIRE._filter_candidate_groups(
            joinpath(missing_root, "ScenarioData"),
            ("winter",),
            2,
            load_table,
            2,
            [2020],
        )

        filter_header = "Year,Season,SampleIndex,Value,Value2,ClusterGroup\n"
        function assert_invalid_filter(rows::AbstractString, expected::AbstractString)
            _write_csv(
                joinpath(missing_root, "ScenarioData", "filter_result.csv"),
                filter_header * rows,
            )
            error = try
                OpenEMPIRE._filter_candidate_groups(
                    joinpath(missing_root, "ScenarioData"),
                    ("winter",),
                    2,
                    load_table,
                    2,
                    [2020],
                )
                nothing
            catch err
                err
            end
            @test error isa ArgumentError
            if error isa ArgumentError
                @test occursin(expected, sprint(showerror, error))
            end
            return nothing
        end

        valid_group_one = "2020,winter,1,1.1,2.1,1\n"
        assert_invalid_filter(
            "2020,winter,0,,2.0,0\n" * valid_group_one,
            "row 2 has an invalid Value",
        )
        assert_invalid_filter(
            "2020,winter,0,abc,2.0,0\n" * valid_group_one,
            "row 2 has an invalid Value",
        )
        assert_invalid_filter(
            "2020,winter,0.5,1.0,2.0,0\n" * valid_group_one,
            "row 2 has an invalid SampleIndex",
        )
        assert_invalid_filter(
            "99999999999999999999999,winter,0,1.0,2.0,0\n" * valid_group_one,
            "row 2 has an invalid Year",
        )
        assert_invalid_filter(
            "2020,,0,1.0,2.0,0\n" * valid_group_one,
            "row 2 has an invalid Season",
        )
        assert_invalid_filter(
            "2020,winter,0,NaN,2.0,0\n" * valid_group_one,
            "row 2 contains a non-finite metric",
        )
        assert_invalid_filter(
            "2020,winter,0,1.0,Inf,0\n" * valid_group_one,
            "row 2 contains a non-finite metric",
        )
        assert_invalid_filter(
            "2020,winter,-1,1.0,2.0,0\n" * valid_group_one,
            "row 2 contains a negative SampleIndex",
        )
        assert_invalid_filter(
            "2020,winter,0,1.0,2.0,3\n" * valid_group_one,
            "row 2 has ClusterGroup 3 outside 0:1",
        )
        assert_invalid_filter(
            "2020,winter,0,1.0,2.0,0\n2020,winter,0,1.1,2.1,1\n",
            "row 3 contains duplicate candidate",
        )
        assert_invalid_filter(
            "2019,winter,0,1.0,2.0,0\n" * valid_group_one,
            "Year=2019, which is not present in every raw scenario input",
        )
        assert_invalid_filter(
            "2020,winter,29,1.0,2.0,0\n" * valid_group_one,
            "hour 29 exceeds the 30 available rows",
        )
        assert_invalid_filter(
            "2020,winter,0,1.0,2.0,0\n",
            "has no candidates for season winter and ClusterGroup 1",
        )
    end
end

function test_scenario_filter_defaults()
    mktempdir() do root
        implicit_root = joinpath(root, "implicit")
        explicit_root = joinpath(root, "explicit")
        mkpath(implicit_root)
        _write_fixed_sample_scenario_data(implicit_root)
        cp(implicit_root, explicit_root)
        rm(joinpath(implicit_root, "ScenarioData", "sampling_key.csv"))
        rm(joinpath(explicit_root, "ScenarioData", "sampling_key.csv"))

        sets = _scenario_test_sets()
        config = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "regular_seasons" => ["winter", "spring", "summer", "fall"],
            "n_peak_seasons" => 0,
            "len_peak_season" => 0,
            "length_of_regular_season" => 2,
            "number_of_scenarios" => 2,
            "use_fixed_sample" => false,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 2, 0, 0, 2)

        function generate_unfiltered(root_path, run_config)
            params = OpenEMPIRE.EmpireParams(
                genCapAvailType = Dict(
                    "Solar" => 0.0,
                    "Windonshore" => 0.0,
                    "Windoffshore" => 0.0,
                    "Hydrorun-of-the-river" => 0.0,
                ),
            )
            OpenEMPIRE.generate_scenario_csv!(
                root_path,
                periods,
                params,
                sets,
                run_config;
                rng = MersenneTwister(31),
            )
        end

        generate_unfiltered(implicit_root, config)
        generate_unfiltered(
            explicit_root,
            merge(
                config,
                Dict(
                    "filter_make" => false,
                    "filter_use" => false,
                    "n_cluster" => 10,
                ),
            ),
        )
        for filename in (
            "sampling_key.csv",
            "sloadRaw.csv",
            "maxRegHydroGenRaw.csv",
            "genCapAvailStochRaw.csv",
        )
            @test read(
                joinpath(implicit_root, "ScenarioData", filename),
                String,
            ) == read(
                joinpath(explicit_root, "ScenarioData", filename),
                String,
            )
        end
    end
end

function test_python_fixed_sample_scenario_parity()
    reference_repo = joinpath(dirname(pkgdir(OpenEMPIRE)), "OpenEMPIRE-csv")

    mktempdir() do root
        raw_root = joinpath(root, "raw")
        julia_root = joinpath(root, "julia")
        python_output = joinpath(root, "python_output")
        _write_python_parity_scenario_data(raw_root)
        cp(raw_root, julia_root)

        generated = _run_python_reference_generator(
            reference_repo,
            joinpath(raw_root, "ScenarioData"),
            python_output,
            root,
        )
        if !generated
            @test_skip "OpenEMPIRE-csv Python reference generator is unavailable"
            return
        end

        sets = _scenario_test_sets(["A", "B"])
        params = OpenEMPIRE.EmpireParams(
            genCapAvailType = Dict(
                "Solar" => 0.0,
                "Windonshore" => 0.0,
                "Windoffshore" => 0.0,
                "Hydrorun-of-the-river" => 0.0,
            ),
        )
        cfg = Dict(
            "time_format" => "%d/%m/%Y %H:%M",
            "regular_seasons" => ["winter", "spring", "summer", "fall"],
            "n_peak_seasons" => 2,
            "len_peak_season" => 4,
            "length_of_regular_season" => 2,
            "number_of_scenarios" => 1,
            "use_fixed_sample" => true,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 2, 2, 4, 1)
        OpenEMPIRE.generate_scenario_csv!(julia_root, periods, params, sets, cfg; rng = MersenneTwister(1))

        julia_output = joinpath(julia_root, "ScenarioData")
        @test _load_rows(joinpath(julia_output, "sloadRaw.csv")) ==
              _load_rows(joinpath(python_output, "sloadRaw.csv"))
        @test _hydro_rows(joinpath(julia_output, "maxRegHydroGenRaw.csv")) ==
              _hydro_rows(joinpath(python_output, "maxRegHydroGenRaw.csv"))
        @test _availability_rows(joinpath(julia_output, "genCapAvailStochRaw.csv")) ==
              _availability_rows(joinpath(python_output, "genCapAvailStochRaw.csv"))
    end
end

function test_create_model_with_raw_csv_scenarios()
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)

        emp, periods, sets, params = OpenEMPIRE.create_model(
            joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"),
            dataset;
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        @test JuMP.num_variables(emp) > 0
        @test length(params.sloadRaw) == 3
        @test length(params.sload) == 3
        @test haskey(params.genCapAvail, ("Germany", "Solar"))
        @test isfile(joinpath(dataset, "ScenarioData", "sloadRaw.csv"))
    end
end

function test_generate_scenarios_without_model()
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)
        # Remove the shipped generated CSVs so the assertions prove this call writes them.
        scenario_dir = joinpath(dataset, "ScenarioData")
        for f in ("sloadRaw.csv", "maxRegHydroGenRaw.csv", "genCapAvailStochRaw.csv", "sampling_key.csv")
            rm(joinpath(scenario_dir, f); force = true)
        end

        periods, sets, params = OpenEMPIRE.generate_scenarios(
            joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"),
            dataset;
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        # No JuMP model is built, but the scenario CSVs (and a fresh sampling key,
        # since the test config is not fixed-sample) are written to disk and the
        # stochastic profiles are populated in params.
        @test isfile(joinpath(scenario_dir, "sloadRaw.csv"))
        @test isfile(joinpath(scenario_dir, "maxRegHydroGenRaw.csv"))
        @test isfile(joinpath(scenario_dir, "genCapAvailStochRaw.csv"))
        @test isfile(joinpath(scenario_dir, "sampling_key.csv"))
        @test length(params.sloadRaw) == 3
        @test haskey(params.genCapAvail, ("Germany", "Solar"))
    end
end

function test_write_scenario_sampling_key_artifacts()
    mktempdir() do root
        dataset = joinpath(root, "dataset")
        scenario_dir = joinpath(dataset, "ScenarioData")
        sampling_key = _write_csv(
            joinpath(scenario_dir, "sampling_key.csv"),
            """
Period,Scenario,Season,Year,Month,Hour
1,1,winter,2020,1,4
""",
        )
        _write_csv(joinpath(scenario_dir, "sloadRaw.csv"), "Node,Operationalhour,Scenario,Period,ElectricLoadRaw_in_MW\n")
        filter_result = _write_csv(
            joinpath(scenario_dir, "filter_result.csv"),
            "Year,Season,SampleIndex,Value,Value2,ClusterGroup\n2020,winter,0,1.0,2.0,0\n",
        )

        config = Dict(
            "use_scenario_generation" => true,
            "use_fixed_sample" => false,
            "number_of_scenarios" => 1,
            "length_of_regular_season" => 24,
            "regular_seasons" => ["winter"],
            "filter_make" => true,
            "filter_use" => true,
            "n_cluster" => 10,
        )
        config_file = joinpath(root, "run.yaml")
        YAML.write_file(config_file, config)

        result_dir = joinpath(root, "results")
        archived_key = OpenEMPIRE.write_scenario_artifacts(
            result_dir,
            dataset,
            config;
            config_file = config_file,
            dataset = "dataset",
            input_format = :csv,
            seed = 11,
        )

        expected_key = joinpath(result_dir, "Input", "ScenarioData", "sampling_key.csv")
        @test archived_key == expected_key
        @test read(expected_key, String) == read(sampling_key, String)
        @test isfile(joinpath(result_dir, "Input", "config.yaml"))
        archived_filter = joinpath(
            result_dir,
            "Input",
            "ScenarioData",
            "filter_result.csv",
        )
        @test read(archived_filter, String) == read(filter_result, String)

        metadata = YAML.load_file(joinpath(result_dir, "Input", "scenario_metadata.yaml"))
        @test metadata["dataset"] == "dataset"
        @test metadata["seed"] == 11
        @test metadata["input_format"] == "csv"
        @test metadata["use_scenario_generation"] == true
        @test metadata["use_fixed_sample"] == false
        @test metadata["filter_make"] == true
        @test metadata["filter_use"] == true
        @test metadata["n_cluster"] == 10
        @test metadata["archived_sampling_key"] == joinpath("Input", "ScenarioData", "sampling_key.csv")
        @test metadata["source_filter_result"] == filter_result
        @test metadata["archived_filter_result"] ==
              joinpath("Input", "ScenarioData", "filter_result.csv")
        @test metadata["generated_scenario_files_present"]["sloadRaw.csv"] == true

        unfiltered_result = joinpath(root, "unfiltered")
        unfiltered_config = merge(
            config,
            Dict("filter_make" => false, "filter_use" => false),
        )
        OpenEMPIRE.write_scenario_artifacts(
            unfiltered_result,
            dataset,
            unfiltered_config,
        )
        @test !ispath(joinpath(
            unfiltered_result,
            "Input",
            "ScenarioData",
            "filter_result.csv",
        ))
        unfiltered_metadata = YAML.load_file(joinpath(
            unfiltered_result,
            "Input",
            "scenario_metadata.yaml",
        ))
        @test !haskey(unfiltered_metadata, "archived_filter_result")
        staged_result = joinpath(root, "staged")
        staged_dataset = joinpath(staged_result, "Input", "csv")
        staged_config = joinpath(staged_result, "Input", "config.yaml")
        mkpath(dirname(staged_config))
        cp(dataset, staged_dataset)
        cp(config_file, staged_config)
        staged_key = joinpath(staged_dataset, "ScenarioData", "sampling_key.csv")
        @test OpenEMPIRE.write_scenario_artifacts(
            staged_result,
            staged_dataset,
            config;
            config_file = staged_config,
            dataset = "dataset",
            input_format = :csv,
            seed = 11,
        ) == staged_key
        @test !ispath(joinpath(staged_result, "Input", "ScenarioData", "sampling_key.csv"))
        staged_metadata = YAML.load_file(joinpath(staged_result, "Input", "scenario_metadata.yaml"))
        @test staged_metadata["staged_input"] == true
        @test staged_metadata["archived_sampling_key"] ==
              joinpath("Input", "csv", "ScenarioData", "sampling_key.csv")

        disabled_result = joinpath(root, "disabled")
        disabled_config = merge(config, Dict("use_scenario_generation" => false))
        @test OpenEMPIRE.write_scenario_artifacts(disabled_result, dataset, disabled_config) === nothing
        @test !ispath(joinpath(disabled_result, "Input", "ScenarioData", "sampling_key.csv"))
    end
end

function test_write_scenario_copula_cluster_artifacts()
    mktempdir() do root
        dataset = joinpath(root, "dataset")
        scenario_dir = joinpath(dataset, "ScenarioData")
        _write_csv(
            joinpath(scenario_dir, "sampling_key.csv"),
            """
Period,Scenario,Season,Year,Month,Hour
1,1,winter,2020,1,4
""",
        )
        copula_clusters = _write_csv(
            OpenEMPIRE._copula_cluster_path(dataset),
            "Season,Year,SampleIndex,ClusterGroup\nwinter,2020,0,0\nwinter,2020,1,1\n",
        )

        config = Dict(
            "use_scenario_generation" => true,
            "use_fixed_sample" => false,
            "number_of_scenarios" => 1,
            "length_of_regular_season" => 24,
            "regular_seasons" => ["winter"],
            "copula_clusters_make" => true,
            "copula_clusters_use" => true,
            "copulas_to_use" => ["electricload"],
            "n_cluster" => 2,
        )

        result_dir = joinpath(root, "results")
        OpenEMPIRE.write_scenario_artifacts(result_dir, dataset, config; seed = 3)

        archived_copula = joinpath(result_dir, "Input", "ScenarioData", "copula_clusters.csv")
        @test read(archived_copula, String) == read(copula_clusters, String)

        metadata = YAML.load_file(joinpath(result_dir, "Input", "scenario_metadata.yaml"))
        @test metadata["copula_clusters_make"] == true
        @test metadata["copula_clusters_use"] == true
        @test metadata["copulas_to_use"] == ["electricload"]
        @test metadata["source_copula_clusters"] == copula_clusters
        @test metadata["archived_copula_clusters"] ==
              joinpath("Input", "ScenarioData", "copula_clusters.csv")

        # Disabled copula clustering must not archive the catalog or claim it in metadata.
        plain_result = joinpath(root, "plain")
        plain_config = merge(
            config,
            Dict("copula_clusters_make" => false, "copula_clusters_use" => false),
        )
        OpenEMPIRE.write_scenario_artifacts(plain_result, dataset, plain_config)
        @test !ispath(joinpath(plain_result, "Input", "ScenarioData", "copula_clusters.csv"))
        plain_metadata = YAML.load_file(joinpath(plain_result, "Input", "scenario_metadata.yaml"))
        @test !haskey(plain_metadata, "archived_copula_clusters")
    end
end

function test_create_model_accepts_optimizer_type()
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)

        emp, periods, sets, params = OpenEMPIRE.create_model(
            joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"),
            dataset;
            optimizer = HiGHS.Optimizer,
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        @test JuMP.num_variables(emp) > 0
    end
end

_sparse_axis_length(container) = length(collect(eachindex(container)))

function test_storage_constraints_match_python_formulation()
    sets = OpenEMPIRE.EmpireSets(
        Storage = ["Battery"],
        DependentStorage = ["Battery"],
        Node = ["A"],
        StoragesOfNode = [("A", "Battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))
    t = first(periods)
    params = OpenEMPIRE.EmpireParams(
        storageDiscToCharRatio = Dict("Battery" => 2.0),
        storagePowToEnergy = Dict("Battery" => 3.0),
        storPWMaxBuiltCap = Dict(("A", "Battery") => StrategicProfile([20.0])),
        storENMaxBuiltCap = Dict(("A", "Battery") => StrategicProfile([10.0])),
        storPWMaxInstalledCap = Dict(("A", "Battery") => 40.0),
        storENMaxInstalledCap = Dict(("A", "Battery") => 30.0),
    )

    emp = JuMP.Model()
    OpenEMPIRE.create_variables(emp, sets, periods)
    OpenEMPIRE.create_storage_constraints(emp, sets, params, periods)

    discharge_cap = emp[:storage_op_cap_pow_dis]["A", "Battery", sp, t]
    @test JuMP.normalized_coefficient(discharge_cap, emp[:storDischarge]["A", "Battery", t]) == 1.0
    @test JuMP.normalized_coefficient(discharge_cap, emp[:storPWInstalledCap]["A", "Battery", sp]) == -2.0

    power_energy = emp[:storage_couple_pow_en]["A", "Battery", sp]
    @test JuMP.normalized_coefficient(power_energy, emp[:storPWInstalledCap]["A", "Battery", sp]) == 1.0
    @test JuMP.normalized_coefficient(power_energy, emp[:storENInstalledCap]["A", "Battery", sp]) == -3.0

    @test _sparse_axis_length(emp[:storage_max_inv_pow]) == 1
    @test _sparse_axis_length(emp[:storage_max_inv_en]) == 1
    @test _sparse_axis_length(emp[:storage_max_inst_pow]) == 1
    @test _sparse_axis_length(emp[:storage_max_inst_en]) == 1
end

function test_create_model_adds_storage_max_constraints()
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)

        emp, periods, sets, params = OpenEMPIRE.create_model(
            joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"),
            dataset;
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        expected = length(OpenEMPIRE.node_storages(sets)) * length(strat_periods(periods))
        @test _sparse_axis_length(emp[:storage_max_inv_pow]) == expected
        @test _sparse_axis_length(emp[:storage_max_inv_en]) == expected
        @test _sparse_axis_length(emp[:storage_max_inst_pow]) == expected
        @test _sparse_axis_length(emp[:storage_max_inst_en]) == expected
        @test JuMP.num_constraints(emp; count_variable_in_set_constraints = false) == 81190
    end
end

function test_north_sea_transmission_cap_is_config_gated()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Windoffshore"],
        Technology = ["Wind"],
        Node = ["Offshore", "Onshore"],
        OffshoreNode = ["Offshore"],
        DirectionalLink = [("Offshore", "Onshore"), ("Onshore", "Offshore")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [
            ("Offshore", "Onshore", "HVDC"),
            ("Onshore", "Offshore", "HVDC"),
        ],
        GeneratorsOfTechnology = [("Wind", "Windoffshore")],
        GeneratorsOfNode = [("Offshore", "Windoffshore")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))
    params = OpenEMPIRE.EmpireParams()

    emp_off = JuMP.Model()
    OpenEMPIRE.create_variables(emp_off, sets, periods)
    OpenEMPIRE.create_transmission_constraints(emp_off, sets, params, periods; north_sea = false)
    @test !haskey(JuMP.object_dictionary(emp_off), :wind_farm_transmission_cap)

    emp_on = JuMP.Model()
    OpenEMPIRE.create_variables(emp_on, sets, periods)
    OpenEMPIRE.create_transmission_constraints(emp_on, sets, params, periods; north_sea = true)
    @test _sparse_axis_length(emp_on[:wind_farm_transmission_cap]) == 2

    cap = emp_on[:transmissionInstalledCap]["Offshore", "Onshore", sp]
    gen = emp_on[:genInstalledCap]["Offshore", "Windoffshore", sp]
    for arc in (("Offshore", "Onshore"), ("Onshore", "Offshore"))
        constraint = emp_on[:wind_farm_transmission_cap][arc, sp]
        @test JuMP.normalized_coefficient(constraint, cap) == 1.0
        @test JuMP.normalized_coefficient(constraint, gen) == -1.0
    end
end

function test_north_sea_cap_pins_generatorless_offshore_node_to_zero()
    # An offshore node with no generators of its own gives the cap an empty
    # right-hand side, so the corridor is forced to zero capacity. Python does
    # exactly the same, so this documents the behaviour rather than guarding
    # against it -- what the port adds is a warning, because the failure is
    # otherwise silent and disconnects the node.
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Windoffshore"],
        Technology = ["Wind"],
        Node = ["Hub", "Onshore"],
        OffshoreNode = ["Hub"],
        DirectionalLink = [("Hub", "Onshore"), ("Onshore", "Hub")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [
            ("Hub", "Onshore", "HVDC"),
            ("Onshore", "Hub", "HVDC"),
        ],
        GeneratorsOfTechnology = [("Wind", "Windoffshore")],
        GeneratorsOfNode = Tuple{String, String}[],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))
    params = OpenEMPIRE.EmpireParams()

    emp = JuMP.Model()
    OpenEMPIRE.create_variables(emp, sets, periods)
    @test_logs (:warn,) match_mode = :any OpenEMPIRE.create_transmission_constraints(
        emp, sets, params, periods; north_sea = true,
    )

    cap = emp[:transmissionInstalledCap]["Hub", "Onshore", sp]
    for arc in (("Hub", "Onshore"), ("Onshore", "Hub"))
        constraint = emp[:wind_farm_transmission_cap][arc, sp]
        @test JuMP.normalized_coefficient(constraint, cap) == 1.0
        @test JuMP.normalized_rhs(constraint) == 0.0
    end
end

function test_emission_constraints_match_python_formulation()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["gas", "wind"],
        Technology = ["thermal", "renewable"],
        Node = ["A"],
        GeneratorsOfNode = [("A", "gas"), ("A", "wind")],
        GeneratorsOfTechnology = [("thermal", "gas"), ("renewable", "wind")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 2, 2, 0, 0, 2)
    sp = first(strat_periods(periods))
    representatives = collect(repr_periods(sp))
    winter_scenarios = collect(opscenarios(first(representatives)))
    winter_scenario_1 = first(winter_scenarios[1])
    winter_scenario_2 = first(winter_scenarios[2])

    params = OpenEMPIRE.EmpireParams(
        CO2cap = StrategicProfile([0.001]),
        genCO2Content = Dict("gas" => 0.2, "wind" => 0.0),
        genEfficiency = Dict(
            "gas" => StrategicProfile([0.5]),
            "wind" => StrategicProfile([1.0]),
        ),
        seasonNames = ["winter", "spring"],
    )

    emp = JuMP.Model()
    OpenEMPIRE.create_variables(emp, sets, periods)
    OpenEMPIRE.create_emission_constraints(emp, sets, params, periods)

    emission_cap_1 = emp[:emission_cap][sp, 1]
    node_emission_1 = emp[:node_emission]["A", sp, 1]
    node_emission_2 = emp[:node_emission]["A", sp, 2]
    gas_coefficient = multiple_strat(sp, winter_scenario_1) * 0.2 * (3.6 / 0.5)

    @test JuMP.normalized_coefficient(
        emission_cap_1,
        emp[:nodeEmission]["A", sp, 1],
    ) == 1.0
    @test JuMP.normalized_coefficient(
        node_emission_1,
        emp[:nodeEmission]["A", sp, 1],
    ) == 1.0
    @test JuMP.normalized_coefficient(
        node_emission_1,
        emp[:genOperational]["A", "gas", winter_scenario_1],
    ) ≈ -gas_coefficient
    @test JuMP.normalized_coefficient(
        node_emission_1,
        emp[:genOperational]["A", "wind", winter_scenario_1],
    ) == 0.0
    @test JuMP.normalized_coefficient(
        node_emission_1,
        emp[:genOperational]["A", "gas", winter_scenario_2],
    ) == 0.0
    @test JuMP.normalized_coefficient(
        node_emission_2,
        emp[:genOperational]["A", "gas", winter_scenario_2],
    ) ≈ -gas_coefficient
    @test JuMP.normalized_rhs(emission_cap_1) ≈ 1000.0
end

function test_objective_matches_component_sum()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["gas"],
        Storage = ["Battery"],
        DependentStorage = ["Battery"],
        Node = ["A", "B"],
        GeneratorsOfNode = [("A", "gas")],
        StoragesOfNode = [("A", "Battery")],
        DirectionalLink = [("A", "B")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    discounter = Discounter(0.05, 1, periods)
    params = OpenEMPIRE.EmpireParams()

    emp = JuMP.Model()
    OpenEMPIRE.create_variables(emp, sets, periods)
    objective = OpenEMPIRE.create_objective(emp, sets, params, periods, discounter)

    components = OpenEMPIRE.objective_component_expressions(emp, sets, params, periods, discounter)

    # Regression guard: the objective must be exactly the sum of the reported
    # components, so a future edit can't add a cost term to one without the
    # other and silently reintroduce the duplication this refactor removed.
    @test JuMP.isequal_canonical(objective, sum(values(components)))
    @test JuMP.isequal_canonical(JuMP.objective_function(emp), sum(values(components)))
end

function test_native_dual_weight_normalization()
    periods = OpenEMPIRE.create_timestruct(2, 5, 1, 2, 0, 0, 2)
    sp = collect(strat_periods(periods))[2]
    t = first(first(opscenarios(first(repr_periods(sp)))))
    discounter = Discounter(0.05, 1, periods)
    operational_weight = objective_weight(t, discounter; type = "avg_year")
    strategic_weight = objective_weight(sp, discounter)

    flow_model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(flow_model)
    @variable(flow_model, flow >= 0)
    @constraint(flow_model, flow_balance[n in ["A"], time in [t]], flow >= 1)
    @objective(flow_model, Min, operational_weight * flow)
    optimize!(flow_model)

    @test JuMP.is_solved_and_feasible(flow_model)
    @test OpenEMPIRE._flow_balance_price(flow_model, "A", sp, t, discounter) ≈
          strategic_weight

    params = OpenEMPIRE.EmpireParams(CO2cap = StrategicProfile([1.0, 1.0]))
    annual_multiple = multiple_strat(sp, t)
    emission_model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(emission_model)
    @variable(emission_model, generation >= 0)
    @constraint(
        emission_model,
        emission_cap[strategic_period in [sp], scenario in 1:1],
        annual_multiple * generation <= annual_multiple,
    )
    @objective(emission_model, Min, -operational_weight * generation)
    optimize!(emission_model)

    @test JuMP.is_solved_and_feasible(emission_model)
    @test OpenEMPIRE._emission_price(
        emission_model,
        params,
        sp,
        1,
        t,
        discounter,
    ) ≈ -strategic_weight
end

function test_create_model_respects_emission_cap_config()
    mktempdir() do root
        dataset = joinpath(root, "test")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), dataset)

        base_config = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "data", "test_excel", "testrun.yaml"))

        false_config = joinpath(root, "emission_cap_false.yaml")
        base_config["use_emission_cap"] = false
        YAML.write_file(false_config, base_config)
        emp_false, _, _, params_false = OpenEMPIRE.create_model(
            false_config,
            dataset;
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        @test params_false.CO2cap === nothing
        @test params_false.CO2price !== nothing
        @test !haskey(JuMP.object_dictionary(emp_false), :emission_cap)

        true_config = joinpath(root, "emission_cap_true.yaml")
        base_config["use_emission_cap"] = true
        YAML.write_file(true_config, base_config)
        emp_true, periods, _, params_true = OpenEMPIRE.create_model(
            true_config,
            dataset;
            input_format = :csv,
            scenario_rng = MersenneTwister(1),
        )

        @test params_true.CO2cap !== nothing
        @test params_true.CO2price === nothing
        @test haskey(JuMP.object_dictionary(emp_true), :emission_cap)
        expected = length(strat_periods(periods)) * base_config["number_of_scenarios"]
        @test _sparse_axis_length(emp_true[:emission_cap]) == expected
    end
end
