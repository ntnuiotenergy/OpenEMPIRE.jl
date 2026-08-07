
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
    wacc = OpenEMPIRE.wacc(params)
    ρ = OpenEMPIRE.discount_rate(params)

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
            cap_cost = params.transmissionTypeCapitalCost[tt] # in €/(MW * km)
            life = params.transmissionLifetime[(m,n)]
            trans_length = params.transmissionLength[(m,n)] # in km
            om_cost = get(params.transmissionTypeFixedOMCost, tt, 0.0) # in €/MW/year
            profiles = FixedProfile[]
            for sp in SP
                cost_per_year = trans_length * cap_cost[sp] / annuity_factor(wacc, life) + om_cost[sp]
                y = min(life, sum(duration_strat(spp) for spp in SP if spp >= sp))
                invest_cost = present_value(cost_per_year, ρ, y; at_start = true) # in €/MW
                push!(profiles, FixedProfile(invest_cost))
            end
            params.transmissionInvCost[(m, n)] = StrategicProfile(profiles)
        end
    end
end

function preprocess_max_installed_cap(params::EmpireParams, sets, periods)
    # Ensure that the maximum installed capacity is at least equal to the initial capacity

    # Generators of technology. Python builds this parameter over the full
    # Node × Technology × Period product, using a raw default of zero.
    params.genMaxInstalledCap = Dict{Tuple{String,String}, TimeProfile}()
    for n in nodes(sets), gt in techs(sets)
        vals = Float64[]
        for sp in strat_periods(periods)
            max_cap = get(params.genMaxInstalledCapRaw, (n, gt), DEFAULT_GEN_MAX_INST_CAP_RAW)
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
        # Without an efficiency profile there is no marginal-cost basis, so the
        # generator keeps the documented accessor fallback. Never fall through to
        # an empty StrategicProfile: validation and model evaluation index it and
        # fail with an opaque BoundsError.
        haskey(params.genEfficiency, g) || continue

        # A generator with an efficiency but no fuel price cannot be costed here.
        # `full_model_int` is the motivating case: it deliberately omits gas fuel
        # prices because InternalEMPIRE prices gas through its natural-gas module,
        # so that dataset needs the gas module rather than a silent zero cost.
        haskey(params.genFuelCost, g) || throw(ArgumentError(
            "Generator $g has a genEfficiency profile but no genFuelCost entry. " *
            "Add its fuel cost, or use a dataset whose fuels are all priced in " *
            "genFuelCost.",
        ))

        values = Float64[]
        for sp in strat_periods(periods)
            # Variable cost in €/MWh
            ccs_remove_frac = 0.9

            if ("CCS", g) in sets.GeneratorsOfTechnology
                carbon_cost = (1 - ccs_remove_frac) * co2_price(params, sp) * co2_content(params, g) +
                 ccs_remove_frac * co2_content(params, g) * ccs_cost_variable(params, sp)
            else
                carbon_cost = co2_price(params, sp) * co2_content(params, g)
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
                if haskey(params.genRefInitCap, (n, g))
                    scale = haskey(params.genScaleInitCap, g) ? params.genScaleInitCap[g][sp] : 0.0
                    val = params.genRefInitCap[(n, g)] * (1 - scale)
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
            representatives = collect(repr_periods(sp))
            # Match Python (empire.py): the annual-demand normalization denominator is summed
            # over REGULAR seasons only. Peak seasons are excluded here (the resulting factor
            # is still applied to peak hours below). Including peaks would inflate the
            # denominator and scale every load down (~0.7% on europe_v51), because peak hours
            # carry above-average demand.
            regular_count = regular_season_count(params, length(representatives))
            regular_reps = representatives[1:regular_count]
            load_raw = sum(
                multiple_strat(sp, t) * probability(t) * params.sloadRaw[n][t]
                for rp in regular_reps
                for sc in opscenarios(rp)
                for t in sc
            )
            scale_factor = 0.0
            if haskey(params.sloadAnnualDemand, n)
                scale_factor = params.sloadAnnualDemand[n][sp] / load_raw
            end
            scen_profiles = ScenarioProfile[]
            for rp in representatives
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
        profiles = RepresentativeProfile[]
        for sp in strat_periods(periods)
            scen_profiles = ScenarioProfile[]
            for rp in repr_periods(sp)
                fixed_profiles = FixedProfile[]
                for sc in opscenarios(rp)
                    val = sum(params.maxRegHydroGenRaw[n][t] for t in sc)
                    push!(fixed_profiles, FixedProfile(val))
                end
                push!(scen_profiles, ScenarioProfile(fixed_profiles))
            end
            push!(profiles, RepresentativeProfile(scen_profiles))
        end
        params.maxRegHydroGen[n] = StrategicProfile(profiles)
    end
end
