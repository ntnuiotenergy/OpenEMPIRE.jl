
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

    # Give each season and equal share of each year
    seasons_share = [1 / nseasons for _ in 1:nseasons]

    # Give peaks zero weight (only used for feasibility checks)
    peaks_share = [0 for _ in 1:npeaks]

    # Create representative periods for each year
    repr_periods = RepresentativePeriods(8760, vcat(seasons_share, peaks_share), vcat(seasons, peaks))

    # Return a two level structure with yearly resolution
    return TwoLevel(npers, years_period, repr_periods; op_per_strat = 8760)
end

function create_variables(emp::JuMP.Model, sets, periods::TimeStruct.TimeStructure)

    # Index sets
    N = nodes(sets)
    G = generators(sets)
    S = storages(sets)

    T = periods
    SP = strat_periods(periods)

    @info "Declaring variables"
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
    for (n, g) in sets.GeneratorsOfNode, sp in SP
        unsafe_insertvar!(genInvCap, n, g, sp)
        unsafe_insertvar!(genInstalledCap, n, g, sp)
    end
    for (n, m) in sets.DirectionalLink, sp in SP
        unsafe_insertvar!(transmissionInvCap, n, m, sp)
        unsafe_insertvar!(transmissionInstalledCap, n, m, sp)
    end
    for (n, s) in sets.StoragesOfNode, sp in SP
        unsafe_insertvar!(storPWInvCap, n, s, sp)
        unsafe_insertvar!(storENInvCap, n, s, sp)
        unsafe_insertvar!(storPWInstalledCap, n, s, sp)
        unsafe_insertvar!(storENInstalledCap, n, s, sp)
    end
    @info "Inserting variables into sparse arrays - operational variables"
    @info "Total time periods: $(length(T))"
    @info "Generator operational variables: $(length(sets.GeneratorsOfNode) * length(T))"
    for (n, g) in sets.GeneratorsOfNode, t in T
        unsafe_insertvar!(genOperational, n, g, t)
    end
    @info "Transmission operational variables: $(length(sets.DirectionalLink) * length(T))"
    for (n, m) in sets.DirectionalLink, t in T
        unsafe_insertvar!(transmissionOperational, n, m, t)
    end
    @info "Storage operational variables: $(length(sets.StoragesOfNode) * length(T))"
    for (n, s) in sets.StoragesOfNode, t in T
        unsafe_insertvar!(storCharge, n, s, t)
        unsafe_insertvar!(storDischarge, n, s, t)
        unsafe_insertvar!(storOperational, n, s, t)
    end
    @info "Load shedding variables: $(length(N) * length(T))"
    for n in N, t in T
        unsafe_insertvar!(loadShed, n, t)
    end
end

function create_objective(emp::JuMP.Model, sets, par, periods::TimeStructure, discounter::Discounter)
    @info "Creating objective function"
    N = nodes(sets)
    T = periods
    SP = strat_periods(periods)

    genInvCap = emp[:genInvCap]
    transInvCap = emp[:transmissionInvCap]
    storInvCapPow = emp[:storPWInvCap]
    storInvCapEn = emp[:storENInvCap]

    shed = emp[:loadShed]
    genOp = emp[:genOperational]

    @objective(
        emp,
        Min,
        sum(objective_weight(sp, discounter) * (
            sum(gen_invest_cost(par, g, sp) * genInvCap[n, g, sp] for n in N, g in generators(sets, n); init = 0) +
            sum(trans_invest_cost(par, m, n, sp) * transInvCap[m, n, sp] for (m, n) in arcs(sets); init = 0) +
            sum(stor_pw_invest_cost(par, s, sp) * storInvCapPow[n, s, sp] for n in N, s in storages(sets, n); init = 0) +
            sum(stor_en_invest_cost(par, s, sp) * storInvCapEn[n, s, sp] for n in N, s in storages(sets, n); init = 0)
            ) for sp in SP) +
        sum(objective_weight(t, discounter) * (
                sum(lost_load_cost(par, n, t) * shed[n, t] for n in N; init = 0) +
                sum(gen_marginal_cost(par, g, t) * genOp[n, g, t] for n in N for g in generators(sets, n); init = 0)
                ) for t in T)
    )
end

# Create all constraints in the model
function create_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)
    @info "Creating constraints"

    N = nodes(sets)
    G = generators(sets)
    T = periods

    genOp = emp[:genOperational]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    trOp = emp[:transmissionOperational]
    shed = emp[:loadShed]

    @info "Flow balance constraints: $((length(N)) * length(T))"
    @constraint(
        emp,
        flow_balance[n in N, t in T],
        sum(genOp[n, g, t] for g in G) + sum(discharge_eff(par, s) * storDischarge[n, s, t] - storCharge[n, s, t] for s in storages(sets, n)) +
            sum(line_eff(par, m, n) * trOp[m, n, t] for (m, n, t) in SparseVariables.select(trOp, :, n, t)) - sum(trOp[n, :, t]) +
            shed[n, t] == load(par, n, t)
    )

    create_generator_constraints(emp, sets, par, periods)
    create_storage_constraints(emp, sets, par, periods)
    create_transmission_constraints(emp, sets, par, periods)

end

# Calculate the total duration of all strategic periods from spp to sp (inclusive)
# Return Inf if spp < sp
function duration_aggr(sp, spp, strat_periods)
    spp < sp && return Inf
    return sum(duration_strat(p) for p in strat_periods if p >= sp && p < spp; init = 0)
end

function create_generator_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)
    @info "Creating generator constraints"
    N = sets.Node
    SP = strat_periods(periods)

    genOp = emp[:genOperational]
    genCap = emp[:genInstalledCap]
    genInv = emp[:genInvCap]

    # Generation capacity constraints
    @info " - capacity constraints: $(length(sets.GeneratorsOfNode) * length(periods))"
    @constraint(
        emp,
        gen_max_prod[n in N, g in generators(sets, n), sp in SP, t in sp],
        genOp[n, g, t] <= gencap_avail(par, n, g, t) * genCap[n, g, sp]
    )

    # Ramping Constraints
    @info " - ramping constraints: $(length(sets.GeneratorsOfNode) * length(periods))"
    @constraint(
        emp,
        gen_ramping[n in N, g in generators(sets, n), sp in SP, (prev, t) in withprev(sp); !isnothing(prev)],
        genOp[n, g, t] <= genOp[n, g, prev] + rampup_cap(par, g) * genCap[n, g, sp]
    )

    # Tracking installed capacity from investments across strategic periods that are within
    # the technology lifetime
    @info " - installed capacity constraints: $(length(sets.GeneratorsOfNode) * length(SP))"
    @constraint(
        emp,
        installed_cap_gen[n in N, g in generators(sets, n), sp in SP],
        sum(genInv[n, g, spp] for spp in SP if duration_aggr(spp, sp, SP) <= gen_lifetime(par, g)) +
            gencap_init(par, n, g, sp) == genCap[n, g, sp]
    )

    # Constraints on maximum capacity that can be built and installed for each technology
    @info " - maximum investment constraints: $(length(sets.GeneratorsOfNode) * length(SP))"
    @constraint(
        emp,
        max_inv_tech[n in N, tc in techs(sets, n), sp in SP; max_build_cap(par, n, tc, sp) !== nothing],
        sum(genInv[n, g, sp] for g in generators_tech(sets, n, tc)) <= max_build_cap(par, n, tc, sp)
    )

    # Constraints on maximum installed capacity for each technology
    @info " - maximum installed capacity constraints: $(length(sets.GeneratorsOfNode) * length(SP))"
    @constraint(
        emp,
        max_inst_tech[n in N, tc in techs(sets, n), sp in SP; max_inst_cap(par, n, tc, sp) !== nothing],
        sum(genCap[n, g, sp] for g in generators_tech(sets, n, tc)) <= max_inst_cap(par, n, tc, sp)
    )
end

function create_storage_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)
    @info "Creating storage constraints"
    N = sets.Node
    SP = strat_periods(periods)

    storOp = emp[:storOperational]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    storCapEn = emp[:storENInstalledCap]
    storCapInvEn = emp[:storENInvCap]
    storCapPow = emp[:storPWInstalledCap]
    storCapInvPow = emp[:storPWInvCap]

    # Storage energy balance constraints
    @info " - energy balance constraints: $(length(sets.StoragesOfNode) * length(periods))"
    @constraint(
        emp,
        storage_bal[n in N, s in storages(sets, n), sp in SP, (prev, t) in withprev(sp)],
        bleed_eff(par, s) * (isnothing(prev) ? storage_init(par, s) * storCapEn[n, s, sp] : storOp[n, s, prev]) +
            charge_eff(par, s) * storCharge[n, s, t] - storDischarge[n, s, t] == storOp[n, s, t]
    )

    # Cyclic condition for storage at the end of each operational scenario
    @info " - cyclic condition constraints"
    @constraint(
        emp,
        storage_cyclic[n in N, s in storages(sets, n), sp in SP, sc in opscenarios(sp)],
        storOp[n, s, last(sc)] == storage_init(par, s) * storCapEn[n, s, sp]
    )

    # Storage operational and power capacity constraints
    @info " - operational capacity constraints energy: $(length(sets.StoragesOfNode) * length(periods))"
    @constraint(
        emp,
        storage_op_cap_en[n in N, s in storages(sets, n), sp in SP, t in sp],
        storOp[n, s, t] <= storCapEn[n, s, sp]
    )
    @info " - operational capacity constraints power: $(length(sets.StoragesOfNode) * length(periods))"
    @constraint(
        emp,
        storage_op_cap_pow[n in N, s in storages(sets, n), sp in SP, t in sp],
        storCharge[n, s, t] <= storCapPow[n, s, sp]
    )

    @info " - investment constraints"
    # Tracking installed capacity from investments
    @constraint(
        emp,
        storage_installed_cap_en[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvEn[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s)) +
            stor_cap_init_en(par, n, s, sp) == storCapEn[n, s, sp]
    )
    @constraint(
        emp,
        storage_installed_cap_pow[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvPow[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s)) +
            stor_cap_init_pow(par, n, s, sp) == storCapPow[n, s, sp]
    )

    # Couple power and energy capacity investments via a fixed ratio for dependent storages
    @constraint(
        emp,
        storage_couple_pow_en[n in N, s in storages(sets, n), sp in SP; s in dependent_storages(sets)],
        storCapInvEn[n, s, sp] == power_to_energy(par, s) * storCapInvPow[n, s, sp]
    )

end

function create_transmission_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)
    @info "Creating transmission constraints"
    N = sets.Node
    SP = strat_periods(periods)

    tr_op = emp[:transmissionOperational]
    tr_cap = emp[:transmissionInstalledCap]
    tr_inv_cap = emp[:transmissionInvCap]

    # Transmission capacity constraints
    @constraint(
        emp,
        trans_cap[(m, n) in arcs(sets), sp in SP, t in sp],
        tr_op[m, n, t] <= tr_cap[m, n, sp]
    )

    # Tracking installed capacity from investments across strategic periods that are within
    # the technology lifetime
    @constraint(
        emp,
        trans_track_cap[(m, n) in arcs(sets), sp in SP],
        sum(tr_inv_cap[m, n, spp] for spp in SP if duration_aggr(spp, sp, SP) <= trans_lifetime(par, m, n)) +
            trans_cap_init(par, m, n, sp) * tr_cap[m, n, sp] == 0
    )

    # Constraints on maximum capacity that can be built and installed for each transmission line
    @constraint(
        emp,
        trans_cap_inv[(m, n) in arcs(sets), sp in SP; !isnothing(trans_max_build_cap(par, m, n, sp))],
        tr_inv_cap[m, n, sp] <= trans_max_build_cap(par, m, n, sp)
    )

end


function create_emission_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)

    # TODO: Implement emission constraints
    #=
    def emission_cap_rule(model, i, w):
            return sum(model.seasScale[s]*model.genCO2TypeFactor[g]*(3.6/model.genEfficiency[g,i])*model.genOperational[n,g,h,i,w] for (n,g) in model.GeneratorsOfNode for (s,h) in model.HoursOfSeason)/1000000 \
                - model.CO2cap[i] <= 0   #
    =#
end
