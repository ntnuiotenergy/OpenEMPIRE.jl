function create_model(config_file, data_folder; optimizer = nothing)

    config = YAML.load_file(config_file)

    # Time structure information
    horizon = config["forecast_horizon_year"]
    sp_dur_years = config["leap_years_investment"]
    strat_pers = round(Int, (horizon - 2020) / sp_dur_years)

    season_for_hour = Dict{Int, Int}()

    seasons = 4
    hours_reg_season = config["length_of_regular_season"]
    for s in 1:seasons
        start_hour = (s - 1) * hours_reg_season + 1
        end_hour = s * hours_reg_season
        for h in start_hour:end_hour
            season_for_hour[h] = s
        end
    end
    peaks = 2
    hours_peak = 24
    for p in 1:peaks
        start_hour = seasons * hours_reg_season + (p - 1) * hours_peak + 1
        end_hour = seasons * hours_reg_season + p * hours_peak
        for h in start_hour:end_hour
            season_for_hour[h] = seasons + p
        end
    end
    scenarios = config["number_of_scenarios"]

    periods = OpenEMPIRE.create_timestruct(strat_pers, sp_dur_years, seasons, hours_reg_season, peaks, hours_peak, scenarios)


    sets = OpenEMPIRE.read_sets_xlsx(data_folder)
    params = OpenEMPIRE.read_params_xlsx(data_folder)
    OpenEMPIRE.read_scenario_tab(data_folder, periods, params, season_for_hour)

    # Financial parameters
    params.WACC = config["wacc"]
    params.discountRate = config["discount_rate"]

    OpenEMPIRE.preprocess_params(params, sets, periods)

    emp = isnothing(optimizer) ? JuMP.Model() : JuMP.direct_model(optimizer_with_attributes(optimizer))
    OpenEMPIRE.create_variables(emp, sets, periods)
    OpenEMPIRE.create_constraints(emp, sets, params, periods)
    OpenEMPIRE.create_objective(emp, sets, params, periods, Discounter(params.discountRate, 1, periods))

   return emp, periods, sets, params

end
