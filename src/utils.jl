
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

function preprocess_invest_cost(params::EmpireParams, sets, periods)

    @info "Preprocessing investment costs based on WACC and discount rate"

    # Calculate investment costs per strategic period based on annuity and present value
    wacc = params.WACC
    ρ = params.discountRate

    SP = strat_periods(periods)

    # Generator investment costs
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
    for tr in sets.TransmissionType
        if haskey(params.transmissionTypeCapitalCost, tr) && haskey(params.transmissionLifetime, tr)
            cap_cost = params.transmissionTypeCapitalCost[tr] # in €/kW
            life = params.transmissionLifetime[tr]
            om_cost = get(params.transmissionTypeFixedOMCost, tr, 0.0) # in €/kW/year
            profiles = FixedProfile[]
            for sp in SP
                cost_per_year = cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                invest_cost = present_value(cost_per_year * 1000, ρ, y; at_start = true) # in €/MW
                push!(profiles, FixedProfile(invest_cost))
            end
            params.transmissionInvCost[tr] = StrategicProfile(profiles)
        end
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
            # Convert fuel cost from €/GJ to €/MWh and add variable O&M cost and CO2 cost
            cost_per_energy = (3.6 / params.genEfficiency[g][sp]) * params.genFuelCost[g][sp] +
                params.CO2price[sp] * params.genCO2Content[g] + get(params.genVariableOMCost, g, 0.0) # in €/MWh
            push!(values, cost_per_energy)
        end
        params.genMargCost[g] = StrategicProfile(values)
    end
end

function preprocess_initcap(params::EmpireParams, sets, periods)
    for g in sets.Generator
        values = Float64[]
        for sp in strat_periods(periods)
            if !haskey(params.genInitCap, g) || params.genInitCap[g][sp] == 0
                val = params.genRefInitCap[g] * (1 - params.genScaleInitCap[sp])
            else
                val = params.genInitCap[g][sp]
            end
            push!(values, val)
        end
        params.genInitCap[g] = StrategicProfile(values)
    end
end
