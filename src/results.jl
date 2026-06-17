
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
            sum(trans_invest_cost(par, m, n, sp) * value(transInvCap[m, n, sp]) for (m, n) in bidir_arcs(sets); init = 0)
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

    SP = strat_periods(periods)
    N = nodes(sets)

    gen_cost = sum(operational_objective_weight(par, sp, representative_index, t, discounter) * (
            sum(gen_marginal_cost(par, g, t) * value(genOperational[n, g, t]) for n in N for g in generators(sets, n); init = 0)
            )
        for sp in SP
        for (representative_index, rp) in enumerate(repr_periods(sp))
        for sc in opscenarios(rp)
        for t in sc)

    load_shed_cost = sum(operational_objective_weight(par, sp, representative_index, t, discounter) * (
            sum(lost_load_cost(par, n, t) * value(loadShed[n, t]) for n in N; init = 0)
            )
        for sp in SP
        for (representative_index, rp) in enumerate(repr_periods(sp))
        for sc in opscenarios(rp)
        for t in sc)

    return gen_cost, load_shed_cost
end
