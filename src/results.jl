
function sol_invest_cost(emp, sets, par, periods, discounter::Discounter)

    genInvCap = emp[:genInvCap]
    transInvCap = emp[:transmissionInvCap]
    storInvCapPow = emp[:storPWInvCap]
    storInvCapEn = emp[:storENInvCap]

    SP = strat_periods(periods)
    N = nodes(sets)

    gen_cost = sum(objective_weight(sp, discounter) *
            sum(gen_invest_cost(par, g, sp) * value(genInvCap[n, g, sp]) for n in N for g in generators(sets, n); init = 0)
            for sp in SP)
    trans_cost = sum(objective_weight(sp, discounter) * (
            sum(trans_invest_cost(par, m, n, sp) * value(transInvCap[m, n, sp]) for (m, n) in arcs(sets); init = 0)
            ) for sp in SP)
    stor_pw_cost = sum(objective_weight(sp, discounter) * (
            sum(stor_pw_invest_cost(par, s, sp) * value(storInvCapPow[n, s, sp]) for n in N for s in storages(sets, n); init = 0)
            ) for sp in SP)
    stor_en_cost = sum(objective_weight(sp, discounter) * (
            sum(stor_en_invest_cost(par, s, sp) * value(storInvCapEn[n, s, sp]) for n in N for s in storages(sets, n); init = 0)
            ) for sp in SP)

    return gen_cost, trans_cost, stor_pw_cost, stor_en_cost
end


function sol_operational_cost(emp, sets, par, periods, discounter::Discounter)

    genOperational = emp[:genOperational]
    loadShed = emp[:loadShed]

    T = periods
    N = nodes(sets)

    gen_cost = sum(objective_weight(t, discounter; type = "avg_year") * (
            sum(gen_marginal_cost(par, g, t) * value(genOperational[n, g, t]) for n in N for g in generators(sets, n); init = 0)
            ) for t in T)

    load_shed_cost = sum(objective_weight(t, discounter; type = "avg_year") * (
            sum(lost_load_cost(par, n, t) * value(loadShed[n, t]) for n in N; init = 0)
            ) for t in T)

    return gen_cost, load_shed_cost
end


function total_load_shedding(emp, sets, periods)

    loadShed = emp[:loadShed]
    T = periods
    N = nodes(sets)

    return sum(
        multiple(t) * probability(t) * value(loadShed[n, t])
        for n in N, t in T;
        init = 0,
    )
end


function total_generation(emp, sets, periods)

    genOperational = emp[:genOperational]
    T = periods
    N = nodes(sets)

    return sum(
        multiple(t) * probability(t) *
        sum(value(genOperational[n, g, t]) for g in generators(sets, n); init = 0)
        for n in N, t in T;
        init = 0,
    )
end


function annual_emissions(emp, sets, par, periods)

    SP = strat_periods(periods)
    emissions = Dict{Tuple{Any, Int}, Float64}()

    for sp in SP
        for scenario_number in eachindex(collect(opscenarios(first(repr_periods(sp)))))
            emissions[(sp, scenario_number)] =
                _annual_emissions_for_scenario(emp, sets, par, sp, scenario_number)
        end
    end

    return emissions
end


function generator_results(emp, sets, par, periods, discounter::Discounter)

    genInvCap = emp[:genInvCap]
    genInstalledCap = emp[:genInstalledCap]
    genOperational = emp[:genOperational]
    SP = strat_periods(periods)
    NG = node_generators(sets)

    return [
        begin
            annual_prod_mwh = sum(
                multiple_strat(sp, t) * probability(t) * value(genOperational[n, g, t])
                for t in sp;
                init = 0,
            )
            installed_cap = value(genInstalledCap[n, g, sp])
            inv_cap = value(genInvCap[n, g, sp])

            (
                Node = n,
                GeneratorType = g,
                Period = sp,
                genInvCap_MW = inv_cap,
                genInstalledCap_MW = installed_cap,
                genExpectedCapacityFactor = installed_cap > 0 ? annual_prod_mwh / (installed_cap * 8760) : 0.0,
                DiscountedInvestmentCost_Euro = objective_weight(sp, discounter) * gen_invest_cost(par, g, sp) * inv_cap,
                genExpectedAnnualProduction_GWh = annual_prod_mwh / 1000,
            )
        end
        for (n, g) in NG
        for sp in SP
    ]
end


function storage_results(emp, sets, par, periods, discounter::Discounter)

    storPWInvCap = emp[:storPWInvCap]
    storPWInstalledCap = emp[:storPWInstalledCap]
    storENInvCap = emp[:storENInvCap]
    storENInstalledCap = emp[:storENInstalledCap]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    SP = strat_periods(periods)
    NS = node_storages(sets)

    return [
        begin
            annual_discharge_mwh = sum(
                multiple_strat(sp, t) * probability(t) * value(storDischarge[n, s, t])
                for t in sp;
                init = 0,
            )

            annual_losses_mwh = sum(
                multiple_strat(sp, t) * probability(t) *
                (
                    (1 - discharge_eff(par, s)) * value(storDischarge[n, s, t]) +
                    (1 - charge_eff(par, s)) * value(storCharge[n, s, t])
                )
                for t in sp;
                init = 0,
            )

            (
                Node = n,
                StorageType = s,
                Period = sp,
                storPWInvCap_MW = value(storPWInvCap[n, s, sp]),
                storPWInstalledCap_MW = value(storPWInstalledCap[n, s, sp]),
                storENInvCap_MWh = value(storENInvCap[n, s, sp]),
                storENInstalledCap_MWh = value(storENInstalledCap[n, s, sp]),
                DiscountedInvestmentCostPWEN_EuroPerMWMWh = objective_weight(sp, discounter) * (
                    stor_pw_invest_cost(par, s, sp) * value(storPWInvCap[n, s, sp]) +
                    stor_en_invest_cost(par, s, sp) * value(storENInvCap[n, s, sp])
                ),
                ExpectedAnnualDischargeVolume_GWh = annual_discharge_mwh / 1000,
                ExpectedAnnualLossesChargeDischarge_GWh = annual_losses_mwh / 1000,
            )
        end
        for (n, s) in NS
        for sp in SP
    ]
end


function transmission_results(emp, sets, par, periods, discounter::Discounter)

    transmissionInvCap = emp[:transmissionInvCap]
    transmissionInstalledCap = emp[:transmissionInstalledCap]
    transmissionOperational = emp[:transmissionOperational]
    SP = strat_periods(periods)
    BA = bidir_arcs(sets)

    return [
        begin
            annual_volume_mwh = sum(
                multiple_strat(sp, t) * probability(t) *
                (
                    value(transmissionOperational[n1, n2, t]) +
                    value(transmissionOperational[n2, n1, t])
                )
                for t in sp;
                init = 0,
            )

            annual_losses_mwh = sum(
                multiple_strat(sp, t) * probability(t) *
                (
                    (1 - line_eff(par, n1, n2)) * value(transmissionOperational[n1, n2, t]) +
                    (1 - line_eff(par, n2, n1)) * value(transmissionOperational[n2, n1, t])
                )
                for t in sp;
                init = 0,
            )

            (
                BetweenNode = n1,
                AndNode = n2,
                Period = sp,
                transmissionInvCap_MW = value(transmissionInvCap[n1, n2, sp]),
                transmissionInstalledCap_MW = value(transmissionInstalledCap[n1, n2, sp]),
                DiscountedInvestmentCost_Euro = (
                    objective_weight(sp, discounter) *
                    trans_invest_cost(par, n1, n2, sp) *
                    value(transmissionInvCap[n1, n2, sp])
                ),
                transmissionExpectedAnnualVolume_GWh = annual_volume_mwh / 1000,
                ExpectedAnnualLosses_GWh = annual_losses_mwh / 1000,
            )
        end
        for (n1, n2) in BA
        for sp in SP
    ]
end


function emission_summary(emp, sets, par, periods)

    genOperational = emp[:genOperational]
    SP = strat_periods(periods)
    NG = node_generators(sets)

    return [
        begin
            emissions_ton = _annual_emissions_for_scenario(emp, sets, par, sp, scenario_number)

            annual_generation_mwh = sum(
                multiple_strat(sp, t) *
                sum(value(genOperational[n, g, t]) for (n, g) in NG; init = 0)
                for rp in repr_periods(sp)
                for (k, sc) in enumerate(opscenarios(rp))
                if k == scenario_number
                for t in sc;
                init = 0,
            )

            (
                Period = sp,
                Scenario = scenario_number,
                AnnualCO2emission_Ton = emissions_ton,
                CO2Price_EuroPerTon = co2_price(par, sp),
                CO2Cap_Ton = isnothing(co2_cap(par, sp)) ? 0.0 : co2_cap(par, sp) * 1e6,
                AnnualGeneration_GWh = annual_generation_mwh / 1000,
                AvgCO2factor_TonPerMWh = annual_generation_mwh > 0 ? emissions_ton / annual_generation_mwh : 0.0,
            )
        end
        for sp in SP
        for scenario_number in eachindex(collect(opscenarios(first(repr_periods(sp)))))
    ]
end


# Internal helpers
function _co2_intensity(par, g, sp)

    content = co2_content(par, g)
    content == 0.0 && return 0.0

    return content * (3.6 / par.genEfficiency[g][sp])
end

function _annual_emissions_for_scenario(emp, sets, par, sp, scenario_number)

    genOperational = emp[:genOperational]
    NG = node_generators(sets)

    return sum(
        multiple_strat(sp, t) *
        value(genOperational[n, g, t]) *
        _co2_intensity(par, g, sp)
        for rp in repr_periods(sp)
        for (k, sc) in enumerate(opscenarios(rp))
        if k == scenario_number
        for t in sc
        for (n, g) in NG;
        init = 0,
    )
end
