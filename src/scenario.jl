
function scenario_id(sc)
    m = match(r"\d+$", sc)
    if m !== nothing
        value = parse(Int, m.match)
        return value
    end
    return nothing
end

function read_scenario_tab(data_folder, periods, params::EmpireParams, hours_per_season::Dict{Int, Vector{Int}})
    @info "Reading scenario data"

    params.sloadRaw = Dict{String, TimeProfile}()
    params.maxRegHydroGenRaw = Dict{String, TimeProfile}()

    el_file = joinpath(data_folder, "Stochastic", "Stochastic_ElectricLoadRaw.tab")
    hydro_file = joinpath(data_folder, "Stochastic", "Stochastic_HydroGenMaxSeasonalProduction.tab")

    read_scenario_data(el_file, params.sloadRaw, periods, hours_per_season, 5)
    read_scenario_data(hydro_file, params.maxRegHydroGenRaw, periods, hours_per_season, 6)

    avail_file = joinpath(data_folder, "Stochastic", "Stochastic_StochasticAvailability.tab")
    params.genCapAvail = Dict{Tuple{String,String}, TimeProfile}()
    read_scenario_data_gen(avail_file, params.genCapAvail, periods, hours_per_season, 6)

end

function read_scenario_data(file, node_val::Dict{String, TimeProfile}, periods, hours_per_season::Dict{Int, Vector{Int}}, value_col)

    # Read the scenario data from tab files
    sc_data = CSV.File(file; delim='\t')

    nodes = unique(String(r[1]) for r in sc_data)
    for n in nodes
        repr_profiles = RepresentativeProfile[]
        for (i, sp) in enumerate(strat_periods(periods))
            scen_profiles = ScenarioProfile[]
            for (j, rp) in enumerate(repr_periods(sp))
                op_profiles = OperationalProfile[]
                for (k, sc) in enumerate(opscenarios(rp))
                    op_data = filter(r -> r.Node == n && r.Period == i && scenario_id(r.Scenario) == k, sc_data)
                    sort!(op_data, by = r -> r.Operationalhour)
                    vals = [r[value_col] for r in op_data if r.Operationalhour in hours_per_season[j]]
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
    hours_per_season::Dict{Int, Vector{Int}},
    value_col::Int
)

    # Read the scenario data from tab files
    sc_data = CSV.File(file; delim='\t')

    nodes = unique(String(r[1]) for r in sc_data)
    gens = unique(String(r[2]) for r in sc_data)
    for n in nodes
        for g in gens
            repr_profiles = RepresentativeProfile[]
            for (i, sp) in enumerate(strat_periods(periods))
                scen_profiles = ScenarioProfile[]
                for (j, rp) in enumerate(repr_periods(sp))
                    op_profiles = OperationalProfile[]
                    for (k, sc) in enumerate(opscenarios(rp))
                        op_data = filter(r -> r.Node == n  && r.IntermitentGenerators == g && r.Period == i && scenario_id(r.Scenario) == k, sc_data)
                        sort!(op_data, by = r -> r.Operationalhour)
                        vals = [r[value_col] for r in op_data if r.Operationalhour in hours_per_season[j]]
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
end
