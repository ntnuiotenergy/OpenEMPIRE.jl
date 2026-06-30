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

function _scenario_time_rows()
    starts = DateTime[
        DateTime(2020, 1, 1),
        DateTime(2020, 4, 1),
        DateTime(2020, 7, 1),
        DateTime(2020, 10, 1),
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

        config = Dict(
            "use_scenario_generation" => true,
            "use_fixed_sample" => false,
            "number_of_scenarios" => 1,
            "length_of_regular_season" => 24,
            "regular_seasons" => ["winter"],
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

        metadata = YAML.load_file(joinpath(result_dir, "Input", "scenario_metadata.yaml"))
        @test metadata["dataset"] == "dataset"
        @test metadata["seed"] == 11
        @test metadata["input_format"] == "csv"
        @test metadata["use_scenario_generation"] == true
        @test metadata["use_fixed_sample"] == false
        @test metadata["archived_sampling_key"] == joinpath("Input", "ScenarioData", "sampling_key.csv")
        @test metadata["generated_scenario_files_present"]["sloadRaw.csv"] == true

        disabled_result = joinpath(root, "disabled")
        disabled_config = merge(config, Dict("use_scenario_generation" => false))
        @test OpenEMPIRE.write_scenario_artifacts(disabled_result, dataset, disabled_config) === nothing
        @test !ispath(joinpath(disabled_result, "Input", "ScenarioData", "sampling_key.csv"))
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
