_optimizer_constructor(optimizer) =
    optimizer isa DataType ? (() -> Base.invokelatest(optimizer)) : optimizer

function create_model(
    config_file,
    data_folder;
    optimizer = nothing,
    include_string_names = true,
    input_format = :auto,
    scenario_rng = Random.default_rng(),
)

    config = YAML.load_file(config_file)

    # Time structure information
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
    scenarios = config["number_of_scenarios"]

    periods = OpenEMPIRE.create_timestruct(
        strat_pers,
        sp_dur_years,
        season_count,
        hours_reg_season,
        peak_count,
        hours_peak,
        scenarios,
    )


    sets, params = OpenEMPIRE.read_data(data_folder; format = input_format)
    params.seasonNames = vcat(collect(regular_seasons), ["peak$(i)" for i in 1:peak_count])
    params.regularSeasonCount = season_count

    OpenEMPIRE.read_scenario_data!(
        OpenEMPIRE.input_path(data_folder),
        periods,
        params,
        sets,
        config,
        season_for_hour;
        rng = scenario_rng,
    )

    # Financial parameters
    params.WACC = config["wacc"]
    params.discountRate = config["discount_rate"]

    OpenEMPIRE.preprocess_params(params, sets, periods)

    OpenEMPIRE.validate(params; sets, periods, strict = false)

    emp = if isnothing(optimizer)
        JuMP.Model()
    else
        JuMP.direct_model(optimizer_with_attributes(_optimizer_constructor(optimizer)))
    end
    set_string_names_on_creation(emp, include_string_names)
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @time OpenEMPIRE.create_constraints(emp, sets, params, periods)
    @time OpenEMPIRE.create_objective(emp, sets, params, periods, Discounter(OpenEMPIRE.discount_rate(params), 1, periods))

    return emp, periods, sets, params

end
