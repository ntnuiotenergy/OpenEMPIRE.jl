
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

_solution_value(x) = Float64(JuMP.value(x))

function _strategic_indices(periods::TimeStructure)
    return collect(enumerate(strat_periods(periods)))
end

function _foreach_operational_index(f, par::EmpireParams, periods::TimeStructure)
    for (period_index, sp) in enumerate(strat_periods(periods))
        for (representative_index, rp) in enumerate(repr_periods(sp))
            season = season_name(par, representative_index)
            for (scenario_index, sc) in enumerate(opscenarios(rp))
                for (hour, t) in enumerate(sc)
                    f(period_index, scenario_index, season, hour, t)
                end
            end
        end
    end
    return nothing
end

function _write_csv_rows(path::AbstractString, rows)
    mkpath(dirname(path))
    CSV.write(path, rows)
    return path
end

"""
    write_solution_tables(result_dir, emp, sets, params, periods)

Write solved model variables to CSV files in `joinpath(result_dir, "Output")`.

The files intentionally mirror the simple Python variable dumps, but use CSV
instead of tab-delimited output. These tables are meant for formulation parity
checks and downstream aggregation, not as a complete replacement for EMPIRE's
full reporting layer.
"""
function write_solution_tables(result_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure)
    output_dir = joinpath(result_dir, "Output")
    mkpath(output_dir)

    write_investment_csvs(output_dir, emp, sets, periods)
    write_operational_csvs(output_dir, emp, sets, par, periods)

    return output_dir
end

function write_investment_csvs(output_dir::AbstractString, emp::JuMP.Model, sets, periods::TimeStructure)
    strategic_periods = _strategic_indices(periods)

    gen_inv = emp[:genInvCap]
    gen_cap = emp[:genInstalledCap]
    gen_rows = NamedTuple{(:Node, :Generator, :Period, :genInvCap), Tuple{String, String, Int, Float64}}[]
    gen_cap_rows = NamedTuple{(:Node, :Generator, :Period, :genInstalledCap), Tuple{String, String, Int, Float64}}[]
    for (n, g) in node_generators(sets), (period_index, sp) in strategic_periods
        push!(gen_rows, (Node = n, Generator = g, Period = period_index, genInvCap = _solution_value(gen_inv[n, g, sp])))
        push!(gen_cap_rows, (Node = n, Generator = g, Period = period_index, genInstalledCap = _solution_value(gen_cap[n, g, sp])))
    end
    _write_csv_rows(joinpath(output_dir, "genInvCap.csv"), gen_rows)
    _write_csv_rows(joinpath(output_dir, "genInstalledCap.csv"), gen_cap_rows)

    trans_inv = emp[:transmissionInvCap]
    trans_cap = emp[:transmissionInstalledCap]
    trans_rows = NamedTuple{(:FromNode, :ToNode, :Period, :transmisionInvCap), Tuple{String, String, Int, Float64}}[]
    trans_cap_rows = NamedTuple{(:FromNode, :ToNode, :Period, :transmissionInstalledCap), Tuple{String, String, Int, Float64}}[]
    for (m, n) in bidir_arcs(sets), (period_index, sp) in strategic_periods
        push!(trans_rows, (FromNode = m, ToNode = n, Period = period_index, transmisionInvCap = _solution_value(trans_inv[m, n, sp])))
        push!(trans_cap_rows, (FromNode = m, ToNode = n, Period = period_index, transmissionInstalledCap = _solution_value(trans_cap[m, n, sp])))
    end
    _write_csv_rows(joinpath(output_dir, "transmisionInvCap.csv"), trans_rows)
    _write_csv_rows(joinpath(output_dir, "transmissionInstalledCap.csv"), trans_cap_rows)

    stor_pw_inv = emp[:storPWInvCap]
    stor_pw_cap = emp[:storPWInstalledCap]
    stor_en_inv = emp[:storENInvCap]
    stor_en_cap = emp[:storENInstalledCap]
    stor_pw_rows = NamedTuple{(:Node, :Storage, :Period, :storPWInvCap), Tuple{String, String, Int, Float64}}[]
    stor_pw_cap_rows = NamedTuple{(:Node, :Storage, :Period, :storPWInstalledCap), Tuple{String, String, Int, Float64}}[]
    stor_en_rows = NamedTuple{(:Node, :Storage, :Period, :storENInvCap), Tuple{String, String, Int, Float64}}[]
    stor_en_cap_rows = NamedTuple{(:Node, :Storage, :Period, :storENInstalledCap), Tuple{String, String, Int, Float64}}[]
    for (n, s) in node_storages(sets), (period_index, sp) in strategic_periods
        push!(stor_pw_rows, (Node = n, Storage = s, Period = period_index, storPWInvCap = _solution_value(stor_pw_inv[n, s, sp])))
        push!(stor_pw_cap_rows, (Node = n, Storage = s, Period = period_index, storPWInstalledCap = _solution_value(stor_pw_cap[n, s, sp])))
        push!(stor_en_rows, (Node = n, Storage = s, Period = period_index, storENInvCap = _solution_value(stor_en_inv[n, s, sp])))
        push!(stor_en_cap_rows, (Node = n, Storage = s, Period = period_index, storENInstalledCap = _solution_value(stor_en_cap[n, s, sp])))
    end
    _write_csv_rows(joinpath(output_dir, "storPWInvCap.csv"), stor_pw_rows)
    _write_csv_rows(joinpath(output_dir, "storPWInstalledCap.csv"), stor_pw_cap_rows)
    _write_csv_rows(joinpath(output_dir, "storENInvCap.csv"), stor_en_rows)
    _write_csv_rows(joinpath(output_dir, "storENInstalledCap.csv"), stor_en_cap_rows)

    return output_dir
end

function write_operational_csvs(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure)
    gen_op = emp[:genOperational]
    gen_rows = NamedTuple{
        (:Node, :Generator, :Period, :Scenario, :Season, :Hour, :genOperational),
        Tuple{String, String, Int, Int, String, Int, Float64},
    }[]
    _foreach_operational_index(par, periods) do period, scenario, season, hour, t
        for (n, g) in node_generators(sets)
            push!(gen_rows, (
                Node = n,
                Generator = g,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                genOperational = _solution_value(gen_op[n, g, t]),
            ))
        end
    end
    _write_csv_rows(joinpath(output_dir, "genOperational.csv"), gen_rows)

    trans_op = emp[:transmissionOperational]
    trans_rows = NamedTuple{
        (:FromNode, :ToNode, :Period, :Scenario, :Season, :Hour, :transmisionOperational),
        Tuple{String, String, Int, Int, String, Int, Float64},
    }[]
    _foreach_operational_index(par, periods) do period, scenario, season, hour, t
        for (m, n) in arcs(sets)
            push!(trans_rows, (
                FromNode = m,
                ToNode = n,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                transmisionOperational = _solution_value(trans_op[m, n, t]),
            ))
        end
    end
    _write_csv_rows(joinpath(output_dir, "transmisionOperational.csv"), trans_rows)

    stor_charge = emp[:storCharge]
    stor_discharge = emp[:storDischarge]
    stor_operation = emp[:storOperational]
    stor_charge_rows = NamedTuple{
        (:Node, :Storage, :Period, :Scenario, :Season, :Hour, :storCharge),
        Tuple{String, String, Int, Int, String, Int, Float64},
    }[]
    stor_discharge_rows = NamedTuple{
        (:Node, :Storage, :Period, :Scenario, :Season, :Hour, :storDischarge),
        Tuple{String, String, Int, Int, String, Int, Float64},
    }[]
    stor_operation_rows = NamedTuple{
        (:Node, :Storage, :Period, :Scenario, :Season, :Hour, :storageOperational),
        Tuple{String, String, Int, Int, String, Int, Float64},
    }[]
    _foreach_operational_index(par, periods) do period, scenario, season, hour, t
        for (n, s) in node_storages(sets)
            push!(stor_charge_rows, (
                Node = n,
                Storage = s,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                storCharge = _solution_value(stor_charge[n, s, t]),
            ))
            push!(stor_discharge_rows, (
                Node = n,
                Storage = s,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                storDischarge = _solution_value(stor_discharge[n, s, t]),
            ))
            push!(stor_operation_rows, (
                Node = n,
                Storage = s,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                storageOperational = _solution_value(stor_operation[n, s, t]),
            ))
        end
    end
    _write_csv_rows(joinpath(output_dir, "storCharge.csv"), stor_charge_rows)
    _write_csv_rows(joinpath(output_dir, "storDischarge.csv"), stor_discharge_rows)
    _write_csv_rows(joinpath(output_dir, "storageOperational.csv"), stor_operation_rows)

    load_shed = emp[:loadShed]
    load_shed_rows = NamedTuple{
        (:Node, :Period, :Scenario, :Season, :Hour, :loadShed),
        Tuple{String, Int, Int, String, Int, Float64},
    }[]
    _foreach_operational_index(par, periods) do period, scenario, season, hour, t
        for n in nodes(sets)
            push!(load_shed_rows, (
                Node = n,
                Period = period,
                Scenario = scenario,
                Season = season,
                Hour = hour,
                loadShed = _solution_value(load_shed[n, t]),
            ))
        end
    end
    _write_csv_rows(joinpath(output_dir, "loadShed.csv"), load_shed_rows)

    return output_dir
end
