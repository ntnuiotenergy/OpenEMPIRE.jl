_optimizer_constructor(optimizer) =
    optimizer isa DataType ? (() -> Base.invokelatest(optimizer)) : optimizer

function _optimizer_with_attributes(optimizer, optimizer_attributes)
    return optimizer_with_attributes(_optimizer_constructor(optimizer), optimizer_attributes...)
end

function _config_bool(config, key::AbstractString, default::Bool)::Bool
    value = get(config, key, default)
    value isa Bool && return value
    if value isa AbstractString
        normalized = lowercase(strip(value))
        normalized in ("true", "1", "yes") && return true
        normalized in ("false", "0", "no") && return false
        throw(ArgumentError("Unsupported boolean value for $key: $value"))
    end
    return Bool(value)
end

"""
    _prepare_model_inputs(config_file, data_folder; input_format, scenario_rng, progress)

Run the data-preparation stages shared by `create_model` and `generate_scenarios`
(Build 1-6): read the config, build the time structure, load the dataset, and read
or generate the stochastic scenario data. No JuMP model is constructed here.

Returns `(config, periods, sets, params)`.
"""
function _prepare_model_inputs(
    config_file,
    data_folder;
    input_format = :auto,
    scenario_rng = Random.default_rng(),
    progress = nothing,
)
    _report_progress(progress, "Build 1/12: reading configuration from $config_file")
    config = YAML.load_file(config_file)

    # Time structure information
    _report_progress(progress, "Build 2/12: creating time structure")
    horizon = config["forecast_horizon_year"]
    sp_dur_years = config["leap_years_investment"]
    strat_pers = round(Int, (horizon - 2020) / sp_dur_years)

    season_for_hour = Dict{Int, Int}()

    regular_seasons = OpenEMPIRE.regular_scenario_seasons(config)
    season_count = length(regular_seasons)
    hours_reg_season = config["length_of_regular_season"]
    for season_index in 1:season_count
        start_hour = (season_index - 1) * hours_reg_season + 1
        end_hour = season_index * hours_reg_season
        for h in start_hour:end_hour
            season_for_hour[h] = season_index
        end
    end
    peak_count = OpenEMPIRE.scenario_peak_count(config)
    hours_peak = OpenEMPIRE.scenario_peak_hours(config)
    for peak_index in 1:peak_count
        start_hour = season_count * hours_reg_season + (peak_index - 1) * hours_peak + 1
        end_hour = season_count * hours_reg_season + peak_index * hours_peak
        for h in start_hour:end_hour
            season_for_hour[h] = season_count + peak_index
        end
    end
    weather_scenarios = OpenEMPIRE.weather_scenario_count(config)
    gas_scenarios = OpenEMPIRE.gas_scenario_count(config)
    scenarios = OpenEMPIRE.combined_scenario_count(config)
    operational_hours_per_year = Int(get(config, "operational_hours_per_year", 8760))

    periods = OpenEMPIRE.create_timestruct(
        strat_pers,
        sp_dur_years,
        season_count,
        hours_reg_season,
        peak_count,
        hours_peak,
        scenarios,
        ;
        operational_hours_per_year,
    )


    _report_progress(progress, "Build 3/12: reading input data from $data_folder")
    gas_enabled = OpenEMPIRE.natural_gas_enabled(config)
    sets, params = OpenEMPIRE.read_data(
        data_folder;
        format = input_format,
        natural_gas = gas_enabled,
        weather_scenarios,
        gas_scenarios,
    )
    _report_progress(
        progress,
        "Build 4/12: input data loaded ($(length(nodes(sets))) nodes, $(length(generators(sets))) generators, $(length(storages(sets))) storages)",
    )
    if _config_bool(config, "use_emission_cap", false)
        params.CO2price = nothing
    else
        params.CO2cap = nothing
    end
    params.seasonNames = vcat(collect(regular_seasons), ["peak$(i)" for i in 1:peak_count])
    params.regularSeasonCount = season_count

    _report_progress(progress, "Build 5/12: reading or generating stochastic scenario data")
    OpenEMPIRE.read_scenario_data!(
        OpenEMPIRE.input_path(data_folder),
        periods,
        params,
        sets,
        config,
        season_for_hour;
        rng = scenario_rng,
    )
    _report_progress(progress, "Build 6/12: stochastic scenario data ready")

    return config, periods, sets, params
end

"""
    generate_scenarios(config_file, data_folder; input_format, scenario_rng, progress)

Generate (or load) the stochastic scenario data for `data_folder` **without
building the JuMP model**, then return `(periods, sets, params)`.

This runs the same input-preparation path as [`create_model`] up to and
including the scenario step, so its side effects are identical: when
`use_scenario_generation` is true the raw `ScenarioData/*.csv` files are sampled
and the generated `sloadRaw.csv`, `maxRegHydroGenRaw.csv`,
`genCapAvailStochRaw.csv` (and, unless `use_fixed_sample` is true, a fresh
`sampling_key.csv`) are written into `<data_folder>/ScenarioData`. Use it to
prepare comparable scenario inputs for multi-seed parity runs before paying the
cost of model construction and optimization.
"""
function generate_scenarios(
    config_file,
    data_folder;
    input_format = :auto,
    scenario_rng = Random.default_rng(),
    progress = nothing,
)
    _, periods, sets, params = _prepare_model_inputs(
        config_file,
        data_folder;
        input_format,
        scenario_rng,
        progress,
    )
    return periods, sets, params
end

"""
    create_model(config_file, data_folder; include_investment_constraints = true, ...)

Build an EMPIRE model from configuration and input data. Set
`include_investment_constraints = false` for OOS evaluation after strategic
capacities from a completed investment run will be fixed on the model.
"""
function create_model(
    config_file,
    data_folder;
    optimizer = nothing,
    optimizer_attributes = (),
    include_string_names = true,
    include_investment_constraints::Bool = true,
    input_format = :auto,
    scenario_rng = Random.default_rng(),
    progress = nothing,
)
    config, periods, sets, params = _prepare_model_inputs(
        config_file,
        data_folder;
        input_format,
        scenario_rng,
        progress,
    )

    # Financial parameters
    params.WACC = config["wacc"]
    params.discountRate = config["discount_rate"]

    _report_progress(progress, "Build 7/12: preprocessing parameters")
    gas_enabled = OpenEMPIRE.natural_gas_enabled(config)
    OpenEMPIRE.preprocess_params(params, sets, periods; natural_gas = gas_enabled)

    _report_progress(progress, "Build 8/12: validating parameters")
    OpenEMPIRE.validate(params; sets, periods, strict = false)
    if gas_enabled
        gas_issues = OpenEMPIRE.validate_natural_gas(params, sets, periods)
        isempty(gas_issues) || throw(ArgumentError(
            "Natural-gas input validation found $(length(gas_issues)) issue(s):\n  - " *
            join(gas_issues, "\n  - "),
        ))
    end

    _report_progress(progress, "Build 9/12: initializing JuMP model")
    emp = if isnothing(optimizer)
        JuMP.Model()
    else
        JuMP.direct_model(_optimizer_with_attributes(optimizer, optimizer_attributes))
    end
    set_string_names_on_creation(emp, include_string_names)
    _report_progress(progress, "Build 10/12: creating variables")
    @time OpenEMPIRE.create_variables(
        emp,
        sets,
        periods;
        natural_gas = gas_enabled,
        progress,
    )
    _report_progress(progress, "Build 11/12: creating constraints")
    @time OpenEMPIRE.create_constraints(
        emp,
        sets,
        params,
        periods;
        north_sea = _config_bool(config, "north_sea", false),
        natural_gas = gas_enabled,
        include_investment_constraints,
        progress,
    )
    _report_progress(progress, "Build 12/12: creating objective")
    @time OpenEMPIRE.create_objective(
        emp,
        sets,
        params,
        periods,
        Discounter(OpenEMPIRE.discount_rate(params), 1, periods);
        natural_gas = gas_enabled,
        progress,
    )
    _report_progress(progress, "Model build complete")

    return emp, periods, sets, params

end
