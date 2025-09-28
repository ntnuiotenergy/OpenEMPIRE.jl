
function sol_invest_cost(emp, sets, par, periods, discounter::Discounter)

    genInvCap = emp[:genInvCap]
    transInvCap = emp[:transmissionInvCap]
    storInvCapPow = emp[:storPWInvCap]
    storInvCapEn = emp[:storENInvCap]

    SP = strat_periods(periods)
    N = sets.Node

    inv_cost = sum(objective_weight(sp, discounter) * (
            sum(gen_invest_cost(par, g, sp) * value(genInvCap[n, g, sp]) for n in N for g in generators(sets, n); init = 0) +
            sum(trans_invest_cost(par, m, n, sp) * value(transInvCap[m, n, sp]) for (m, n) in arcs(sets); init = 0) +
            sum(stor_pw_invest_cost(par, s, sp) * value(storInvCapPow[n, s, sp]) for n in N for s in storages(sets, n); init = 0) +
            sum(stor_en_invest_cost(par, s, sp) * value(storInvCapEn[n, s, sp]) for n in N for s in storages(sets, n); init = 0)
            ) for sp in SP)
    return inv_cost
end


function sol_operational_cost(emp, sets, par, periods, discounter::Discounter)

    genOperational = emp[:genOperational]
    loadShed = emp[:loadShed]

    T = periods
    N = sets.Node

    gen_cost = sum(objective_weight(t, discounter) * (
            sum(gen_marginal_cost(par, g, t) * value(genOperational[n, g, t]) for n in N for g in generators(sets, n); init = 0)
            ) for t in T)

    load_shed_cost = sum(objective_weight(t, discounter) * (
            sum(lost_load_cost(par, n, t) * value(loadShed[n, t]) for n in N; init = 0)
            ) for t in T)

    return gen_cost, load_shed_cost
end
