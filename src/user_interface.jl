function create_model(config_file, data_folder)

    config = YAML.load_file(config_file)

    # Time structure information
    horizon = config["forecast_horizon_year"]
    sp_dur_years = config["leap_years_investment"]
    strat_pers = round(Int, (horizon - 2020) / sp_dur_years)

    hours_per_season = Dict{Int, Vector{Int}}()

    seasons = 4
    hours_reg_season = config["length_of_regular_season"]
    for s in 1:seasons
        start_hour = (s - 1) * hours_reg_season + 1
        end_hour = s * hours_reg_season
        hours_per_season[s] = collect(start_hour:end_hour)
    end
    peaks = 2
    hours_peak = 24
    for p in 1:peaks
        start_hour = seasons * hours_reg_season + (p - 1) * hours_peak + 1
        end_hour = seasons * hours_reg_season + p * hours_peak
        hours_per_season[seasons + p] = collect(start_hour:end_hour)
    end
    scenarios = config["number_of_scenarios"]


    periods = OpenEMPIRE.create_timestruct(strat_pers, sp_dur_years, seasons, hours_reg_season, peaks, hours_peak, scenarios)

    sets = OpenEMPIRE.read_sets_xlsx(data_folder)
    params = OpenEMPIRE.read_params_xlsx(data_folder)
    OpenEMPIRE.read_scenario_tab(data_folder, periods, params, hours_per_season)

    emp = JuMP.Model()
    OpenEMPIRE.create_variables(emp, sets, periods)
    OpenEMPIRE.create_constraints(emp, sets, params, periods)

   return emp

end
