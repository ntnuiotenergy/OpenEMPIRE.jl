
function scenario_id(sc)
    m = match(r"\d+$", sc)
    if m !== nothing
        value = parse(Int, m.match)
        return value
    end
    return nothing
end

function read_scenario_tab(data_folder, periods, params::EmpireParams, season_for_hour::Dict{Int, Int})

    params.sloadRaw = Dict{String, TimeProfile}()
    params.maxRegHydroGenRaw = Dict{String, TimeProfile}()

    el_file = joinpath(data_folder, "ScenarioData", "Stochastic_ElectricLoadRaw.tab")
    hydro_file = joinpath(data_folder, "ScenarioData", "Stochastic_HydroGenMaxSeasonalProduction.tab")
    avail_file = joinpath(data_folder, "ScenarioData", "Stochastic_StochasticAvailability.tab")

    missing_files = filter(!isfile, [el_file, hydro_file, avail_file])
    if !isempty(missing_files)
        throw(ArgumentError(
            "Generated stochastic .tab scenario files are required by the Julia model. " *
            "Raw ScenarioData CSV files must first be converted/generated. Missing files: " *
            join(missing_files, ", ")
        ))
    end

    read_scenario_data(el_file, params.sloadRaw, periods, season_for_hour, 5)
    read_scenario_data(hydro_file, params.maxRegHydroGenRaw, periods, season_for_hour, 6)

    params.genCapAvail = Dict{Tuple{String,String}, TimeProfile}()
    read_scenario_data_gen(avail_file, params.genCapAvail, periods, season_for_hour, 6)

end

function read_scenario_data(file, node_val::Dict{String, TimeProfile}, periods, season_for_hour::Dict{Int, Int}, value_col)

    @info "Reading scenario data from $file"

    # Read the scenario data from tab files
    sc_data = CSV.File(file; delim='\t')

    nodes = unique(String(r[1]) for r in sc_data)

    profiles = Dict{Tuple{String,Int,Int,Int}, Vector{Float64}}()

    for n in nodes
        for (i, sp) in enumerate(strat_periods(periods))
            for (j, rp) in enumerate(repr_periods(sp))
                for (k, sc) in enumerate(opscenarios(rp))
                    profiles[(n, i, j, k)] = Float64[]
                end
            end
        end
    end

    for r in sc_data
        n = String(r[1])
        sp = r.Period
        rp = season_for_hour[r.Operationalhour]
        sc = OpenEMPIRE.scenario_id(r.Scenario)
        push!(profiles[(n, sp, rp, sc)], r[value_col])
    end

    for n in nodes
        repr_profiles = RepresentativeProfile[]
        for (i, sp) in enumerate(strat_periods(periods))
            scen_profiles = ScenarioProfile[]
            for (j, rp) in enumerate(repr_periods(sp))
                op_profiles = OperationalProfile[]
                for (k, sc) in enumerate(opscenarios(rp))
                    vals = profiles[(n, i, j, k)]
                    push!(op_profiles, OperationalProfile(vals))
                end
                push!(scen_profiles, ScenarioProfile(op_profiles))
            end
            push!(repr_profiles, RepresentativeProfile(scen_profiles))
        end
        profile = StrategicProfile(repr_profiles)
        node_val[String(n)] = profile
    end
end

function read_scenario_data_gen(
    file,
    node_gen_val::Dict{Tuple{String,String}, TimeProfile},
    periods::TimeStructure,
    season_for_hour::Dict{Int, Int},
    value_col::Int
)
    @info "Reading scenario data from $file"

    # Read the scenario data from tab files
    sc_data = CSV.File(file; delim='\t')

    node_gens = unique((String(r[1]), String(r[2])) for r in sc_data)

    profiles = Dict{Tuple{String,String,Int,Int,Int}, Vector{Float64}}()

    for (n,g) in node_gens
        for (i, sp) in enumerate(strat_periods(periods))
            for (j, rp) in enumerate(repr_periods(sp))
                for (k, sc) in enumerate(opscenarios(rp))
                    profiles[(n, g, i, j, k)] = Float64[]
                end
            end
        end
    end

    for r in sc_data
        n = String(r[1])
        g = String(r[2])
        sp = r.Period
        rp = season_for_hour[r.Operationalhour]
        sc = OpenEMPIRE.scenario_id(r.Scenario)
        push!(profiles[(n, g, sp, rp, sc)], r[value_col])
    end

    for (n, g) in node_gens
        repr_profiles = RepresentativeProfile[]
        for (i, sp) in enumerate(strat_periods(periods))
            scen_profiles = ScenarioProfile[]
            for (j, rp) in enumerate(repr_periods(sp))
                op_profiles = OperationalProfile[]
                for (k, sc) in enumerate(opscenarios(rp))
                    vals = profiles[(n, g, i, j, k)]
                    push!(op_profiles, OperationalProfile(vals))
                end
                push!(scen_profiles, ScenarioProfile(op_profiles))
            end
            push!(repr_profiles, RepresentativeProfile(scen_profiles))
        end
        profile = StrategicProfile(repr_profiles)
        node_gen_val[(String(n), String(g))] = profile
    end
end
