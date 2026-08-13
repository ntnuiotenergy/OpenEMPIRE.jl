function create_timestruct(npers, years_period, nseasons, hours_season, npeaks, hours_peak, nscens = 1)

    # Create a representative period for each season and peak day
    # Use OperationalScenarios for multiple scenarios with equal probability
    if nscens > 1
        seasons = [OperationalScenarios([SimpleTimes(hours_season, 1) for sc in 1:nscens]) for _ in 1:nseasons]
        peaks = [OperationalScenarios([SimpleTimes(hours_peak, 1) for sc in 1:nscens]) for _ in 1:npeaks]
    else
        seasons = [SimpleTimes(hours_season, 1) for _ in 1:nseasons]
        peaks = [SimpleTimes(hours_peak, 1) for _ in 1:npeaks]
    end

    peak_hours = hours_peak * npeaks

    # Give each season an equal share of each year outside peak periods
    seasons_share = [(8760 - peak_hours) / (8760 * nseasons) for _ in seasons]

    # Count each modeled peak hour once per year.
    peaks_share = [hours_peak / 8760 for _ in peaks]

    # Create representative periods for each year
    repr_periods = RepresentativePeriods(8760, vcat(seasons_share, peaks_share), vcat(seasons, peaks))

    # Return a two level structure with yearly resolution
    return TwoLevel(npers, years_period, repr_periods; op_per_strat = 8760)
end

_report_progress(::Nothing, message) = nothing

function _report_progress(progress, message)
    progress(message)
    return nothing
end

function create_variables(emp::JuMP.Model, sets, periods::TimeStruct.TimeStructure; progress = nothing)

    # Index sets
    N = nodes(sets)
    G = generators(sets)
    S = storages(sets)

    T = periods
    SP = strat_periods(periods)

    @info "Declaring variables"
    _report_progress(progress, "Declaring JuMP variables")
    # Investments in new generator capacity and tracking installed capacity
    @variable(emp, genInvCap[N, G, SP] >= 0; container = IndexedVarArray)
    @variable(emp, genInstalledCap[N, G, SP] >= 0; container = IndexedVarArray)

    # Investments in new transmission capacity and tracking installed capacity
    @variable(emp, transmissionInvCap[N, N, SP] >= 0; container = IndexedVarArray)
    @variable(emp, transmissionInstalledCap[N, N, SP] >= 0; container = IndexedVarArray)

    # Investment in new storage capacity and tracking installed capacity
    @variable(emp, storPWInvCap[N, S, SP] >= 0; container = IndexedVarArray)
    @variable(emp, storPWInstalledCap[N, S, SP] >= 0; container = IndexedVarArray)
    @variable(emp, storENInvCap[N, S, SP] >= 0; container = IndexedVarArray)
    @variable(emp, storENInstalledCap[N, S, SP] >= 0; container = IndexedVarArray)

    # Operational variables, generation, storage charge/discharge and load shedding
    @variable(emp, genOperational[N, G, T] >= 0; container = IndexedVarArray)
    @variable(emp, transmissionOperational[N, N, T] >= 0; container = IndexedVarArray)
    @variable(emp, storCharge[N, S, T] >= 0; container = IndexedVarArray)
    @variable(emp, storDischarge[N, S, T] >= 0; container = IndexedVarArray)
    @variable(emp, storOperational[N, S, T] >= 0; container = IndexedVarArray)
    @variable(emp, loadShed[N, T] >= 0; container = IndexedVarArray)

    # Insert sparse variables
    @info "Inserting variables into sparse arrays - strategic variables"
    _report_progress(progress, "Indexing strategic variables")
    for (n, g) in node_generators(sets), sp in SP
        unsafe_insertvar!(genInvCap, n, g, sp)
        unsafe_insertvar!(genInstalledCap, n, g, sp)
    end
    for (n, m) in bidir_arcs(sets), sp in SP
        unsafe_insertvar!(transmissionInvCap, n, m, sp)
        unsafe_insertvar!(transmissionInstalledCap, n, m, sp)
    end
    for (n, s) in node_storages(sets), sp in SP
        unsafe_insertvar!(storPWInvCap, n, s, sp)
        unsafe_insertvar!(storENInvCap, n, s, sp)
        unsafe_insertvar!(storPWInstalledCap, n, s, sp)
        unsafe_insertvar!(storENInstalledCap, n, s, sp)
    end
    @info "Inserting variables into sparse arrays - operational variables"
    @info "Total time periods: $(length(T))"
    @info "Generator operational variables: $(length(node_generators(sets)) * length(T))"
    _report_progress(
        progress,
        "Indexing operational variables ($(length(T)) time steps, $(length(node_generators(sets)) * length(T)) generator entries)",
    )
    for (n, g) in node_generators(sets), t in T
        unsafe_insertvar!(genOperational, n, g, t)
    end
    @info "Transmission operational variables: $(length(arcs(sets)) * length(T))"
    _report_progress(progress, "Indexing transmission operational variables ($(length(arcs(sets)) * length(T)) entries)")
    for (n, m) in arcs(sets), t in T
        unsafe_insertvar!(transmissionOperational, n, m, t)
    end
    @info "Storage operational variables: $(length(node_storages(sets)) * length(T))"
    _report_progress(progress, "Indexing storage operational variables ($(length(node_storages(sets)) * length(T)) entries)")
    for (n, s) in node_storages(sets), t in T
        unsafe_insertvar!(storCharge, n, s, t)
        unsafe_insertvar!(storDischarge, n, s, t)
        unsafe_insertvar!(storOperational, n, s, t)
    end
    @info "Load shedding variables: $(length(N) * length(T))"
    _report_progress(progress, "Indexing load-shedding variables ($(length(N) * length(T)) entries)")
    for n in N, t in T
        unsafe_insertvar!(loadShed, n, t)
    end
    return
end

function create_objective(emp::JuMP.Model, sets, par, periods::TimeStructure, discounter::Discounter; progress = nothing)
    @info "Creating objective function"
    _report_progress(progress, "Creating objective function")

    components = objective_component_expressions(emp, sets, par, periods, discounter)

    return @objective(emp, Min, sum(values(components)))
end

# Create all constraints in the model
function create_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure; offshore_transmission_cap::Bool = true, progress = nothing)
    @info "Creating constraints"
    _report_progress(progress, "Creating constraints")

    N = nodes(sets)
    G = generators(sets)
    T = periods

    genOp = emp[:genOperational]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    trOp = emp[:transmissionOperational]
    shed = emp[:loadShed]

    @info "Flow balance constraints: $((length(N)) * length(T))"
    _report_progress(progress, "Creating flow-balance constraints ($(length(N) * length(T)) constraints)")
    @constraint(
        emp,
        flow_balance[n in N, t in T],
        sum(genOp[n, g, t] for g in G) + sum(discharge_eff(par, s) * storDischarge[n, s, t] - storCharge[n, s, t] for s in storages(sets, n)) +
            sum(line_eff(par, m, n) * trOp[m, n, t] for (m, n, t) in SparseVariables.select(trOp, :, n, t)) - sum(trOp[n, :, t]) +
            shed[n, t] == load(par, n, t)
    )

    create_generator_constraints(emp, sets, par, periods; progress)
    create_storage_constraints(emp, sets, par, periods; progress)
    create_transmission_constraints(emp, sets, par, periods; offshore_transmission_cap, progress)
    create_emission_constraints(emp, sets, par, periods; progress)
    return nothing

end

# Calculate the total duration of all strategic periods from spp to sp (inclusive)
# Return Inf if spp < sp
function duration_aggr(sp, spp, strat_periods)
    spp < sp && return Inf
    return sum(duration_strat(p) for p in strat_periods if p >= sp && p < spp; init = 0)
end

function create_generator_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure; progress = nothing)
    @info "Creating generator constraints"
    _report_progress(progress, "Creating generator constraints")
    N = nodes(sets)
    SP = strat_periods(periods)

    genOp = emp[:genOperational]
    genCap = emp[:genInstalledCap]
    genInv = emp[:genInvCap]

    # Generation capacity constraints
    @info " - capacity constraints: $(length(node_generators(sets)) * length(periods))"
    _report_progress(progress, "Creating generator capacity constraints ($(length(node_generators(sets)) * length(periods)) constraints)")
    @constraint(
        emp,
        gen_max_prod[n in N, g in generators(sets, n), sp in SP, t in sp],
        genOp[n, g, t] <= gencap_avail(par, n, g, t) * genCap[n, g, sp]
    )

    # Ramping Constraints (thermal generators only)
    @info " - ramping constraints (thermal generators only)"
    _report_progress(progress, "Creating generator ramping constraints")
    @constraint(
        emp,
        gen_ramping[n in N, g in generators(sets, n), sp in SP, (prev, t) in withprev(sp); !isnothing(prev) && is_thermal(sets, g)],
        genOp[n, g, t] <= genOp[n, g, prev] + rampup_cap(par, g) * genCap[n, g, sp]
    )

    # Generation limit for hydropower plants
    @info " - generation limit constraints for regulated hydropower for each operational scenario"
    _report_progress(progress, "Creating regulated hydropower scenario constraints")
    @constraint(
        emp,
        gen_hydro_limit[n in N, g in generators(sets, n), sc in opscenarios(periods); is_reg_hydro(sets, g)],
        sum(genOp[n, g, t] for t in sc) <= max_hydro_gen(par, n, sc)
    )
    @info " - generation limit constraints for hydropower for each node and strategic period"
    _report_progress(progress, "Creating node hydropower limit constraints")
    @constraint(
        emp,
        gen_hydro_node_limit[n in N, sp in SP; !isnothing(max_hydro_node(par, n))],
        sum(
            multiple_strat(sp, t) * probability(t) * genOp[n, g, t]
            for g in generators(sets, n) if is_hydro(sets, g)
            for t in sp
        ) <= max_hydro_node(par, n)
    )

    # Tracking installed capacity from investments across strategic periods that are within
    # the technology lifetime
    @info " - installed capacity constraints: $(length(node_generators(sets)) * length(SP))"
    _report_progress(progress, "Creating generator installed-capacity tracking constraints ($(length(node_generators(sets)) * length(SP)) constraints)")
    @constraint(
        emp,
        installed_cap_gen[n in N, g in generators(sets, n), sp in SP],
        # An investment in period spp stays installed for lifetime/leap_years periods and retires
        # once `lifetime` years have elapsed. Python (empire.py lifetime_rule_gen) keeps it while
        # i - j <= lifetime/LeapYears - 1, i.e. while elapsed years <= lifetime - leap_years.
        # `duration_aggr` is the elapsed years (spp start -> sp start), so the cutoff must subtract
        # one strategic period; using `<= lifetime` alone over-extends every asset by one period.
        sum(genInv[n, g, spp] for spp in SP if duration_aggr(spp, sp, SP) <= gen_lifetime(par, g) - duration_strat(sp)) +
            gencap_init(par, n, g, sp) == genCap[n, g, sp]
    )

    # Constraints on maximum capacity that can be built and installed for each technology
    @info " - maximum investment constraints: $(length(N) * length(techs(sets)) * length(SP))"
    _report_progress(progress, "Creating generator maximum-investment constraints ($(length(N) * length(techs(sets)) * length(SP)) constraints)")
    @constraint(
        emp,
        max_inv_tech[n in N, tc in techs(sets), sp in SP],
        sum(genInv[n, g, sp] for g in generators_tech(sets, n, tc)) <= max_build_cap(par, n, tc, sp)
    )

    # Constraints on maximum installed capacity for each technology
    @info " - maximum installed capacity constraints: $(length(N) * length(techs(sets)) * length(SP))"
    _report_progress(progress, "Creating generator maximum-installed-capacity constraints ($(length(N) * length(techs(sets)) * length(SP)) constraints)")
    return @constraint(
        emp,
        max_inst_tech[n in N, tc in techs(sets), sp in SP],
        sum(genCap[n, g, sp] for g in generators_tech(sets, n, tc)) <= max_inst_cap(par, n, tc, sp)
    )
end

function create_storage_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure; progress = nothing)
    @info "Creating storage constraints"
    _report_progress(progress, "Creating storage constraints")
    N = nodes(sets)
    SP = strat_periods(periods)

    storOp = emp[:storOperational]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    storCapEn = emp[:storENInstalledCap]
    storCapInvEn = emp[:storENInvCap]
    storCapPow = emp[:storPWInstalledCap]
    storCapInvPow = emp[:storPWInvCap]

    # Storage energy balance constraints
    @info " - energy balance constraints: $(length(node_storages(sets)) * length(periods))"
    _report_progress(progress, "Creating storage energy-balance constraints ($(length(node_storages(sets)) * length(periods)) constraints)")
    @constraint(
        emp,
        storage_bal[n in N, s in storages(sets, n), sp in SP, (prev, t) in withprev(sp)],
        (isnothing(prev) ? storage_init(par, s) * storCapEn[n, s, sp] : bleed_eff(par, s) * storOp[n, s, prev]) +
            charge_eff(par, s) * storCharge[n, s, t] - storDischarge[n, s, t] == storOp[n, s, t]
    )

    # Cyclic condition for storage at the end of each operational scenario
    @info " - cyclic condition constraints"
    _report_progress(progress, "Creating storage cyclic-condition constraints")
    @constraint(
        emp,
        storage_cyclic[n in N, s in storages(sets, n), sp in SP, sc in opscenarios(sp)],
        storOp[n, s, last(sc)] == storage_init(par, s) * storCapEn[n, s, sp]
    )

    # Storage operational and power capacity constraints
    @info " - operational capacity constraints energy: $(length(node_storages(sets)) * length(periods))"
    _report_progress(progress, "Creating storage energy-capacity constraints ($(length(node_storages(sets)) * length(periods)) constraints)")
    @constraint(
        emp,
        storage_op_cap_en[n in N, s in storages(sets, n), sp in SP, t in sp],
        storOp[n, s, t] <= storCapEn[n, s, sp]
    )
    @info " - operational capacity constraints power: $(length(node_storages(sets)) * length(periods))"
    _report_progress(progress, "Creating storage power-capacity constraints ($(length(node_storages(sets)) * length(periods)) constraints)")
    @constraint(
        emp,
        storage_op_cap_pow[n in N, s in storages(sets, n), sp in SP, t in sp],
        storCharge[n, s, t] <= storCapPow[n, s, sp]
    )
    @constraint(
        emp,
        storage_op_cap_pow_dis[n in N, s in storages(sets, n), sp in SP, t in sp],
        storDischarge[n, s, t] <= storage_disc_to_char_ratio(par, s) * storCapPow[n, s, sp]
    )

    @info " - investment constraints"
    _report_progress(progress, "Creating storage installed-capacity tracking constraints")
    # Tracking installed capacity from investments
    @constraint(
        emp,
        storage_installed_cap_en[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvEn[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s) - duration_strat(sp)) +
            stor_cap_init_en(par, n, s, sp) == storCapEn[n, s, sp]
    )
    @constraint(
        emp,
        storage_installed_cap_pow[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvPow[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s) - duration_strat(sp)) +
            stor_cap_init_pow(par, n, s, sp) == storCapPow[n, s, sp]
    )

    @info " - maximum storage investment constraints: $(2 * length(node_storages(sets)) * length(SP))"
    _report_progress(progress, "Creating storage maximum-investment constraints ($(2 * length(node_storages(sets)) * length(SP)) potential constraints)")
    @constraint(
        emp,
        storage_max_inv_pow[n in N, s in storages(sets, n), sp in SP; stor_pw_max_build_cap(par, n, s, sp) !== nothing],
        storCapInvPow[n, s, sp] <= stor_pw_max_build_cap(par, n, s, sp)
    )
    @constraint(
        emp,
        storage_max_inv_en[n in N, s in storages(sets, n), sp in SP; stor_en_max_build_cap(par, n, s, sp) !== nothing],
        storCapInvEn[n, s, sp] <= stor_en_max_build_cap(par, n, s, sp)
    )

    @info " - maximum storage installed constraints: $(2 * length(node_storages(sets)) * length(SP))"
    _report_progress(progress, "Creating storage maximum-installed-capacity constraints ($(2 * length(node_storages(sets)) * length(SP)) potential constraints)")
    @constraint(
        emp,
        storage_max_inst_pow[n in N, s in storages(sets, n), sp in SP; stor_pw_max_inst_cap(par, n, s, sp) !== nothing],
        storCapPow[n, s, sp] <= stor_pw_max_inst_cap(par, n, s, sp)
    )
    @constraint(
        emp,
        storage_max_inst_en[n in N, s in storages(sets, n), sp in SP; stor_en_max_inst_cap(par, n, s, sp) !== nothing],
        storCapEn[n, s, sp] <= stor_en_max_inst_cap(par, n, s, sp)
    )

    # Couple installed power and energy capacities via a fixed ratio for dependent storages.
    return @constraint(
        emp,
        storage_couple_pow_en[n in N, s in storages(sets, n), sp in SP; s in dependent_storages(sets)],
        storCapPow[n, s, sp] == power_to_energy(par, s) * storCapEn[n, s, sp]
    )

end

function _canonical_arc(m, n)
    return is_bidir(m, n) ? (m, n) : (n, m)
end

function _offshore_endpoint(sets, m, n)
    is_offshore_wind_farm(sets, m) && return m
    is_offshore_wind_farm(sets, n) && return n
    return nothing
end

function create_transmission_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure; offshore_transmission_cap::Bool = true, progress = nothing)
    @info "Creating transmission constraints"
    _report_progress(progress, "Creating transmission constraints")
    N = nodes(sets)
    SP = strat_periods(periods)

    transOp = emp[:transmissionOperational]
    transCap = emp[:transmissionInstalledCap]
    transCapInv = emp[:transmissionInvCap]

    # Transmission capacity constraints
    @constraint(
        emp,
        trans_cap[(m, n) in arcs(sets), sp in SP, t in sp],
        transOp[m, n, t] <= (is_bidir(m, n) ? transCap[m, n, sp] : transCap[n, m, sp])
    )

    # Tracking installed capacity from investments across strategic periods that are within
    # the technology lifetime
    @constraint(
        emp,
        trans_track_cap[(m, n) in bidir_arcs(sets), sp in SP],
        sum(transCapInv[m, n, spp] for spp in SP if duration_aggr(spp, sp, SP) <= trans_lifetime(par, m, n) - duration_strat(sp)) +
            trans_cap_init(par, m, n, sp) == transCap[m, n, sp]
    )

    # Constraints on maximum capacity that can be built and installed for each transmission line
    @constraint(
        emp,
        trans_max_capacity[(m, n) in bidir_arcs(sets), sp in SP; !isnothing(trans_max_build_cap(par, m, n, sp))],
        transCapInv[m, n, sp] <= trans_max_build_cap(par, m, n, sp)
    )

    # Constraints on maximum installed capacity for each transmission line
    @constraint(
        emp,
        trans_installed_cap[(m, n) in bidir_arcs(sets), sp in SP; !isnothing(trans_max_inst_cap(par, m, n, sp))],
        transCap[m, n, sp] <= trans_max_inst_cap(par, m, n, sp)
    )

    if offshore_transmission_cap
        @info " - offshore wind-farm transmission capacity constraints"
        _report_progress(progress, "Creating offshore wind-farm transmission capacity constraints")
        genCap = emp[:genInstalledCap]
        # Python builds this over ordered node pairs, producing duplicate rows for the
        # two directions of an offshore-adjacent corridor. Keep the same row structure
        # while pointing both directions at Julia's canonical corridor capacity.
        return @constraint(
            emp,
            wind_farm_transmission_cap[
                (m, n) in arcs(sets), sp in SP;
                !isnothing(_offshore_endpoint(sets, m, n))
            ],
            transCap[_canonical_arc(m, n)..., sp] <=
                sum(genCap[_offshore_endpoint(sets, m, n), g, sp] for g in generators(sets, _offshore_endpoint(sets, m, n)); init = 0)
        )
    end

    return nothing
end


function _opscenario_count(sp)
    first_rp = first(repr_periods(sp))
    return length(opscenarios(first_rp))
end

function create_emission_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure; progress = nothing)
    par.CO2cap === nothing && return nothing

    @info "Creating emission constraints"
    SP = strat_periods(periods)
    cap_count = sum(_opscenario_count(sp) for sp in SP)
    _report_progress(progress, "Creating emission-cap constraints ($cap_count constraints)")

    N = nodes(sets)
    genOp = emp[:genOperational]

    @variable(emp, nodeEmission[N, sp in SP, sc in 1:_opscenario_count(sp)])

    @constraint(
        emp,
        node_emission[n in N, sp in SP, sc in 1:_opscenario_count(sp)],
        nodeEmission[n, sp, sc] ==
            sum(
                multiple_strat(sp, t) *
                co2_content(par, g) *
                (3.6 / par.genEfficiency[g][sp]) *
                genOp[n, g, t]
                for g in generators(sets, n)
                for rp in repr_periods(sp)
                for (scenario_index, scenario) in enumerate(opscenarios(rp))
                if scenario_index == sc
                for t in scenario;
                init = 0.0
            )
    )

    return @constraint(
        emp,
        emission_cap[sp in SP, sc in 1:_opscenario_count(sp); co2_cap(par, sp) !== nothing],
        sum(nodeEmission[n, sp, sc] for n in N; init = 0.0) <= 1e6 * co2_cap(par, sp)
    )
end

function objective_component_expressions(emp::JuMP.Model, sets, par, periods::TimeStructure, discounter::Discounter)
    N = nodes(sets)
    SP = strat_periods(periods)

    genInvCap = emp[:genInvCap]
    transInvCap = emp[:transmissionInvCap]
    storInvCapPow = emp[:storPWInvCap]
    storInvCapEn = emp[:storENInvCap]
    shed = emp[:loadShed]
    genOp = emp[:genOperational]

    function generator_investment_expr(sp)
        total = JuMP.AffExpr(0.0)
        for n in N, g in generators(sets, n)
            total += gen_invest_cost(par, g, sp) * genInvCap[n, g, sp]
        end
        return total
    end

    function storage_investment_expr(sp)
        total = JuMP.AffExpr(0.0)
        for n in N, s in storages(sets, n)
            total += stor_pw_invest_cost(par, s, sp) * storInvCapPow[n, s, sp]
            total += stor_en_invest_cost(par, s, sp) * storInvCapEn[n, s, sp]
        end
        return total
    end

    function generator_operation_expr(t)
        total = JuMP.AffExpr(0.0)
        for n in N, g in generators(sets, n)
            total += gen_marginal_cost(par, g, t) * genOp[n, g, t]
        end
        return total
    end

    return (
        generator_investment = sum(
            objective_weight(sp, discounter) * generator_investment_expr(sp)
            for sp in SP
        ),
        storage_investment = sum(
            objective_weight(sp, discounter) * storage_investment_expr(sp) for sp in SP
        ),
        transmission_investment = sum(
            objective_weight(sp, discounter) *
            sum(trans_invest_cost(par, m, n, sp) * transInvCap[m, n, sp] for (m, n) in bidir_arcs(sets); init = 0)
            for sp in SP
        ),
        load_shedding = sum(
            objective_weight(t, discounter; type = "avg_year") *
            sum(lost_load_cost(par, n, t) * shed[n, t] for n in N; init = 0)
            for t in periods
        ),
        generator_operation = sum(
            objective_weight(t, discounter; type = "avg_year") * generator_operation_expr(t)
            for t in periods
        ),
    )
end

function objective_component_values(emp::JuMP.Model, sets, par, periods::TimeStructure, discounter::Discounter)
    expressions = objective_component_expressions(emp, sets, par, periods, discounter)
    return map(JuMP.value, expressions)
end
