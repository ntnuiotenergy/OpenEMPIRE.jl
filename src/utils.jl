
function annuity_factor(wacc, life)
    return (1 - (1 + wacc)^(-life)) / wacc
end

function present_value(cost, discount_rate, years; at_start = true)
    ρ = discount_rate
    pv = cost * (1 - (1 + ρ)^(-years)) / ρ
    if at_start
        pv *= (1 + ρ)
    end
    return pv
end

function preprocess_params(params::EmpireParams, sets, periods)
    preprocess_invest_cost(params, sets, periods)
    preprocess_operational_cost(params, sets, periods)
    preprocess_initcap_gen(params, sets, periods)
    preprocess_stoch_load(params, sets, periods)
    preprocess_max_installed_cap(params, sets, periods)
    preprocess_hydro_gen(params, sets, periods)
end

function preprocess_invest_cost(params::EmpireParams, sets, periods)

    @info "Preprocessing investment costs based on WACC and discount rate"

    # Calculate investment costs per strategic period based on annuity and present value
    wacc = params.WACC
    ρ = params.discountRate

    SP = strat_periods(periods)

    # Generator investment costs

    # TODO: avoid hardcoding of ccs data
    ccs_cost_fix = 1149873.72
    ccs_rem_frac = 0.9

    params.genInvCost = Dict{String, StrategicProfile}()
    for g in sets.Generator
        if haskey(params.genCapitalCost, g) && haskey(params.genLifetime, g)
            cap_cost = params.genCapitalCost[g] # in €/kW
            life = gen_lifetime(params, g)
            om_cost = get(params.genFixedOMCost, g, 0.0) # in €/kW/year
            inv_cost = Float64[]
            for sp in SP
                # Cost for each year of its lifetime using annuity factor
                cost_per_year = cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]

                # Number of years the investment is active in the planning periods
                # considering the lifetime of the asset
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                # Calculate the total investment cost in €/MW when investing in this strategic period
                # assuming investments are made at the start of the strategic period
                tot_invest_cost = present_value(cost_per_year * 1000, ρ, y; at_start = true) # in €/MW

                if ("CCS", g) in sets.GeneratorsOfTechnology
                    tot_invest_cost += ccs_cost_fix * ccs_rem_frac * params.genCO2Content[g] * (3.6 / params.genEfficiency[g][sp])
                end

                push!(inv_cost, tot_invest_cost)
            end
            params.genInvCost[g] = StrategicProfile(inv_cost)
        end
    end

    # Storage energy capacity investment costs
    params.storENInvCost = Dict{String, StrategicProfile}()
    for s in sets.Storage
        if haskey(params.storENCapitalCost, s) && haskey(params.storageLifetime, s)
            cap_cost = params.storENCapitalCost[s] # in €/kWh
            life = lifetime_storage(params, s)
            om_cost = get(params.storENFixedOMCost, s, 0.0) # in €/kWh/year
            profiles = FixedProfile[]
            for sp in SP
                cost_per_year = cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                invest_cost = present_value(cost_per_year * 1000, ρ, y; at_start = true) # in €/MW
                push!(profiles, FixedProfile(invest_cost))
            end
            params.storENInvCost[s] = StrategicProfile(profiles)
        end
    end

    # Storage power capacity investment costs
    params.storPWInvCost = Dict{String, StrategicProfile}()
    for s in sets.Storage
        if haskey(params.storPWCapitalCost, s) && haskey(params.storageLifetime, s)
            cap_cost = params.storPWCapitalCost[s] # in €/kW
            life = lifetime_storage(params, s)
            om_cost = get(params.storPWFixedOMCost, s, 0.0) # in €/kW/year
            profiles = FixedProfile[]
            for sp in SP
                cost_per_year = cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                invest_cost = present_value(cost_per_year * 1000, ρ, y; at_start = true) # in €/MW
                push!(profiles, FixedProfile(invest_cost))
            end
            params.storPWInvCost[s] = StrategicProfile(profiles)
        end
    end

    # Transmission investment costs
    params.transmissionInvCost = Dict{Tuple{String,String}, StrategicProfile}()
    for (m, n, tt) in sets.TransmissionTypeOfDirectionalLink
        if haskey(params.transmissionTypeCapitalCost, tt) && haskey(params.transmissionLifetime, (m,n))
            cap_cost = params.transmissionTypeCapitalCost[tt] # in €/kW
            life = params.transmissionLifetime[(m,n)]
            om_cost = get(params.transmissionTypeFixedOMCost, tt, 0.0) # in €/kW/year
            profiles = FixedProfile[]
            for sp in SP
                cost_per_year = cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                invest_cost = present_value(cost_per_year * 1000, ρ, y; at_start = true) # in €/MW
                push!(profiles, FixedProfile(invest_cost))
            end
            params.transmissionInvCost[(m, n)] = StrategicProfile(profiles)
        end
    end
end

function preprocess_max_installed_cap(params::EmpireParams, sets, periods)
    # Ensure that the maximum installed capacity is at least equal to the initial capacity

    # Generators of technology
    params.genMaxInstalledCap = Dict{Tuple{String,String}, TimeProfile}()
    for (n, gt) in keys(params.genMaxInstalledCapRaw)
        vals = Float64[]
        for sp in strat_periods(periods)
            max_cap = params.genMaxInstalledCapRaw[(n, gt)]
            init_cap = sum(gencap_init(params, n, g, sp) for g in generators_tech(sets, n, gt); init = 0)
            if init_cap > max_cap
                @warn "Initial capacity $init_cap for technology $gt at node $n exceeds maximum installed capacity $max_cap. Setting maximum installed capacity to initial capacity."
                max_cap = init_cap
            end
            push!(vals, max_cap)
        end
        params.genMaxInstalledCap[(n, gt)] = StrategicProfile(vals)
    end

    # Transmission lines
    for (m, n) in keys(params.transmissionMaxInstalledCap)
        vals = Float64[]
        for sp in strat_periods(periods)
            max_cap = params.transmissionMaxInstalledCap[(m, n)][sp]
            init_cap = trans_cap_init(params, m, n, sp)
            if init_cap > max_cap
                @warn "Initial capacity $init_cap for transmission line $((m, n)) exceeds maximum installed capacity $max_cap. Setting maximum installed capacity to initial capacity."
                max_cap = init_cap
            end
            push!(vals, max_cap)
        end
        params.transmissionMaxInstalledCap[(m, n)] = StrategicProfile(vals)
    end
end

# Find the marginal cost of generation for each generator and strategic period
# including fuel cost, variable O&M cost and CO2 cost
function preprocess_operational_cost(params::EmpireParams, sets, periods)
    params.genMargCost = Dict{String, StrategicProfile}()
    for g in sets.Generator
        values = Float64[]
        for sp in strat_periods(periods)
            # Variable cost in €/MWh
            if !haskey(params.genFuelCost, g) || !haskey(params.genEfficiency, g)
                continue
            end

            ccs_remove_frac = 0.9

            if ("CCS", g) in sets.GeneratorsOfTechnology
                carbon_cost = (1 - ccs_remove_frac) * params.CO2price[sp] * params.genCO2Content[g] +
                 ccs_remove_frac * params.genCO2Content[g] * params.CCSCostTSVariable[sp]
            else
                carbon_cost = params.CO2price[sp] * params.genCO2Content[g]
            end

            # Convert fuel cost from €/GJ to €/MWh and add variable O&M cost and CO2 cost
            cost_per_energy = (3.6 / params.genEfficiency[g][sp]) * (params.genFuelCost[g][sp] +
                carbon_cost) + get(params.genVariableOMCost, g, 0.0) # in €/MWh

            push!(values, cost_per_energy)
        end
        params.genMargCost[g] = StrategicProfile(values)
    end
end

function preprocess_initcap_gen(params::EmpireParams, sets, periods)
    @info "Preprocessing initial generation capacities"
    for (n, g) in sets.GeneratorsOfNode
        values = Float64[]
        for sp in strat_periods(periods)
            val = 0.0
            # If no initial capacity is provided or equal to 0, use reference capacity
            # scaled by reduction factor if available
            if !haskey(params.genInitCap, (n, g)) || params.genInitCap[(n, g)][sp] == 0
                if haskey(params.genRefInitCap, (n, g)) && haskey(params.genScaleInitCap, g)
                    val = params.genRefInitCap[(n, g)] * (1 - params.genScaleInitCap[g][sp])
                end
            else
                val = params.genInitCap[(n, g)][sp]
            end
            push!(values, val)
        end
        params.genInitCap[(n, g)] = StrategicProfile(values)
    end
end

function preprocess_stoch_load(params::EmpireParams, sets, periods)
    @info "Preprocessing stochastic load profiles based on annual demand"
    # Scale the stochastic load profiles based on the expected annual load
    params.sload = Dict{String, TimeProfile}()
    for n in sets.Node
        if !haskey(params.sloadRaw, n)
            continue
        end
        repr_profiles = RepresentativeProfile[]
        for sp in strat_periods(periods)
            load_raw = sum(multiple_strat(sp, t) * probability(t) * params.sloadRaw[n][t] for t in sp)
            scale_factor = 0.0
            if haskey(params.sloadAnnualDemand, n)
                scale_factor = params.sloadAnnualDemand[n][sp] / load_raw
            end
            scen_profiles = ScenarioProfile[]
            for rp in repr_periods(sp)
                op_profiles = OperationalProfile[]
                for sc in opscenarios(rp)
                    scaled_vals = [params.sloadRaw[n][t] * scale_factor for t in sc]
                    push!(op_profiles, OperationalProfile(scaled_vals))
                end
                push!(scen_profiles, ScenarioProfile(op_profiles))
            end
            push!(repr_profiles, RepresentativeProfile(scen_profiles))
        end
        params.sload[n] = StrategicProfile(repr_profiles)
    end
end

function preprocess_hydro_gen(params::EmpireParams, sets, periods)
    @info "Preprocessing stochastic hydro generation profiles"
    # Aggregate the hydro generation profiles for each node and operational scenario
    params.maxRegHydroGen = Dict{String, TimeProfile}()
    for n in sets.Node
        if !haskey(params.maxRegHydroGenRaw, n)
            continue
        end
        profiles = FixedProfile[]
        for sc in opscenarios(periods)
            val = sum(params.maxRegHydroGenRaw[n][t] for t in sc)
            push!(profiles, FixedProfile(val))
        end
        params.maxRegHydroGen[n] = ScenarioProfile(profiles)
    end
end
