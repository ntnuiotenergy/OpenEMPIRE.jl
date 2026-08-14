
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

    N = nodes(sets)

    gen_cost = sum(objective_weight(t, discounter; type = "avg_year") * (
            sum(gen_marginal_cost(par, g, t) * value(genOperational[n, g, t]) for n in N for g in generators(sets, n); init = 0)
            )
        for t in periods)

    load_shed_cost = sum(objective_weight(t, discounter; type = "avg_year") * (
            sum(lost_load_cost(par, n, t) * value(loadShed[n, t]) for n in N; init = 0)
            )
        for t in periods)

    return gen_cost, load_shed_cost
end

_solution_value(x) = Float64(JuMP.value(x))

function _strategic_indices(periods::TimeStructure)
    return collect(enumerate(strat_periods(periods)))
end

_scenario_label(scenario_index::Integer) = "scenario$scenario_index"

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

function _foreach_operational_context(f, par::EmpireParams, periods::TimeStructure)
    for (period_index, sp) in enumerate(strat_periods(periods))
        hour_offset = 0
        for (representative_index, rp) in enumerate(repr_periods(sp))
            season = season_name(par, representative_index)
            first_scenario = first(opscenarios(rp))
            for (scenario_index, sc) in enumerate(opscenarios(rp))
                for (local_hour, t) in enumerate(sc)
                    f(period_index, sp, scenario_index, representative_index, season, hour_offset + local_hour, t)
                end
            end
            hour_offset += length(first_scenario)
        end
    end
    return nothing
end

function _foreach_natural_gas_operational_context(
    f,
    par::EmpireParams,
    periods::TimeStructure,
)
    gas_scenarios = par.NaturalGas.gasScenarioCount
    _foreach_operational_context(
        (
            period,
            strategic_period,
            combined_scenario,
            representative,
            season,
            hour,
            operational_period,
        ) -> begin
        f(
            period,
            strategic_period,
            combined_scenario,
            weather_scenario_index(combined_scenario, gas_scenarios),
            gas_scenario_index(combined_scenario, gas_scenarios),
            representative,
            season,
            hour,
            operational_period,
        )
        end,
        par,
        periods,
    )
    return nothing
end

"""
    _log_write(path)

Announce a solution table on stdout with a wall-clock timestamp, mirroring
InternalEMPIRE's `HH:MM:SS: Writing ... to <file>` lines. Writing the full
`full_model_int` output set takes tens of minutes, so a run that prints nothing
between "solve finished" and "run complete" looks hung. Every table goes through
either this or [`_write_csv_table`], so one call site here covers all of them.
"""
function _log_write(path::AbstractString)
    println(Dates.format(Dates.now(), "HH:MM:SS"), ": Writing ", basename(path))
    flush(stdout)
    return nothing
end

function _write_csv_rows(path::AbstractString, rows)
    mkpath(dirname(path))
    _log_write(path)
    CSV.write(path, rows)
    return path
end

"""
    _stream_csv_table(path, header, emit)

Write a table row by row without materialising it.

`emit` receives a callback and calls it once per row. Building the whole table
first — `push!` into a `Vector{NamedTuple}`, then `CSV.write` — costs memory
proportional to the row count: `genOperational` alone is 13,048,560 rows, about
0.9 GB resident before a single byte reaches disk, and the operational tables are
written back to back. Streaming keeps that flat.
"""
function _stream_csv_table(path::AbstractString, header, emit::Function)
    _write_csv_table(path, header) do io
        emit(row -> _write_csv_row(io, row))
    end
    return path
end

# `do` blocks pass the function first, matching `_write_csv_table`'s two orders.
_stream_csv_table(emit::Function, path::AbstractString, header) =
    _stream_csv_table(path, header, emit)

function _csv_field(value)
    if value isa AbstractFloat && isnan(value)
        return "NaN"
    end
    text = string(value)
    if occursin(',', text) || occursin('"', text) || occursin('\n', text) || occursin('\r', text)
        return "\"" * replace(text, "\"" => "\"\"") * "\""
    end
    return text
end

function _write_csv_row(io, row)
    println(io, join((_csv_field(value) for value in row), ","))
    return nothing
end

function _write_csv_table(path::AbstractString, header, write_rows::Function)
    mkpath(dirname(path))
    _log_write(path)
    open(path, "w") do io
        _write_csv_row(io, header)
        write_rows(io)
    end
    return path
end

_write_csv_table(write_rows::Function, path::AbstractString, header) =
    _write_csv_table(path, header, write_rows)

function _value_or_zero(container, args...)
    try
        return _solution_value(container[args...])
    catch
        return 0.0
    end
end

function _objective_value_or_nan(emp::JuMP.Model)
    try
        return Float64(JuMP.objective_value(emp))
    catch
        return NaN
    end
end

function _dual_or_nan(container, args...)
    try
        return Float64(JuMP.dual(container[args...]))
    catch
        return NaN
    end
end

function _period_labels(periods::TimeStructure; base_year::Int = 2020)
    labels = String[]
    start_year = base_year
    for sp in strat_periods(periods)
        years = round(Int, duration_strat(sp))
        stop_year = start_year + years
        push!(labels, "$start_year-$stop_year")
        start_year = stop_year
    end
    return labels
end

function _period_label(labels::Vector{String}, period_index::Integer)
    return labels[Int(period_index)]
end

function _discount_multiplier(par::EmpireParams, periods::TimeStructure, sp)
    return objective_weight(sp, Discounter(discount_rate(par), 1, periods))
end

function _gen_efficiency(par::EmpireParams, generator::AbstractString, sp)
    return haskey(par.genEfficiency, generator) ? par.genEfficiency[generator][sp] : 1.0
end

function _gen_capacity_availability(par::EmpireParams, node::AbstractString, generator::AbstractString, t)
    if haskey(par.genCapAvail, (node, generator))
        return par.genCapAvail[(node, generator)][t]
    end
    return get(par.genCapAvailType, generator, 1.0)
end

function _is_res_generator(sets, generator::AbstractString)
    generator in ("Hydrorun-of-the-river", "Windonshore", "Windoffshore", "Solar") && return true
    for (technology, gen) in sets.GeneratorsOfTechnology
        gen == generator || continue
        technology in ("Hydro_ror", "Wind_onshr", "Wind_offshr", "Solar") && return true
    end
    return false
end

function _flow_balance_price(emp::JuMP.Model, node::AbstractString, sp, t, discounter::Discounter)
    objects = JuMP.object_dictionary(emp)
    haskey(objects, :flow_balance) || return NaN
    strategic_weight = objective_weight(sp, discounter)
    strategic_weight == 0 && return NaN
    scale = objective_weight(t, discounter; type = "avg_year") / strategic_weight
    scale == 0 && return NaN
    return _dual_or_nan(emp[:flow_balance], node, t) / scale
end

function _emission_price(emp::JuMP.Model, par::EmpireParams, sp, scenario_index::Integer, t, discounter::Discounter)
    if co2_cap(par, sp) !== nothing && haskey(JuMP.object_dictionary(emp), :emission_cap)
        # The emission-cap constraint (model_definition.jl) is written in tons:
        #   sum(nodeEmission) <= 1e6 * co2_cap   (co2_cap is stored in Mtons).
        # Its dual is therefore already in EUR/ton, so we only undo the objective's
        # objective discount/probability weighting here. (Python's constraint is instead written
        # in Mtons — LHS divided by 1e6 — so its dual is EUR/Mton and Python multiplies
        # the divisor by 1e6 to reach EUR/ton; we must NOT, or the price comes out 1e6x
        # too small. See results.jl parity notes / DIAGNOSIS_parity_test_dataset.md.)
        strategic_weight = objective_weight(sp, discounter)
        annual_multiple = multiple_strat(sp, t)
        (strategic_weight == 0 || annual_multiple == 0) && return NaN
        scale = objective_weight(t, discounter; type = "avg_year") /
            (strategic_weight * annual_multiple)
        scale == 0 && return NaN
        return _dual_or_nan(emp[:emission_cap], sp, scenario_index) / scale
    end
    return co2_price(par, sp)
end

function _incoming_nodes(sets, node::AbstractString)
    return [from for (from, to) in arcs(sets) if to == node]
end

function _outgoing_nodes(sets, node::AbstractString)
    return [to for (from, to) in arcs(sets) if from == node]
end

"""
    write_solution_tables(result_dir, emp, sets, params, periods)

Write solved model variables and reports to CSV files in `joinpath(result_dir, "output")`.

The low-level files mirror the simple first-stage and operational variable
dumps, while the `results_*.csv` files provide Python-style reporting tables
with cleaned Julia naming conventions.
"""
function write_solution_tables(result_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure)
    output_dir = joinpath(result_dir, "output")
    mkpath(output_dir)

    write_investment_csvs(output_dir, emp, sets, periods)
    write_operational_csvs(output_dir, emp, sets, par, periods)
    write_report_csvs(output_dir, emp, sets, par, periods)
    has_natural_gas(sets) &&
        haskey(JuMP.object_dictionary(emp), :ngTerminalImport) &&
        write_natural_gas_csvs(output_dir, emp, sets, par, periods)
    has_hydrogen(sets) &&
        haskey(JuMP.object_dictionary(emp), :electrolyzerCapBuilt) &&
        write_hydrogen_csvs(output_dir, emp, sets, par, periods)

    return output_dir
end

function _write_hydrogen_table(write_rows, output_dir, filenames, header)
    primary = _write_csv_table(joinpath(output_dir, first(filenames)), header, write_rows)
    for filename in Iterators.drop(filenames, 1)
        cp(primary, joinpath(output_dir, filename); force = true)
    end
    return primary
end

function _write_hydrogen_oos_capacity_tables(
    output_dir,
    emp,
    hydrogen,
    strategic_periods,
    co2_corridors,
)
    capacity_specs = (
        (
            "H2ImportCapBuilt.csv", ["Node", "TerminalType", "Period", "H2ImportCapBuilt"],
            hydrogen.TerminalsOfNode, emp[:hydrogenImportCapBuilt], :terminal,
        ),
        (
            "H2ImportTotalCap.csv", ["Node", "TerminalType", "Period", "H2ImportTotalCap"],
            hydrogen.TerminalsOfNode, emp[:hydrogenImportCapInstalled], :terminal,
        ),
        (
            "elyzerCapBuilt.csv", ["Node", "Period", "elyzerCapBuilt"],
            hydrogen.ProductionNode, emp[:electrolyzerCapBuilt], :node,
        ),
        (
            "elyzerTotalCap.csv", ["Node", "Period", "elyzerTotalCap"],
            hydrogen.ProductionNode, emp[:electrolyzerCapInstalled], :node,
        ),
        (
            "ReformerCapBuilt.csv", ["Node", "ReformerPlant", "Period", "ReformerCapBuilt"],
            [(node, plant) for node in hydrogen.ReformerLocation for plant in hydrogen.ReformerPlant],
            emp[:reformerCapBuilt], :plant,
        ),
        (
            "ReformerTotalCap.csv", ["Node", "ReformerPlant", "Period", "ReformerTotalCap"],
            [(node, plant) for node in hydrogen.ReformerLocation for plant in hydrogen.ReformerPlant],
            emp[:reformerCapInstalled], :plant,
        ),
        (
            "hydrogenPipelineBuilt.csv", ["FromNode", "ToNode", "Period", "hydrogenPipelineBuilt"],
            hydrogen.Corridor, emp[:hydrogenPipelineCapBuilt], :arc,
        ),
        (
            "repurposedPipelineBuilt.csv", ["FromNode", "ToNode", "Period", "repurposedPipelineBuilt"],
            hydrogen.RepurposableGasCorridor, emp[:hydrogenRepurposedGasPipelineCapBuilt], :arc,
        ),
        (
            "totalHydrogenPipelineCapacity.csv", ["FromNode", "ToNode", "Period", "totalHydrogenPipelineCapacity"],
            hydrogen.Corridor, emp[:hydrogenPipelineCapInstalled], :arc,
        ),
        (
            "hydrogenStorageBuilt.csv", ["Node", "H2Storage", "Period", "hydrogenStorageBuilt"],
            hydrogen.StoragesOfNode, emp[:hydrogenStorageCapBuilt], :storage,
        ),
        (
            "hydrogenTotalStorage.csv", ["Node", "H2Storage", "Period", "hydrogenTotalStorage"],
            hydrogen.StoragesOfNode, emp[:hydrogenStorageCapInstalled], :storage,
        ),
        (
            "CO2PipelineBuilt.csv", ["FromNode", "ToNode", "Period", "CO2PipelineBuilt"],
            co2_corridors, emp[:co2PipelineCapBuilt], :arc,
        ),
        (
            "totalCO2PipelineCapacity.csv", ["FromNode", "ToNode", "Period", "totalCO2PipelineCapacity"],
            co2_corridors, emp[:co2PipelineCapInstalled], :arc,
        ),
        (
            "CO2SiteCapacityDeveloped.csv", ["Node", "Period", "CO2SiteCapacityDeveloped"],
            hydrogen.CO2SequestrationNode, emp[:co2SequestrationCapBuilt], :node,
        ),
    )
    for (filename, header, keys, variable, shape) in capacity_specs
        _write_hydrogen_table(output_dir, (filename,), header) do io
            for key in keys, (period, strategic_period) in strategic_periods
                if shape === :node
                    _write_csv_row(io, [key, period, _solution_value(variable[key, strategic_period])])
                else
                    first_key, second_key = key
                    _write_csv_row(io, [
                        first_key, second_key, period,
                        _solution_value(variable[first_key, second_key, strategic_period]),
                    ])
                end
            end
        end
    end
    return nothing
end

function write_hydrogen_csvs(output_dir, emp, sets, par, periods)
    hydrogen = hydrogen_sets(sets)
    strategic_periods = collect(enumerate(strat_periods(periods)))
    _write_hydrogen_table(
        output_dir,
        ("hydrogenElectrolyzerCapacity.csv", "results_hydrogen_electrolyzer_investments.csv"),
        ["Node", "Period", "Built_MW", "Installed_MW"],
    ) do io
        for node in hydrogen.ProductionNode, (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                node, period,
                _solution_value(emp[:electrolyzerCapBuilt][node, strategic_period]),
                _solution_value(emp[:electrolyzerCapInstalled][node, strategic_period]),
            ])
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenReformerCapacity.csv", "results_hydrogen_reformer_investments.csv"),
        ["Node", "Plant", "Period", "Built_MW_H2", "Installed_MW_H2"],
    ) do io
        for node in hydrogen.ReformerLocation, plant in hydrogen.ReformerPlant,
            (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                node, plant, period,
                _solution_value(emp[:reformerCapBuilt][node, plant, strategic_period]),
                _solution_value(emp[:reformerCapInstalled][node, plant, strategic_period]),
            ])
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenPipelineCapacity.csv", "results_hydrogen_pipeline_investments.csv"),
        ["FromNode", "ToNode", "Period", "Built_Hydrogen_ton_per_h", "Installed_Hydrogen_ton_per_h"],
    ) do io
        for (from, to) in hydrogen.Corridor, (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                from, to, period,
                _solution_value(emp[:hydrogenPipelineCapBuilt][from, to, strategic_period]),
                _solution_value(emp[:hydrogenPipelineCapInstalled][from, to, strategic_period]),
            ])
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenRepurposedGasPipeline.csv", "results_hydrogen_repurposed_pipeline.csv"),
        ["FromNode", "ToNode", "Period", "Built_NaturalGas_ton_per_h", "Installed_NaturalGas_ton_per_h"],
    ) do io
        for (from, to) in hydrogen.RepurposableGasCorridor,
            (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                from, to, period,
                _solution_value(emp[:hydrogenRepurposedGasPipelineCapBuilt][from, to, strategic_period]),
                _solution_value(emp[:hydrogenRepurposedGasPipelineCapInstalled][from, to, strategic_period]),
            ])
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenStorageCapacity.csv", "results_hydrogen_storage_investments.csv"),
        ["Node", "Storage", "Period", "Built_ton", "Installed_ton"],
    ) do io
        for (node, storage) in hydrogen.StoragesOfNode,
            (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                node, storage, period,
                _solution_value(emp[:hydrogenStorageCapBuilt][node, storage, strategic_period]),
                _solution_value(emp[:hydrogenStorageCapInstalled][node, storage, strategic_period]),
            ])
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenImportCapacity.csv", "results_hydrogen_import_investments.csv"),
        ["Node", "Terminal", "Period", "Built_ton_per_h", "Installed_ton_per_h"],
    ) do io
        for (node, terminal) in hydrogen.TerminalsOfNode,
            (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                node, terminal, period,
                _solution_value(emp[:hydrogenImportCapBuilt][node, terminal, strategic_period]),
                _solution_value(emp[:hydrogenImportCapInstalled][node, terminal, strategic_period]),
            ])
        end
    end
    co2_corridors = unique(Arc[minmax(from, to) for (from, to) in hydrogen.CO2DirectionalLink])
    _write_hydrogen_table(
        output_dir,
        ("co2StrategicCapacity.csv", "results_co2_investments.csv"),
        ["Asset", "FromOrNode", "ToNode", "Period", "Built", "Installed"],
    ) do io
        for (from, to) in co2_corridors, (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                "Pipeline", from, to, period,
                _solution_value(emp[:co2PipelineCapBuilt][from, to, strategic_period]),
                _solution_value(emp[:co2PipelineCapInstalled][from, to, strategic_period]),
            ])
        end
        for node in hydrogen.CO2SequestrationNode,
            (period, strategic_period) in strategic_periods
            _write_csv_row(io, [
                "SequestrationSite", node, "", period,
                _solution_value(emp[:co2SequestrationCapBuilt][node, strategic_period]),
                _solution_value(emp[:co2SequestrationCapInstalled][node, strategic_period]),
            ])
        end
    end
    _write_hydrogen_oos_capacity_tables(
        output_dir,
        emp,
        hydrogen,
        strategic_periods,
        co2_corridors,
    )

    operational_header = [
        "Period", "Scenario", "WeatherScenario", "GasScenario", "Season", "Hour",
    ]
    function each_context(f)
        _foreach_natural_gas_operational_context(
            (period, strategic_period, scenario, weather, gas, representative, season, hour, t) ->
                f((period, scenario, weather, gas, season, hour), t),
            par,
            periods,
        )
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenProduction.csv", "results_hydrogen_production.csv"),
        vcat(["Source", "Node", "Technology"], operational_header, ["Hydrogen_ton_per_h", "Hydrogen_MWh_per_h", "Electricity_MW", "NaturalGas_ton_per_h"]),
    ) do io
        each_context() do context, t
            for node in hydrogen.ProductionNode
                tonnes = _solution_value(emp[:electrolyzerHydrogen][node, t])
                _write_csv_row(io, vcat([
                    "Electrolyzer", node, "Electrolyzer",
                ], collect(context), [
                    tonnes, tonnes * par.Hydrogen.hydrogenMWhPerTon,
                    _solution_value(emp[:electrolyzerElectricity][node, t]), 0.0,
                ]))
            end
            for node in hydrogen.ReformerLocation, plant in hydrogen.ReformerPlant
                _write_csv_row(io, vcat([
                    "Reformer", node, plant,
                ], collect(context), [
                    _solution_value(emp[:reformerHydrogenTon][node, plant, t]),
                    _solution_value(emp[:reformerHydrogenMWh][node, plant, t]),
                    par.Hydrogen.reformerElectricityUse[(plant, context[1])] *
                    _solution_value(emp[:reformerHydrogenTon][node, plant, t]),
                    _solution_value(emp[:reformerNaturalGas][node, plant, t]),
                ]))
            end
            for (node, terminal) in hydrogen.TerminalsOfNode
                _write_csv_row(io, vcat([
                    "Import", node, terminal,
                ], collect(context), [
                    _solution_value(emp[:hydrogenImportTon][node, terminal, t]),
                    _solution_value(emp[:hydrogenImportMWh][node, terminal, t]),
                    0.0, 0.0,
                ]))
            end
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenPipelineFlow.csv", "results_hydrogen_pipeline_operations.csv"),
        vcat(["FromNode", "ToNode"], operational_header, ["Flow_ton_per_h"]),
    ) do io
        each_context() do context, t
            for (from, to) in hydrogen.DirectionalLink
                _write_csv_row(io, vcat(
                    [from, to], collect(context),
                    [_solution_value(emp[:hydrogenPipelineFlow][from, to, t])],
                ))
            end
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenStorageOperations.csv", "results_hydrogen_storage_operations.csv"),
        vcat(["Node", "Storage"], operational_header, ["Level_ton", "Charge_ton_per_h", "Discharge_ton_per_h", "Compression_MW"]),
    ) do io
        each_context() do context, t
            for (node, storage) in hydrogen.StoragesOfNode
                _write_csv_row(io, vcat([node, storage], collect(context), [
                    _solution_value(emp[:hydrogenStorageLevel][node, storage, t]),
                    _solution_value(emp[:hydrogenStorageCharge][node, storage, t]),
                    _solution_value(emp[:hydrogenStorageDischarge][node, storage, t]),
                    _solution_value(emp[:hydrogenStorageCompressionPower][node, storage, t]),
                ]))
            end
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenForPower.csv", "results_hydrogen_for_power.csv"),
        vcat(["Node", "Generator"], operational_header, ["Hydrogen_ton_per_h"]),
    ) do io
        each_context() do context, t
            for (node, generator) in _hydrogen_node_generators(sets)
                _write_csv_row(io, vcat(
                    [node, generator], collect(context),
                    [_solution_value(emp[:hydrogenForPower][node, generator, t])],
                ))
            end
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("hydrogenTransport.csv", "results_transport_hydrogen_operations.csv"),
        vcat(["Node"], operational_header, ["ElectricityMet_MW", "ElectricityShed_MW", "HydrogenMet_ton_per_h", "HydrogenShed_ton_per_h"]),
    ) do io
        each_context() do context, t
            for node in natural_gas_onshore_nodes(sets)
                _write_csv_row(io, vcat([node], collect(context), [
                    _solution_value(emp[:transportElectricityDemandMet][node, t]),
                    _solution_value(emp[:transportElectricityDemandShed][node, t]),
                    _solution_value(emp[:transportHydrogenDemandMet][node, t]),
                    _solution_value(emp[:transportHydrogenDemandShed][node, t]),
                ]))
            end
        end
    end
    _write_hydrogen_table(
        output_dir,
        ("co2Operations.csv", "results_co2_operations.csv"),
        vcat(["FromOrNode", "ToNode", "Operation"], operational_header, ["CO2_ton_per_h"]),
    ) do io
        each_context() do context, t
            for (from, to) in hydrogen.CO2DirectionalLink
                _write_csv_row(io, vcat(
                    [from, to, "Pipeline"], collect(context),
                    [_solution_value(emp[:co2PipelineFlow][from, to, t])],
                ))
            end
            for node in hydrogen.CO2SequestrationNode
                _write_csv_row(io, vcat(
                    [node, "", "Sequestration"], collect(context),
                    [_solution_value(emp[:co2Sequestered][node, t])],
                ))
            end
        end
    end
    hydrogen_costs = hydrogen_objective_expressions(
        emp,
        sets,
        par,
        periods,
        Discounter(discount_rate(par), 1, periods),
    )
    _write_hydrogen_table(
        output_dir,
        ("hydrogenCO2ObjectiveComponents.csv", "results_hydrogen_co2_objective.csv"),
        ["Component", "DiscountedCost_EUR"],
    ) do io
        for (name, expression) in pairs(hydrogen_costs)
            _write_csv_row(io, [String(name), JuMP.value(expression)])
        end
    end
    JuMP.has_duals(emp) && write_hydrogen_dual_csvs(output_dir, emp, sets, par, periods)
    return output_dir
end

function write_hydrogen_dual_csvs(output_dir, emp, sets, par, periods)
    discounter = Discounter(discount_rate(par), 1, periods)
    return _write_csv_table(
        joinpath(output_dir, "hydrogenCO2OperationalDuals.csv"),
        ["Commodity", "Node", "Period", "Scenario", "WeatherScenario", "GasScenario", "Season", "Hour", "Price_EUR_per_ton"],
    ) do io
        _foreach_natural_gas_operational_context(
            (period, strategic_period, scenario, weather, gas, representative, season, hour, t) -> begin
                weight = objective_weight(t, discounter; type = "avg_year")
                for node in hydrogen_nodes(sets)
                    _write_csv_row(io, [
                        "Hydrogen", node, period, scenario, weather, gas, season, hour,
                        _dual_or_nan(emp[:hydrogen_flow_balance], node, t) / weight,
                    ])
                end
                for node in natural_gas_onshore_nodes(sets)
                    _write_csv_row(io, [
                        "CO2", node, period, scenario, weather, gas, season, hour,
                        _dual_or_nan(emp[:co2_flow_balance], node, t) / weight,
                    ])
                end
            end,
            par,
            periods,
        )
    end
end

function _write_natural_gas_table(
    output_dir,
    filenames,
    header,
    write_rows,
)
    # Each gas family is published under a native and a Python-style name. Build
    # the table once and copy it: `write_rows` re-walks every operational period
    # and re-queries every JuMP value, which is the dominant cost here.
    primary = _write_csv_table(joinpath(output_dir, first(filenames)), header, write_rows)
    for filename in Iterators.drop(filenames, 1)
        cp(primary, joinpath(output_dir, filename); force = true)
    end
    return output_dir
end

function write_natural_gas_csvs(
    output_dir::AbstractString,
    emp::JuMP.Model,
    sets,
    par::EmpireParams,
    periods::TimeStructure,
)
    terminal_import = emp[:ngTerminalImport]
    transmission = emp[:ngTransmission]
    for_power = emp[:ngForPower]
    storage = emp[:ngStorageOperational]
    charge = emp[:ngStorageCharge]
    discharge = emp[:ngStorageDischarge]
    transport_met = emp[:transportNaturalGasDemandMet]
    transport_shed = emp[:transportNaturalGasDemandShed]
    gas = par.NaturalGas
    common = [
        "Period",
        "Scenario",
        "WeatherScenario",
        "GasScenario",
        "Season",
        "Hour",
    ]

    terminal_header = vcat(
        ["Node", "Terminal"],
        common,
        ["TerminalImport_ton", "TerminalCapacity_ton_per_h", "TerminalCost_EUR_per_ton"],
    )
    write_terminal_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for (node, terminal) in natural_gas_terminal_nodes(sets)
                _write_csv_row(
                    io,
                    [
                        node,
                        terminal,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        _solution_value(
                            terminal_import[node, terminal, operational_period],
                        ),
                        natural_gas_terminal_capacity(par, node, terminal, period),
                        natural_gas_terminal_cost(
                            par,
                            node,
                            terminal,
                            period,
                            gas_scenario,
                        ),
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        ("ngTerminalImport.csv", "results_natural_gas_terminals.csv"),
        terminal_header,
        write_terminal_rows,
    )

    pipeline_header = vcat(
        ["FromNode", "ToNode"],
        common,
        ["PipelineFlow_ton", "PipelineCapacity_ton_per_h", "ElectricityUse_MWh"],
    )
    write_pipeline_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for (from, to) in natural_gas_links(sets)
                flow = _solution_value(transmission[from, to, operational_period])
                _write_csv_row(
                    io,
                    [
                        from,
                        to,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        flow,
                        natural_gas_pipeline_capacity(par, from, to),
                        gas.pipelinePowerDemandPerTon * flow,
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        ("ngTransmission.csv", "results_natural_gas_pipeline.csv"),
        pipeline_header,
        write_pipeline_rows,
    )

    power_header = vcat(
        ["Node", "Generator"],
        common,
        ["NaturalGasForPower_ton", "Generation_MWh", "Efficiency"],
    )
    write_power_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for (node, generator) in _natural_gas_node_generators(sets)
                _write_csv_row(
                    io,
                    [
                        node,
                        generator,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        _solution_value(for_power[node, generator, operational_period]),
                        _solution_value(
                            emp[:genOperational][node, generator, operational_period],
                        ),
                        par.genEfficiency[generator][operational_period],
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        ("ngForPower.csv", "results_natural_gas_for_power.csv"),
        power_header,
        write_power_rows,
    )

    storage_header = vcat(
        ["Node"],
        common,
        [
            "StorageLevel_ton",
            "StorageCharge_ton",
            "StorageDischarge_ton",
            "StorageCapacity_ton",
        ],
    )
    write_storage_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for node in natural_gas_nodes(sets)
                _write_csv_row(
                    io,
                    [
                        node,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        _solution_value(storage[node, operational_period]),
                        _solution_value(charge[node, operational_period]),
                        _solution_value(discharge[node, operational_period]),
                        natural_gas_storage_capacity(par, node),
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        ("ngStorage.csv", "results_natural_gas_storage.csv"),
        storage_header,
        write_storage_rows,
    )

    transport_header = vcat(
        ["Node"],
        common,
        ["DemandMet_ton", "DemandShed_ton", "AnnualDemand_MWh"],
    )
    write_transport_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for node in _natural_gas_onshore_nodes(sets)
                _write_csv_row(
                    io,
                    [
                        node,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        _solution_value(transport_met[node, operational_period]),
                        _solution_value(transport_shed[node, operational_period]),
                        natural_gas_transport_demand(par, node, period),
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        (
            "transportNaturalGas.csv",
            "results_transport_naturalGas_operations.csv",
        ),
        transport_header,
        write_transport_rows,
    )

    balance_header = vcat(
        ["Node"],
        common,
        [
            "TerminalImport_ton",
            "PipelineIn_ton",
            "PipelineOut_ton",
            "NaturalGasForPower_ton",
            "StorageCharge_ton",
            "StorageDischarge_ton",
            "TransportDemandMet_ton",
            "BalanceResidual_ton",
        ],
    )
    write_balance_rows = function (io)
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            for node in natural_gas_nodes(sets)
                imports = sum(
                    _value_or_zero(
                        terminal_import,
                        node,
                        terminal,
                        operational_period,
                    )
                    for terminal in natural_gas_terminals(sets, node);
                    init = 0.0,
                )
                pipeline_in = sum(
                    _value_or_zero(transmission, source, node, operational_period)
                    for source in natural_gas_incoming(sets, node);
                    init = 0.0,
                )
                pipeline_out = sum(
                    _value_or_zero(
                        transmission,
                        node,
                        destination,
                        operational_period,
                    )
                    for destination in natural_gas_outgoing(sets, node);
                    init = 0.0,
                )
                power = sum(
                    _value_or_zero(for_power, node, generator, operational_period)
                    for generator in generators(sets, node)
                    if generator in natural_gas_generators(sets);
                    init = 0.0,
                )
                storage_charge = _solution_value(charge[node, operational_period])
                storage_discharge =
                    gas.storageDischargeEfficiency *
                    _solution_value(discharge[node, operational_period])
                transport = node in natural_gas_onshore_nodes(sets) ?
                            _solution_value(
                    transport_met[node, operational_period],
                ) : 0.0
                residual =
                    imports + pipeline_in + storage_discharge -
                    power - pipeline_out - storage_charge - transport
                _write_csv_row(
                    io,
                    [
                        node,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        imports,
                        pipeline_in,
                        pipeline_out,
                        power,
                        storage_charge,
                        storage_discharge,
                        transport,
                        residual,
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
    _write_natural_gas_table(
        output_dir,
        ("naturalGasBalance.csv", "results_natural_gas_balance.csv"),
        balance_header,
        write_balance_rows,
    )

    JuMP.has_duals(emp) &&
        write_natural_gas_dual_csvs(output_dir, emp, sets, par, periods)
    return output_dir
end

function write_natural_gas_dual_csvs(
    output_dir::AbstractString,
    emp::JuMP.Model,
    sets,
    par::EmpireParams,
    periods::TimeStructure,
)
    discounter = Discounter(discount_rate(par), 1, periods)
    period_type = eltype(periods)
    predecessor_type = Tuple{Union{Nothing, period_type}, period_type}
    storage_predecessor = Dict{period_type, predecessor_type}()
    for strategic_period in strat_periods(periods)
        for predecessor in withprev(strategic_period)
            storage_predecessor[last(predecessor)] = predecessor
        end
    end
    header = [
        "Node",
        "Period",
        "Scenario",
        "WeatherScenario",
        "GasScenario",
        "Season",
        "Hour",
        "GasPrice_EUR_per_ton",
        "StorageBalanceDual_EUR_per_ton",
    ]
    return _write_csv_table(
        joinpath(output_dir, "naturalGasOperationalDuals.csv"),
        header,
    ) do io
        _foreach_natural_gas_operational_context(
            (
                period,
                strategic_period,
                scenario,
                weather,
                gas_scenario,
                representative,
                season,
                hour,
                operational_period,
            ) -> begin
            weight =
                objective_weight(operational_period, discounter; type = "avg_year")
            for node in natural_gas_nodes(sets)
                gas_price =
                    _dual_or_nan(
                    emp[:natural_gas_flow_balance],
                    node,
                    operational_period,
                ) / weight
                # The storage balance row is built scaled by NATURAL_GAS_ROW_SCALE
                # for conditioning, which inflates its dual by the reciprocal.
                # Undo that so the published value stays in EUR/ton. The flow
                # balance above is unscaled and needs no such correction.
                storage_dual =
                    NATURAL_GAS_ROW_SCALE * _dual_or_nan(
                    emp[:natural_gas_storage_balance],
                    node,
                    strategic_period,
                    storage_predecessor[operational_period],
                ) / weight
                _write_csv_row(
                    io,
                    [
                        node,
                        period,
                        scenario,
                        weather,
                        gas_scenario,
                        season,
                        hour,
                        gas_price,
                        storage_dual,
                    ],
                )
            end
            end,
            par,
            periods,
        )
    end
end

const SCENARIO_ARTIFACT_CONFIG_KEYS = (
    "use_scenario_generation",
    "use_fixed_sample",
    "number_of_scenarios",
    "natural_gas",
    "number_of_gas_scenarios",
    "regular_seasons",
    "n_peak_seasons",
    "len_peak_season",
    "length_of_regular_season",
    "time_format",
    "filter_make",
    "filter_use",
    "n_cluster",
    "copula_clusters_make",
    "copula_clusters_use",
    "copulas_to_use",
)

function _insert_if_not_nothing!(dict, key::AbstractString, value)
    value === nothing && return dict
    dict[key] = value
    return dict
end

function _is_same_or_child_path(path::AbstractString, parent::AbstractString)
    relative = relpath(abspath(path), abspath(parent))
    escapes_parent = relative == ".." || startswith(relative, "../") || startswith(relative, "..\\")
    return relative == "." || !escapes_parent
end

"""
    write_scenario_artifacts(result_dir, data_folder, config; kwargs...)

Archive the scenario sampling key, optional scenario filter or copula clusters,
and run metadata under `joinpath(result_dir, "Input")` when scenario generation
is enabled.

When `data_folder` is already staged under `joinpath(result_dir, "Input")`, the
existing staged `ScenarioData/sampling_key.csv` is referenced directly instead
of duplicated under `Input/ScenarioData`.

The archived `Input/ScenarioData/sampling_key.csv` is enough to replay the
exact sampled scenario tree together with the run config and original dataset.
When filtering is enabled and `filter_result.csv` exists, the exact candidate
catalog is archived beside the sampling key; likewise for
`copula_clusters.csv` when copula clustering is enabled.
Returns the archived sampling-key path, or `nothing` when no sampling key is
available or scenario generation is disabled.
"""
function write_scenario_artifacts(
    result_dir::AbstractString,
    data_folder::AbstractString,
    config;
    config_file = nothing,
    dataset = nothing,
    input_format = nothing,
    seed = nothing,
)
    get(config, "use_scenario_generation", true) || return nothing

    source_key = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
    isfile(source_key) || return nothing

    input_dir = joinpath(result_dir, "Input")
    is_staged_input = _is_same_or_child_path(data_folder, input_dir)
    # When the dataset is already staged under `Input/`, every artifact is referenced
    # where it stands rather than copied beside itself. `scenario_dir` is bound outside
    # the branch because the filter and copula archiving below need it in both cases.
    scenario_dir = joinpath(input_dir, "ScenarioData")
    is_staged_input || mkpath(scenario_dir)

    archived_key = if is_staged_input
        source_key
    else
        copied_key = joinpath(scenario_dir, "sampling_key.csv")
        cp(source_key, copied_key; force = true)
        copied_key
    end

    source_filter = joinpath(data_folder, "ScenarioData", "filter_result.csv")
    filter_enabled =
        get(config, "filter_make", false) || get(config, "filter_use", false)
    archived_filter = if filter_enabled && isfile(source_filter)
        if is_staged_input
            source_filter
        else
            destination = joinpath(scenario_dir, "filter_result.csv")
            cp(source_filter, destination; force = true)
            destination
        end
    else
        nothing
    end

    source_copula = _copula_cluster_path(data_folder)
    copula_enabled =
        get(config, "copula_clusters_make", false) || get(config, "copula_clusters_use", false)
    archived_copula = if copula_enabled && isfile(source_copula)
        if is_staged_input
            source_copula
        else
            destination = joinpath(scenario_dir, "copula_clusters.csv")
            cp(source_copula, destination; force = true)
            destination
        end
    else
        nothing
    end

    if config_file !== nothing && isfile(config_file)
        archived_config = joinpath(input_dir, "config.yaml")
        if abspath(config_file) != abspath(archived_config)
            cp(config_file, archived_config; force = true)
        end
    end

    generated_files = Dict(
        filename => isfile(joinpath(data_folder, "ScenarioData", filename))
        for filename in ("sloadRaw.csv", "maxRegHydroGenRaw.csv", "genCapAvailStochRaw.csv")
    )

    metadata = Dict{String, Any}(
        "data_folder" => data_folder,
        "scenario_data_folder" => joinpath(data_folder, "ScenarioData"),
        "source_sampling_key" => source_key,
        "archived_sampling_key" => relpath(archived_key, result_dir),
        "staged_input" => is_staged_input,
        "generated_scenario_files_present" => generated_files,
    )
    _insert_if_not_nothing!(metadata, "dataset", dataset)
    _insert_if_not_nothing!(metadata, "config_file", config_file)
    _insert_if_not_nothing!(metadata, "input_format", input_format === nothing ? nothing : string(input_format))
    _insert_if_not_nothing!(metadata, "seed", seed)
    if archived_filter !== nothing
        metadata["source_filter_result"] = source_filter
        metadata["archived_filter_result"] = relpath(archived_filter, result_dir)
    end
    if archived_copula !== nothing
        metadata["source_copula_clusters"] = source_copula
        metadata["archived_copula_clusters"] = relpath(archived_copula, result_dir)
    end
    for key in SCENARIO_ARTIFACT_CONFIG_KEYS
        haskey(config, key) && (metadata[key] = config[key])
    end
    YAML.write_file(joinpath(input_dir, "scenario_metadata.yaml"), metadata)

    return archived_key
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
    trans_rows = NamedTuple{(:FromNode, :ToNode, :Period, :transmissionInvCap), Tuple{String, String, Int, Float64}}[]
    trans_cap_rows = NamedTuple{(:FromNode, :ToNode, :Period, :transmissionInstalledCap), Tuple{String, String, Int, Float64}}[]
    for (m, n) in bidir_arcs(sets), (period_index, sp) in strategic_periods
        push!(trans_rows, (FromNode = m, ToNode = n, Period = period_index, transmissionInvCap = _solution_value(trans_inv[m, n, sp])))
        push!(trans_cap_rows, (FromNode = m, ToNode = n, Period = period_index, transmissionInstalledCap = _solution_value(trans_cap[m, n, sp])))
    end
    _write_csv_rows(joinpath(output_dir, "transmissionInvCap.csv"), trans_rows)
    _write_csv_rows(joinpath(output_dir, "transmissionInstalledCap.csv"), trans_cap_rows)

    offshore_conv_inv = emp[:offshoreConvInvCap]
    offshore_conv_cap = emp[:offshoreConvInstalledCap]
    offshore_conv_inv_rows = NamedTuple{
        (:Node, :Period, :offshoreConvInvCap),
        Tuple{String, Int, Float64},
    }[]
    offshore_conv_cap_rows = NamedTuple{
        (:Node, :Period, :offshoreConvInstalledCap),
        Tuple{String, Int, Float64},
    }[]
    for node in offshore_energy_hubs(sets), (period_index, sp) in strategic_periods
        push!(offshore_conv_inv_rows, (
            Node = node,
            Period = period_index,
            offshoreConvInvCap = _solution_value(offshore_conv_inv[node, sp]),
        ))
        push!(offshore_conv_cap_rows, (
            Node = node,
            Period = period_index,
            offshoreConvInstalledCap = _solution_value(offshore_conv_cap[node, sp]),
        ))
    end
    _write_csv_rows(joinpath(output_dir, "offshoreConvInvCap.csv"), offshore_conv_inv_rows)
    _write_csv_rows(
        joinpath(output_dir, "offshoreConvInstalledCap.csv"),
        offshore_conv_cap_rows,
    )

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
    # Streamed rather than accumulated: these are the largest tables the port
    # writes (genOperational reaches 13,048,560 rows on full_model_int), and
    # building them as Vector{NamedTuple} before handing them to CSV.write held
    # roughly a gigabyte per table with several written back to back.
    gen_op = emp[:genOperational]
    _stream_csv_table(
        joinpath(output_dir, "genOperational.csv"),
        ["Node", "Generator", "Period", "Scenario", "Season", "Hour", "genOperational"],
    ) do row
        _foreach_operational_index(par, periods) do period, scenario, season, hour, t
            for (n, g) in node_generators(sets)
                row([n, g, period, scenario, season, hour, _solution_value(gen_op[n, g, t])])
            end
        end
    end

    trans_op = emp[:transmissionOperational]
    _stream_csv_table(
        joinpath(output_dir, "transmissionOperational.csv"),
        ["FromNode", "ToNode", "Period", "Scenario", "Season", "Hour", "transmissionOperational"],
    ) do row
        _foreach_operational_index(par, periods) do period, scenario, season, hour, t
            for (m, n) in arcs(sets)
                row([m, n, period, scenario, season, hour, _solution_value(trans_op[m, n, t])])
            end
        end
    end

    # One pass per file keeps memory flat; the three storage tables share an
    # index walk but not a buffer.
    for (filename, column, container) in (
        ("storCharge.csv", "storCharge", emp[:storCharge]),
        ("storDischarge.csv", "storDischarge", emp[:storDischarge]),
        ("storageOperational.csv", "storageOperational", emp[:storOperational]),
    )
        _stream_csv_table(
            joinpath(output_dir, filename),
            ["Node", "Storage", "Period", "Scenario", "Season", "Hour", column],
        ) do row
            _foreach_operational_index(par, periods) do period, scenario, season, hour, t
                for (n, s) in node_storages(sets)
                    row([n, s, period, scenario, season, hour, _solution_value(container[n, s, t])])
                end
            end
        end
    end

    load_shed = emp[:loadShed]
    _stream_csv_table(
        joinpath(output_dir, "loadShed.csv"),
        ["Node", "Period", "Scenario", "Season", "Hour", "loadShed"],
    ) do row
        _foreach_operational_index(par, periods) do period, scenario, season, hour, t
            for n in nodes(sets)
                row([n, period, scenario, season, hour, _solution_value(load_shed[n, t])])
            end
        end
    end

    return output_dir
end

function write_report_csvs(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure)
    labels = _period_labels(periods)

    write_objective_csv(output_dir, emp)
    write_cost_diagnostic_csvs(output_dir, sets, par, periods)
    write_generator_report_csv(output_dir, emp, sets, par, periods, labels)
    write_storage_report_csv(output_dir, emp, sets, par, periods, labels)
    write_transmission_report_csv(output_dir, emp, sets, par, periods, labels)
    write_transmission_operational_report_csv(output_dir, emp, sets, par, periods, labels)
    write_operational_report_csv(output_dir, emp, sets, par, periods, labels)
    write_curtailment_report_csvs(output_dir, emp, sets, par, periods, labels)
    write_europe_plot_report_csv(output_dir, emp, sets, par, periods, labels)
    write_europe_summary_report_csv(output_dir, emp, sets, par, periods, labels)

    return output_dir
end

function write_objective_csv(output_dir::AbstractString, emp::JuMP.Model)
    return _write_csv_table(joinpath(output_dir, "results_objective.csv"), ["Objective function value:$(_objective_value_or_nan(emp))"]) do io
        nothing
    end
end

function write_cost_diagnostic_csvs(output_dir::AbstractString, sets, par::EmpireParams, periods::TimeStructure)
    strategic_periods = _strategic_indices(periods)
    _write_csv_table(joinpath(output_dir, "marginal_costs.csv"), ["Generator", "Period", "MarginalCost_EurperMWh"]) do io
        for g in generators(sets), (period_index, sp) in strategic_periods
            _write_csv_row(io, [g, period_index, gen_marginal_cost(par, g, sp)])
        end
    end
    _write_csv_table(joinpath(output_dir, "investment_costs.csv"), ["Generator", "Period", "InvestmentCost_EurperMW"]) do io
        for g in generators(sets), (period_index, sp) in strategic_periods
            _write_csv_row(io, [g, period_index, gen_invest_cost(par, g, sp)])
        end
    end
    return output_dir
end

function _weighted_generation(emp::JuMP.Model, par::EmpireParams, node::AbstractString, generator::AbstractString, sp, scenario_index = nothing)
    gen_op = emp[:genOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * probability(t) * _value_or_zero(gen_op, node, generator, t)
            end
        end
    end
    return total
end

function _weighted_storage_discharge(emp::JuMP.Model, par::EmpireParams, node::AbstractString, storage::AbstractString, sp, scenario_index = nothing)
    stor_discharge = emp[:storDischarge]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * probability(t) * _value_or_zero(stor_discharge, node, storage, t)
            end
        end
    end
    return total
end

function _weighted_storage_losses(emp::JuMP.Model, par::EmpireParams, node::AbstractString, storage::AbstractString, sp, scenario_index = nothing)
    stor_charge = emp[:storCharge]
    stor_discharge = emp[:storDischarge]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * probability(t) * (
                    (1 - discharge_eff(par, storage)) * _value_or_zero(stor_discharge, node, storage, t) +
                    (1 - charge_eff(par, storage)) * _value_or_zero(stor_charge, node, storage, t)
                )
            end
        end
    end
    return total
end

function _weighted_transmission_volume(emp::JuMP.Model, par::EmpireParams, from::AbstractString, to::AbstractString, sp, scenario_index = nothing)
    trans_op = emp[:transmissionOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                weight = multiple_strat(sp, t) * probability(t)
                total += weight * (
                    _value_or_zero(trans_op, from, to, t) +
                    _value_or_zero(trans_op, to, from, t)
                )
            end
        end
    end
    return total
end

function _weighted_transmission_losses(emp::JuMP.Model, par::EmpireParams, from::AbstractString, to::AbstractString, sp, scenario_index = nothing)
    trans_op = emp[:transmissionOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                weight = multiple_strat(sp, t) * probability(t)
                total += weight * (
                    (1 - line_eff(par, from, to)) * _value_or_zero(trans_op, from, to, t) +
                    (1 - line_eff(par, to, from)) * _value_or_zero(trans_op, to, from, t)
                )
            end
        end
    end
    return total
end

function _weighted_curtailment(emp::JuMP.Model, par::EmpireParams, node::AbstractString, generator::AbstractString, sp, scenario_index = nothing)
    gen_cap = emp[:genInstalledCap]
    gen_op = emp[:genOperational]
    installed = _value_or_zero(gen_cap, node, generator, sp)
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            scenario_index === nothing || sc_index == scenario_index || continue
            for t in sc
                available = _gen_capacity_availability(par, node, generator, t) * installed
                total += multiple_strat(sp, t) * probability(t) *
                    (available - _value_or_zero(gen_op, node, generator, t))
            end
        end
    end
    return total
end

function _scenario_generation(emp::JuMP.Model, par::EmpireParams, node::AbstractString, generator::AbstractString, sp, scenario_index::Integer)
    gen_op = emp[:genOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * _value_or_zero(gen_op, node, generator, t)
            end
        end
    end
    return total
end

function _scenario_storage_losses(emp::JuMP.Model, par::EmpireParams, node::AbstractString, storage::AbstractString, sp, scenario_index::Integer)
    stor_charge = emp[:storCharge]
    stor_discharge = emp[:storDischarge]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * (
                    (1 - discharge_eff(par, storage)) * _value_or_zero(stor_discharge, node, storage, t) +
                    (1 - charge_eff(par, storage)) * _value_or_zero(stor_charge, node, storage, t)
                )
            end
        end
    end
    return total
end

function _scenario_transmission_losses(emp::JuMP.Model, par::EmpireParams, from::AbstractString, to::AbstractString, sp, scenario_index::Integer)
    trans_op = emp[:transmissionOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            sc_index == scenario_index || continue
            for t in sc
                total += multiple_strat(sp, t) * (
                    (1 - line_eff(par, from, to)) * _value_or_zero(trans_op, from, to, t) +
                    (1 - line_eff(par, to, from)) * _value_or_zero(trans_op, to, from, t)
                )
            end
        end
    end
    return total
end

function _scenario_curtailment(emp::JuMP.Model, par::EmpireParams, node::AbstractString, generator::AbstractString, sp, scenario_index::Integer)
    gen_cap = emp[:genInstalledCap]
    gen_op = emp[:genOperational]
    installed = _value_or_zero(gen_cap, node, generator, sp)
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            sc_index == scenario_index || continue
            for t in sc
                available = _gen_capacity_availability(par, node, generator, t) * installed
                total += multiple_strat(sp, t) *
                    (available - _value_or_zero(gen_op, node, generator, t))
            end
        end
    end
    return total
end

function _annual_emissions(emp::JuMP.Model, sets, par::EmpireParams, sp, scenario_index::Integer)
    gen_op = emp[:genOperational]
    total = 0.0
    for rp in repr_periods(sp)
        for (sc_index, sc) in enumerate(opscenarios(rp))
            sc_index == scenario_index || continue
            for t in sc, (n, g) in node_generators(sets)
                total += multiple_strat(sp, t) *
                    _value_or_zero(gen_op, n, g, t) *
                    co2_content(par, g) *
                    (3.6 / _gen_efficiency(par, g, sp))
            end
        end
    end
    return total
end

function _annual_generation(emp::JuMP.Model, sets, par::EmpireParams, sp, scenario_index::Integer)
    return sum(
        _scenario_generation(emp, par, n, g, sp, scenario_index)
        for (n, g) in node_generators(sets);
        init = 0.0,
    )
end

function write_generator_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    gen_inv = emp[:genInvCap]
    gen_cap = emp[:genInstalledCap]
    header = [
        "Node",
        "GeneratorType",
        "Period",
        "genInvCap_MW",
        "genInstalledCap_MW",
        "genExpectedCapacityFactor",
        "DiscountedInvestmentCost_Euro",
        "genExpectedAnnualProduction_GWh",
    ]
    return _write_csv_table(joinpath(output_dir, "results_output_gen.csv"), header) do io
        for (n, g) in node_generators(sets), (period_index, sp) in _strategic_indices(periods)
            installed = _value_or_zero(gen_cap, n, g, sp)
            weighted_gen = _weighted_generation(emp, par, n, g, sp)
            capacity_factor = installed == 0 ? 0.0 : weighted_gen / (installed * 8760)
            inv_cap = _value_or_zero(gen_inv, n, g, sp)
            discounted_cost = _discount_multiplier(par, periods, sp) * inv_cap * gen_invest_cost(par, g, sp)
            _write_csv_row(io, [
                n,
                g,
                _period_label(labels, period_index),
                inv_cap,
                installed,
                capacity_factor,
                discounted_cost,
                weighted_gen / 1000,
            ])
        end
    end
end

function write_storage_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    stor_pw_inv = emp[:storPWInvCap]
    stor_pw_cap = emp[:storPWInstalledCap]
    stor_en_inv = emp[:storENInvCap]
    stor_en_cap = emp[:storENInstalledCap]
    header = [
        "Node",
        "StorageType",
        "Period",
        "storPWInvCap_MW",
        "storPWInstalledCap_MW",
        "storENInvCap_MWh",
        "storENInstalledCap_MWh",
        "DiscountedInvestmentCostPWEN_EuroPerMWMWh",
        "ExpectedAnnualDischargeVolume_GWh",
        "ExpectedAnnualLossesChargeDischarge_GWh",
    ]
    return _write_csv_table(joinpath(output_dir, "results_output_stor.csv"), header) do io
        for (n, s) in node_storages(sets), (period_index, sp) in _strategic_indices(periods)
            pw_inv = _value_or_zero(stor_pw_inv, n, s, sp)
            en_inv = _value_or_zero(stor_en_inv, n, s, sp)
            discounted_cost = _discount_multiplier(par, periods, sp) * (
                pw_inv * stor_pw_invest_cost(par, s, sp) +
                en_inv * stor_en_invest_cost(par, s, sp)
            )
            _write_csv_row(io, [
                n,
                s,
                _period_label(labels, period_index),
                pw_inv,
                _value_or_zero(stor_pw_cap, n, s, sp),
                en_inv,
                _value_or_zero(stor_en_cap, n, s, sp),
                discounted_cost,
                _weighted_storage_discharge(emp, par, n, s, sp) / 1000,
                _weighted_storage_losses(emp, par, n, s, sp) / 1000,
            ])
        end
    end
end

function write_transmission_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    trans_inv = emp[:transmissionInvCap]
    trans_cap = emp[:transmissionInstalledCap]
    header = [
        "BetweenNode",
        "AndNode",
        "Period",
        "transmissionInvCap_MW",
        "transmissionInstalledCap_MW",
        "DiscountedInvestmentCost_Euro",
        "transmissionExpectedAnnualVolume_GWh",
        "ExpectedAnnualLosses_GWh",
    ]
    return _write_csv_table(joinpath(output_dir, "results_output_transmission.csv"), header) do io
        for (m, n) in bidir_arcs(sets), (period_index, sp) in _strategic_indices(periods)
            inv_cap = _value_or_zero(trans_inv, m, n, sp)
            discounted_cost = _discount_multiplier(par, periods, sp) * inv_cap * trans_invest_cost(par, m, n, sp)
            _write_csv_row(io, [
                m,
                n,
                _period_label(labels, period_index),
                inv_cap,
                _value_or_zero(trans_cap, m, n, sp),
                discounted_cost,
                _weighted_transmission_volume(emp, par, m, n, sp) / 1000,
                _weighted_transmission_losses(emp, par, m, n, sp) / 1000,
            ])
        end
    end
end

function write_transmission_operational_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    trans_op = emp[:transmissionOperational]
    header = ["FromNode", "ToNode", "Period", "Season", "Scenario", "Hour", "TransmissionReceived_MW", "Losses_MW"]
    return _write_csv_table(joinpath(output_dir, "results_output_transmission_operational.csv"), header) do io
        _foreach_operational_context(par, periods) do period_index, sp, scenario_index, _, season, hour, t
            for (m, n) in arcs(sets)
                sent = _value_or_zero(trans_op, m, n, t)
                _write_csv_row(io, [
                    m,
                    n,
                    _period_label(labels, period_index),
                    season,
                    _scenario_label(scenario_index),
                    hour,
                    line_eff(par, m, n) * sent,
                    (1 - line_eff(par, m, n)) * sent,
                ])
            end
        end
    end
end

function write_operational_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    gen_op = emp[:genOperational]
    stor_charge = emp[:storCharge]
    stor_discharge = emp[:storDischarge]
    stor_op = emp[:storOperational]
    trans_op = emp[:transmissionOperational]
    load_shed = emp[:loadShed]
    discounter = Discounter(discount_rate(par), 1, periods)
    generator_columns = ["$(g)_MW" for g in generators(sets)]
    header = vcat(
        ["Node", "Period", "Scenario", "Season", "Hour", "AllGen_MW", "Load_MW", "Net_load_MW"],
        generator_columns,
        [
            "storCharge_MW",
            "storDischarge_MW",
            "storEnergyLevel_MWh",
            "LossesChargeDischargeBleed_MW",
            "FlowOut_MW",
            "FlowIn_MW",
            "LossesFlowIn_MW",
            "LoadShed_MW",
            "Price_EURperMWh",
            "AvgCO2_kgCO2perMWh",
        ],
    )
    return _write_csv_table(joinpath(output_dir, "results_output_Operational.csv"), header) do io
        _foreach_operational_context(par, periods) do period_index, sp, scenario_index, _, season, hour, t
            for n in nodes(sets)
                all_gen = sum(_value_or_zero(gen_op, n, g, t) for g in generators(sets, n); init = 0.0)
                shed = _value_or_zero(load_shed, n, t)
                storage_net = sum(
                    _value_or_zero(stor_charge, n, s, t) - discharge_eff(par, s) * _value_or_zero(stor_discharge, n, s, t)
                    for s in storages(sets, n);
                    init = 0.0,
                )
                transmission_net = sum(_value_or_zero(trans_op, n, to, t) for to in _outgoing_nodes(sets, n); init = 0.0) -
                    sum(line_eff(par, from, n) * _value_or_zero(trans_op, from, n, t) for from in _incoming_nodes(sets, n); init = 0.0)
                net_load = -(sload(par, n, t) - shed + storage_net + transmission_net)
                gen_values = [_value_or_zero(gen_op, n, g, t) for g in generators(sets)]
                storage_charge = sum(-_value_or_zero(stor_charge, n, s, t) for s in storages(sets, n); init = 0.0)
                storage_discharge = sum(_value_or_zero(stor_discharge, n, s, t) for s in storages(sets, n); init = 0.0)
                storage_level = sum(_value_or_zero(stor_op, n, s, t) for s in storages(sets, n); init = 0.0)
                storage_losses = sum(
                    -(1 - discharge_eff(par, s)) * _value_or_zero(stor_discharge, n, s, t) -
                    (1 - charge_eff(par, s)) * _value_or_zero(stor_charge, n, s, t) -
                    (1 - bleed_eff(par, s)) * _value_or_zero(stor_op, n, s, t)
                    for s in storages(sets, n);
                    init = 0.0,
                )
                flow_out = sum(-_value_or_zero(trans_op, n, to, t) for to in _outgoing_nodes(sets, n); init = 0.0)
                flow_in = sum(_value_or_zero(trans_op, from, n, t) for from in _incoming_nodes(sets, n); init = 0.0)
                losses_flow_in = sum(
                    -(1 - line_eff(par, from, n)) * _value_or_zero(trans_op, from, n, t)
                    for from in _incoming_nodes(sets, n);
                    init = 0.0,
                )
                co2_weighted_gen = sum(
                    _value_or_zero(gen_op, n, g, t) * co2_content(par, g) * (3.6 / _gen_efficiency(par, g, sp))
                    for g in generators(sets, n);
                    init = 0.0,
                )
                avg_co2 = all_gen == 0 ? 0.0 : co2_weighted_gen / all_gen
                _write_csv_row(io, vcat(Any[
                    n,
                    _period_label(labels, period_index),
                    _scenario_label(scenario_index),
                    season,
                    hour,
                    all_gen,
                    -sload(par, n, t),
                    net_load,
                ], gen_values, Any[
                    storage_charge,
                    storage_discharge,
                    storage_level,
                    storage_losses,
                    flow_out,
                    flow_in,
                    losses_flow_in,
                    shed,
                    _flow_balance_price(emp, n, sp, t, discounter),
                    avg_co2,
                ]))
            end
        end
    end
end

function write_curtailment_report_csvs(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    gen_cap = emp[:genInstalledCap]
    gen_op = emp[:genOperational]
    res_pairs = [(n, g) for (n, g) in node_generators(sets) if _is_res_generator(sets, g)]
    _write_csv_table(
        joinpath(output_dir, "results_output_curtailed_operational.csv"),
        ["Node", "Period", "Scenario", "Season", "Hour", "RESGeneratorType", "Curtailment_MWh"],
    ) do io
        _foreach_operational_context(par, periods) do period_index, sp, scenario_index, _, season, hour, t
            for (n, g) in res_pairs
                installed = _value_or_zero(gen_cap, n, g, sp)
                curtailment = multiple_strat(sp, t) * probability(t) *
                    (_gen_capacity_availability(par, n, g, t) * installed - _value_or_zero(gen_op, n, g, t))
                _write_csv_row(io, [
                    n,
                    _period_label(labels, period_index),
                    _scenario_label(scenario_index),
                    season,
                    hour,
                    g,
                    curtailment,
                ])
            end
        end
    end
    _write_csv_table(
        joinpath(output_dir, "results_output_curtailed_prod.csv"),
        ["Node", "RESGeneratorType", "Period", "ExpectedAnnualCurtailment_GWh"],
    ) do io
        for (n, g) in res_pairs, (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, [n, g, _period_label(labels, period_index), _weighted_curtailment(emp, par, n, g, sp) / 1000])
        end
    end
    return output_dir
end

function write_europe_plot_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    gen_cap = emp[:genInstalledCap]
    stor_pw_cap = emp[:storPWInstalledCap]
    stor_en_cap = emp[:storENInstalledCap]
    return _write_csv_table(joinpath(output_dir, "results_output_EuropePlot.csv"), ["Period", "genInstalledCap_MW"]) do io
        _write_csv_row(io, vcat([""], generators(sets)))
        _write_csv_row(io, vcat(Any["Initial"], [
            sum(gencap_init(par, n, g, first(strat_periods(periods))) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0)
            for g in generators(sets)
        ]))
        for (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, vcat(Any[_period_label(labels, period_index)], [
                sum(_value_or_zero(gen_cap, n, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0)
                for g in generators(sets)
            ]))
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["Period", "genExpectedAnnualProduction_GWh"])
        _write_csv_row(io, vcat([""], generators(sets)))
        for (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, vcat(Any[_period_label(labels, period_index)], [
                sum(_weighted_generation(emp, par, n, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0) / 1000
                for g in generators(sets)
            ]))
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["Period", "storPWInstalledCap_MW"])
        _write_csv_row(io, vcat([""], storages(sets)))
        for (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, vcat(Any[_period_label(labels, period_index)], [
                sum(_value_or_zero(stor_pw_cap, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0)
                for s in storages(sets)
            ]))
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["Period", "storENInstalledCap_MWh"])
        _write_csv_row(io, vcat([""], storages(sets)))
        for (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, vcat(Any[_period_label(labels, period_index)], [
                sum(_value_or_zero(stor_en_cap, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0)
                for s in storages(sets)
            ]))
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["Period", "storExpectedAnnualDischarge_GWh"])
        _write_csv_row(io, vcat([""], storages(sets)))
        for (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, vcat(Any[_period_label(labels, period_index)], [
                sum(_weighted_storage_discharge(emp, par, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0) / 1000
                for s in storages(sets)
            ]))
        end
    end
end

function write_europe_summary_report_csv(output_dir::AbstractString, emp::JuMP.Model, sets, par::EmpireParams, periods::TimeStructure, labels::Vector{String})
    gen_inv = emp[:genInvCap]
    gen_cap = emp[:genInstalledCap]
    stor_pw_inv = emp[:storPWInvCap]
    stor_pw_cap = emp[:storPWInstalledCap]
    stor_en_inv = emp[:storENInvCap]
    stor_en_cap = emp[:storENInstalledCap]
    discounter = Discounter(discount_rate(par), 1, periods)
    header = [
        "Period",
        "Scenario",
        "AnnualCO2emission_Ton",
        "CO2Price_EuroPerTon",
        "CO2Cap_Ton",
        "AnnualGeneration_GWh",
        "AvgCO2factor_TonPerMWh",
        "AvgELPrice_EuroPerMWh",
        "TotAnnualCurtailedRES_GWh",
        "TotAnnualLossesChargeDischarge_GWh",
        "AnnualLossesTransmission_GWh",
    ]
    return _write_csv_table(joinpath(output_dir, "results_output_EuropeSummary.csv"), header) do io
        for (period_index, sp) in _strategic_indices(periods)
            scenario_count = length(opscenarios(first(repr_periods(sp))))
            for scenario_index in 1:scenario_count
                emissions = _annual_emissions(emp, sets, par, sp, scenario_index)
                generation = _annual_generation(emp, sets, par, sp, scenario_index)
                avg_co2 = generation == 0 ? 0.0 : emissions / generation
                prices = Float64[]
                for rp in repr_periods(sp)
                    sc = collect(opscenarios(rp))[scenario_index]
                    for t in sc, n in nodes(sets)
                        push!(prices, _flow_balance_price(emp, n, sp, t, discounter))
                    end
                end
                valid_prices = filter(!isnan, prices)
                avg_price = isempty(valid_prices) ? NaN : sum(valid_prices) / length(valid_prices)
                first_time = first(first(opscenarios(first(repr_periods(sp)))))
                co2_price_value = _emission_price(emp, par, sp, scenario_index, first_time, discounter)
                _write_csv_row(io, [
                    _period_label(labels, period_index),
                    _scenario_label(scenario_index),
                    emissions,
                    co2_price_value,
                    co2_cap(par, sp) === nothing ? 0.0 : co2_cap(par, sp) * 1e6,
                    generation / 1000,
                    avg_co2,
                    avg_price,
                    sum(_scenario_curtailment(emp, par, n, g, sp, scenario_index) for (n, g) in node_generators(sets) if _is_res_generator(sets, g); init = 0.0) / 1000,
                    sum(_scenario_storage_losses(emp, par, n, s, sp, scenario_index) for (n, s) in node_storages(sets); init = 0.0) / 1000,
                    sum(_scenario_transmission_losses(emp, par, m, n, sp, scenario_index) for (m, n) in bidir_arcs(sets); init = 0.0) / 1000,
                ])
            end
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["GeneratorType", "Period", "genInvCap_MW", "genInstalledCap_MW", "TotDiscountedInvestmentCost_Euro", "genExpectedAnnualProduction_GWh"])
        for g in generators(sets), (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, [
                g,
                _period_label(labels, period_index),
                sum(_value_or_zero(gen_inv, n, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0),
                sum(_value_or_zero(gen_cap, n, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0),
                sum(_discount_multiplier(par, periods, sp) * _value_or_zero(gen_inv, n, g, sp) * gen_invest_cost(par, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0),
                sum(_weighted_generation(emp, par, n, g, sp) for n in nodes(sets) if (n, g) in Set(node_generators(sets)); init = 0.0) / 1000,
            ])
        end
        _write_csv_row(io, [""])
        _write_csv_row(io, ["StorageType", "Period", "storPWInvCap_MW", "storPWInstalledCap_MW", "storENInvCap_MWh", "storENInstalledCap_MWh", "TotDiscountedInvestmentCostPWEN_Euro", "ExpectedAnnualDischargeVolume_GWh"])
        for s in storages(sets), (period_index, sp) in _strategic_indices(periods)
            _write_csv_row(io, [
                s,
                _period_label(labels, period_index),
                sum(_value_or_zero(stor_pw_inv, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0),
                sum(_value_or_zero(stor_pw_cap, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0),
                sum(_value_or_zero(stor_en_inv, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0),
                sum(_value_or_zero(stor_en_cap, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0),
                sum(
                    _discount_multiplier(par, periods, sp) * (
                        _value_or_zero(stor_pw_inv, n, s, sp) * stor_pw_invest_cost(par, s, sp) +
                        _value_or_zero(stor_en_inv, n, s, sp) * stor_en_invest_cost(par, s, sp)
                    )
                    for n in nodes(sets) if (n, s) in Set(node_storages(sets));
                    init = 0.0,
                ),
                sum(_weighted_storage_discharge(emp, par, n, s, sp) for n in nodes(sets) if (n, s) in Set(node_storages(sets)); init = 0.0) / 1000,
            ])
        end
    end
end
