
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

    # Variable for tracking the objective value
    @variable(emp, obj, base_name="objective")

    # Insert sparse variables
    @info "Inserting variables into sparse arrays - strategic variables"
    for (n, g) in sets.GeneratorsOfNode, sp in SP
        unsafe_insertvar!(genInvCap, n, g, sp)
        unsafe_insertvar!(genInstalledCap, n, g, sp)
    end
    for (n, m) in sets.BidirectionalArc, sp in SP
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
    @info "Transmission operational variables: $(length(sets.BidirectionalArc) * length(T))"
    for (n, m) in sets.BidirectionalArc, t in T
        unsafe_insertvar!(transmissionOperational, n, m, t)
    end
    @info "Storage operational variables: $(length(sets.StoragesOfNode) * length(T))"
    for (n, s) in sets.StoragesOfNode, t in T
        unsafe_insertvar!(storCharge, n, s, t)
        unsafe_insertvar!(storDischarge, n, s, t)
        unsafe_insertvar!(storOperational, n, s, t)
    end


end

function create_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)

    N = nodes(sets)
    G = generators(sets)
    T = periods

    genOp = emp[:genOperational]
    storCharge = emp[:storCharge]
    storDischarge = emp[:storDischarge]
    trOp = emp[:transmissionOperational]
    shed = emp[:loadShed]

    μ = par.lineEfficiency

    @constraint(
        emp,
        flow_balance[n in N, t in T],
        sum(genOp[n, g, t] for g in G) + sum(discharge_eff(par, s) * storDischarge[n, s, t] - storCharge[n, s, t] for s in storages(sets, n)) +
            sum(μ[m, n] * trOp[m, n, t] for (m, n, t) in SparseVariables.select(trOp, :, n, t)) - sum(trOp[n, :, t]) +
            #par.sload[n, t] +
            shed[n, t] == 0
    )

    create_generator_constraints(emp, sets, par, periods)
    create_storage_constraints(emp, sets, par, periods)
    create_transmission_constraints(emp, sets, par, periods)

end

function duration_aggr(sp, spp, strat_periods)
    spp < sp && return Inf
    return sum(duration_strat(p) for p in strat_periods if p >= sp && p < spp; init = 0)
end

function create_generator_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)

    N = sets.Node
    G = sets.Generator
    SP = strat_periods(periods)

    genOp = emp[:genOperational]
    genCap = emp[:genInstalledCap]
    genInv = emp[:genInvCap]

    # Generation capacity constraints
    @constraint(
        emp,
        gen_max_prod[n in N, g in G, sp in SP, t in sp],
        genOp[n, g, t] <= gencap_avail(par, n, g, sp) * genCap[n, g, sp]
    )

    # Ramping Constraints
    @constraint(
        emp,
        gen_ramping[n in N, g in G, sp in SP, (prev, t) in withprev(sp); !isnothing(prev)],
        genOp[n, g, t] <= genOp[n, g, prev] + rampup_cap(par, g) * genCap[n, g, sp]
    )

    # Tracking installed capacity from investments across strategic periods that are within
    # the technology lifetime
    @constraint(
        emp,
        installed_cap_gen[n in N, g in G, sp in SP],
        sum(genInv[n, g, spp] for spp in SP if duration_aggr(spp, sp, SP) <= gen_lifetime(par, g)) +
        gencap_init(par, n, g, sp) == genCap[n, g, sp]
    )

    # Constraints on maximum capacity that can be built and installed for each technology
    @constraint(
        emp,
        max_inv_tech[n in N, t in techs(sets, n), sp in SP; !isnothing(max_build_cap(par, n, t, sp))],
        sum(genInv[n, g, sp] for g in generators_tech(sets, n, t)) <= max_build_cap(par, n, t, sp)
    )

    # Constraints on maximum installed capacity for each technology
    @constraint(
        emp,
        max_inst_tech[n in N, t in techs(sets, n), sp in SP; !isnothing(max_inst_cap(par, n, t, sp))],
        sum(genCap[n, g, sp] for g in generators_tech(sets, n, t)) <= max_inst_cap(par, n, t, sp)
    )
end

function create_storage_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)

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
    @constraint(
        emp,
        storage_bal[n in N, s in storages(sets, n), sp in SP, (prev, t) in withprev(sp)],
        bleed_eff(par, s) * (isnothing(prev) ? storage_init(par, s) * storCapEn[n, s, sp] : storOp[n, s, prev]) +
            charge_eff(par, s) * storCharge[n, s, t] - storDischarge[n, s, t] == storOp[n, s, t]
    )

    # Cyclic condition for storage at the end of each operational scenario
    @constraint(
        emp,
        storage_cyclic[n in N, s in storages(sets, n), sp in SP, sc in opscenarios(sp)],
        storOp[n, s, last(sc)] == storage_init(par, s) * storCapEn[n, s, sp]
    )

    # Storage operational and power capacity constraints
    @constraint(
        emp,
        storage_op_cap_en[n in N, s in storages(sets, n), sp in SP, t in sp],
        storOp[n, s, t] <= storCapEn[n, s, sp]
    )
    @constraint(
        emp,
        storage_op_cap_pow[n in N, s in storages(sets, n), sp in SP, t in sp],
        storCharge[n, s, t] <= storCapPow[n, s, sp]
    )

    # Tracking installed capacity from investments
    @constraint(
        emp,
        storage_installed_cap_en[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvEn[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s)) +
            stor_cap_init_en(par, s, sp) == storCapEn[n, s, sp]
    )
    @constraint(
        emp,
        storage_installed_cap_pow[n in N, s in storages(sets, n), sp in SP],
        sum(storCapInvPow[n, s, spp] for spp in SP if duration_aggr(spp, sp, SP) <= lifetime_storage(par, s)) +
            stor_cap_init_pow(par, s, sp) == storCapPow[n, s, sp]
    )

end

function create_transmission_constraints(emp::JuMP.Model, sets, par, periods::TimeStructure)

    N = sets.Node
    SP = strat_periods(periods)

    trOp = emp[:transmissionOperational]
end

#=
function create_model(sets, par, opts, sol, emp)

    println("Declaring variables...")
    varStartTime = Dates.now()

    @variable(emp, genInvCap[n=sets.Node, g=sets.Generator, t=sets.Period; (n, g, t) in sets.NodeGenTime] >= 0, base_name="v_genInvCap")
    println("genInvCap time = "*string(Dates.now()-varStartTime))
    varTime = Dates.now()
    @variable(emp, transmissionInvCap[n=sets.Node, m=sets.Node, t=sets.Period; (n, m, t) in sets.NodeNodeTransm] >= 0, base_name="v_transmissionInvCap")
    println("transmissionInvCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storPWInvCap[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, t=sets.Period; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storPWInvCap")
    println("storPWInvCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storENInvCap[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, t=sets.Period; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storENInvCap")
    println("storENInvCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storCharge[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storCharge")
    println("storCharge time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storDischarge[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storDischarge")
    println("storDischarge time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, loadShed[n=sets.Node, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; sc in [si for si in sets.Scenario]] >= 0, base_name="v_loadShed")
    println("loadShed time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, genInstalledCap[n=sets.Node, g=sets.Generator, t=sets.Period; (n, g, t) in sets.NodeGenTime] >= 0, base_name="v_genInstalledCap")
    println("genInstalledCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, transmissionInstalledCap[n=sets.Node, m=sets.Node, t=sets.Period; (n, m, t) in sets.NodeNodeTransm] >= 0, base_name="v_transmissionInstalledCap")
    println("transmissionInstalledCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storPWInstalledCap[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, t=sets.Period; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storPWInstalledCap")
    println("storPWInstalledCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storENInstalledCap[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, t=sets.Period; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storENInstalledCap")
    println("storENInstalledCap time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storMovedIn[n=sets.Node, s=sets.StorageHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storMovedIn")
    @variable(emp, storMovedOut[n=sets.Node, s=sets.StorageHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storMovedOut")
    @variable(emp, amountsold[(n, s)=sets.StoragesOfHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; sc in [si for si in sets.Scenario]] >= 0, base_name="v_amountsold")
    println("amountsold time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, obj, base_name="objective")

    if opts.HEATMODULE == 1
        @variable(emp, ElToHeatOperational[n=sets.Node, r=sets.ElToHeat, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, r) ∈ sets.ElToHeatOfNode] >= 0, base_name="v_ElToHeatOperational")
        @variable(emp, ElToHeatInvCap[n=sets.Node, r=sets.ElToHeat, t=sets.Period; (n, r) ∈ sets.ElToHeatOfNode] >= 0, base_name="v_ElToHeatInvCap")
        @variable(emp, ElToHeatInstalledCap[n=sets.Node, r=sets.ElToHeat, t=sets.Period; (n, r) ∈ sets.ElToHeatOfNode] >= 0, base_name="v_ElToHeatInstalledCap")
        @variable(emp, loadShedTR[n=sets.Node, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario] >= 0, base_name="v_loadShedTR")
    end

    sol.genInvCap = genInvCap
    sol.transmissionInvCap = transmissionInvCap
    sol.storPWInvCap = storPWInvCap
    sol.storENInvCap = storENInvCap
    sol.storCharge = storCharge
    sol.storDischarge = storDischarge
    sol.loadShed = loadShed
    sol.genInstalledCap = genInstalledCap
    sol.transmissionInstalledCap = transmissionInstalledCap
    sol.storPWInstalledCap = storPWInstalledCap
    sol.storENInstalledCap = storENInstalledCap
    sol.amountsold = amountsold
    sol.storMovedIn = storMovedIn
    sol.storMovedOut = storMovedOut
    sol.obj = obj

    if opts.HEATMODULE == 1
        sol.ElToHeatOperational = ElToHeatOperational
        sol.ElToHeatInvCap = ElToHeatInvCap
        sol.ElToHeatInstalledCap = ElToHeatInstalledCap
        sol.loadShedTR = loadShedTR
    end

    if opts.HYDROGEN_TRANSPORT
        @variable(emp, transmissionInvCap_H2[n=sets.Node, m=sets.Node, t=sets.Period; (n, m, t) in sets.NodeNodeTransm_H2] >= 0, base_name="v_transmissionInvCap_H2")
        println("transmissionInvCap_H2 time = "*string(Dates.now()-varTime))
        varTime = Dates.now()
        @variable(emp, transmissionOperational_H2[n=sets.Node, m=sets.Node, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, m, t) in sets.NodeNodeTransm_H2 || (m, n, t) in sets.NodeNodeTransm_H2] >= 0, base_name="v_transmissionOperational_H2")
        println("transmissionOperational_H2 time = "*string(Dates.now()-varTime))
        varTime = Dates.now()
        @variable(emp, transmissionInstalledCap_H2[n=sets.Node, m=sets.Node, t=sets.Period; (n, m, t) in sets.NodeNodeTransm_H2] >= 0, base_name="v_transmissionInstalledCap_H2")
        println("transmissionInstalledCap_H2 time = "*string(Dates.now()-varTime))
        varTime = Dates.now()

        sol.transmissionInvCap_H2 = transmissionInvCap_H2
        sol.transmissionOperational_H2 = transmissionOperational_H2
        sol.transmissionInstalledCap_H2 = transmissionInstalledCap_H2
    end

    @variable(emp, genOperational[n=sets.Node, g=sets.Generator, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, g, t) in sets.NodeGenTime] >= 0, base_name="v_genOperational")
    println("genOperational time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, storOperational[n=sets.Node, s=sets.Storage+sets.StorageHydrogen, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, s, t) in sets.NodeStorTime] >= 0, base_name="v_storOperational")
    println("storOperational time = "*string(Dates.now()-varTime))
    varTime = Dates.now()
    @variable(emp, transmissionOperational[n=sets.Node, m=sets.Node, h=sets.Operationalhour, t=sets.Period, sc=sets.Scenario; (n, m, t) in sets.NodeNodeTransm] >= 0, base_name="v_transmissionOperational")
    println("transmissionOperational time = "*string(Dates.now()-varTime))
    varTime = Dates.now()

    sol.genOperational = genOperational
    sol.storOperational = storOperational
    sol.transmissionOperational = transmissionOperational

    println("Declaring variables... Done")

    # Constraints
    if opts.HYDROGEN
        @constraint(emp, Objective, obj ==
        sum(discount_multiplier(i, par) * (
            sum(par.genInvCost[g, i] * genInvCap[n, g, i] for (n, g) in sets.GeneratorsOfNode if (n, g, i) in eachindex(genInvCap) && (g,i) ∈ eachindex(par.genInvCost)) +
            sum(par.transmissionInvCost[n1, n2, i] * transmissionInvCap[n1, n2, i] for (n1, n2) in eachindex(par.transmissionInvCost)) +
            sum(par.transmissionInvCost_H2[n1, n2, i] * transmissionInvCap_H2[n1, n2, i] for (n1, n2) in eachindex(par.transmissionInvCost_H2)) +
            sum((par.storPWInvCost[b, i] * storPWInvCap[n, b, i] + par.storENInvCost[b, i] * storENInvCap[n, b, i]) for (n, b) in sets.StoragesOfNode+sets.StoragesOfHydrogen) +
            sum(par.operationalDiscountRate * par.seasScale[s] * par.sceProbab[w] * par.nodeLostLoadCost[n, i] * loadShed[n, h, i, w] for n in sets.Node for w in sets.Scenario for (s, h) in sets.HoursOfSeason if (n, h, i, w) in eachindex(loadShed) && (n, i) ∈ eachindex(par.nodeLostLoadCost); init = 0) +
            sum(par.operationalDiscountRate * par.seasScale[s] * par.sceProbab[w] * par.genMargCost[g, i] * genOperational[n, g, h, i, w] for (n, g) in sets.GeneratorsOfNode for (s, h) in sets.HoursOfSeason for w in sets.Scenario if (n, g, h, i, w) in eachindex(genOperational)) -
            sum(par.operationalDiscountRate * par.seasScale[s] * par.sceProbab[w] * par.HydrogenPrice[b, i] * amountsold[(n, b), h, i, w] * par.storageChargeEff[b] * par.storageDischargeEff[b] * 1000 for (n, b) in sets.StoragesOfHydrogen for (s, h) in sets.HoursOfSeason for w in sets.Scenario) +
        0) for i in sets.Period)
        , base_name="Objective")
    end

    @objective(emp, Min, obj)

    # Flow Balance Constraints
    if opts.HYDROGEN
        @constraint(emp, FlowBalance[n=sets.Node, h=sets.Operationalhour, p=sets.Period, sce=sets.Scenario],
            sum(genOperational[n, g, h, p, sce] for g in sets.Generator if (n, g) in sets.GeneratorsOfNode) +
            sum((par.storageDischargeEff[b] * storDischarge[n, b, h, p, sce] - storCharge[n, b, h, p, sce]) for b in sets.Storage if (n, b) in sets.StoragesOfNode) +
            sum(((get(par.lineEfficiency, [inflow, n], 0) + get(par.lineEfficiency, [n, inflow], 0)) * transmissionOperational[inflow, n, h, p, sce]) for inflow in NodesIn(n, sets) if (inflow, n, h, p, sce) in eachindex(transmissionOperational)) -
            sum((transmissionOperational[n, outflow, h, p, sce]) for outflow in NodesOut(n, sets) if (n, outflow, h, p, sce) in eachindex(transmissionOperational)) -
            sum(SoldInFlow * amountsold[n, b, h, p, sce] for b in sets.Storage if (n, b) in sets.StoragesOfHydrogen) -
            sum(ElToHeatOperational[he, h, p, sce] for he in sets.ElToHeatOfNode if (he, h, p, sce) in eachindex(ElToHeatOperational)) +
            loadShed[n, h, p, sce] == 0, base_name="Flow Balance H2")
    else
        @constraint(emp, FlowBalance[n=sets.Node, h=sets.Operationalhour, p=sets.Period, sce=sets.Scenario],
            sum(genOperational[n, g, h, p, sce] for g in sets.Generator if (n, g) in sets.GeneratorsOfNode) +
            sum((par.storageDischargeEff[b] * storDischarge[n, b, h, p, sce] - storCharge[n, b, h, p, sce]) for b in sets.Storage if (n, b) in sets.StoragesOfNode) +
            sum(((get(par.lineEfficiency, [inflow, n], 0) + get(par.lineEfficiency, [n, inflow], 0)) * transmissionOperational[inflow, n, h, p, sce]) for inflow in NodesIn(n, sets) if (inflow, n, h, p, sce) in eachindex(transmissionOperational)) -
            sum((transmissionOperational[n, outflow, h, p, sce]) for outflow in NodesOut(n, sets) if (n, outflow, h, p, sce) in eachindex(transmissionOperational)) -
            sum(ElToHeatOperational[he, h, p, sce] for he in sets.ElToHeatOfNode if (he, h, p, sce) in eachindex(ElToHeatOperational)) -
            par.sload[n, h, p, sce] +
            loadShed[n, h, p, sce] == 0, base_name="Flow Balance NoH2")
    end

    if opts.HEATMODULE == 1
        @constraint(emp, FlowBalanceTR_Rule[n=sets.Node, h=sets.Operationalhour, p=sets.Period, sce=sets.Scenario],
            sum(genOperational[n, g, h, p, sce] for g in sets.Generator if (n, g) in sets.GeneratorsOfNode) +
            sum((par.storageDischargeEff[b] * storDischarge[n, b, h, p, sce] - storCharge[n, b, h, p, sce]) for b in sets.Storage if (n, b) in sets.StoragesOfNode) +
            sum(sets.ElToHeatEff[r] * ElToHeatOperational[n, r, h, p, sce] for r in sets.ElToHeatOfNode if (n, r) in sets.ElToHeatOfNode) -
            sum(par.sloadTR[n1, h, p, sce] for n1 in sets.Node if n1 == n && [n, h, p, sce] in eachindex(par.sloadTR); init = 0) +
            loadShedTR[n, h, p, sce] == 0, base_name="Flow Balance TR")

        @constraint(emp, ElToHeatConv_Rule[n=sets.Node, r=sets.ElToHeat, h=sets.Operationalhour, p=sets.Period, sce=sets.Scenario; (n, r, h, p, sce) ∈ eachindex(ElToHeatOperational)],
            ElToHeatOperational[n, r, h, p, sce] <= ElToHeatInstalledCap[n, r, p], base_name="El to Heat Conversion Rule")

        @constraint(emp, ElToHeatLifetime_Rule[n=sets.Node, r=sets.ElToHeat, p=sets.Period; (n, r, p) ∈ eachindex(ElToHeatInstalledCap) && (n, r, p) ∈ keys(par.ElToHeatInitCap)],
            sum(ElToHeatInvCap[n, r, i] for i in sets.Period if i >= max((1 + p - par.ElToHeatLifetime[r] / par.LeapYearsInvestment), 1) && i <= p) -
            ElToHeatInstalledCap[n, r, p] + par.ElToHeatInitCap[n, r, p] == 0, base_name="El to Heat Lifetime Rule")

        @constraint(emp, ElToHeatInvCap_Rule[n=sets.Node, r=sets.ElToHeat, p=sets.Period; (n, r, p) in eachindex(ElToHeatInstalledCap)],
            ElToHeatInstalledCap[n, r, p] <= par.ElToHeatMaxInstalledCap[n, r], base_name="El to Heat Investment Capacity Rule")
    end

    # Generation Constraints
    @constraint(emp, maxGenProduction[(n, g)=sets.GeneratorsOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; (n, g, h, w) in keys(par.genCapAvail)],
        genOperational[n, g, h, i, w] <= par.genCapAvail[n, g, h, w] * genInstalledCap[n, g, i], base_name="Max Generator Production")

    @constraint(emp, ramping[(n, g)=sets.GeneratorsOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; g in sets.ThermalGenerators && !(h in sets.FirstHoursOfRegSeason || h in sets.FirstHoursOfPeakSeason)],
        genOperational[n, g, h, i, w] <= genOperational[n, g, (h-1), i, w] + get(par.genRampUpCap, g, 0) * genInstalledCap[n, g, i], base_name="Ramping Constraint")

    @constraint(emp, installedCapDefinitionGen[n=sets.Node, g=sets.GeneratorEL, i=sets.Period; (n, g, i) ∈ keys(par.genInitCap)],
        sum(genInvCap[n, g, j] for j in sets.Period if j >= max(1, 1 + i - par.genLifetime[g] / par.LeapYearsInvestment) && (n, g, i) ∈ eachindex(genInvCap) && j <= i) -
        genInstalledCap[n, g, i] + par.genInitCap[n, g, i] == 0, base_name="Installed Capacity Generator")

    @constraint(emp, hydro_gen_limit[(n, g)=sets.GeneratorsOfNode, s=sets.Season, i=sets.Period, w=sets.Scenario; g in sets.RegHydroGenerator],
        sum(genOperational[n, g, h, i, w] for h in sets.Operationalhour if (s, h) in sets.HoursOfSeason) <= par.maxRegHydroGen[n, s, i, w], base_name="Hydro Generation Limit")

    @constraint(emp, hydro_node_limit[n=sets.Node, i=sets.Period; n in keys(par.maxHydroNode)],
        sum(genOperational[n, g, h, i, w] * par.seasScale[s] * par.sceProbab[w] for g in sets.HydroGenerator if (n, g) in sets.GeneratorsOfNode for (s, h) in sets.HoursOfSeason for w in sets.Scenario) <= par.maxHydroNode[n], base_name="Hydro Node Limit")

    @constraint(emp, investment_gen_cap[t=sets.Technology, n=sets.Node, i=sets.Period; (n, t) in keys(par.genMaxBuiltCap)],
        sum(genInvCap[n, g, i] for g in sets.Generator if (n, g) in sets.GeneratorsOfNode && (t, g) in sets.GeneratorsOfTechnology) <= par.genMaxBuiltCap[n, t], base_name="Investment Generation Capacity")

    @constraint(emp, installed_gen_cap[t=sets.Technology, n=sets.Node, i=sets.Period; (n, t, i) in keys(par.genMaxInstalledCap)],
        sum(genInstalledCap[n, g, i] for g in sets.Generator if (n, g) in sets.GeneratorsOfNode && (t, g) in sets.GeneratorsOfTechnology) <= par.genMaxInstalledCap[n, t, i], base_name="Installed Generation Capacity")

    # Storage Constraints

    @constraint(emp, storageEnergyBalanceRuleInitial[(n, b)=sets.StoragesOfNode - sets.StoragesOfHydrogen, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h in sets.FirstHoursOfRegSeason || h in sets.FirstHoursOfPeakSeason],
        par.storOperationalInit[b] * storENInstalledCap[n, b, i] + par.storageChargeEff[b] * storCharge[n, b, h, i, w] - storDischarge[n, b, h, i, w] - storOperational[n, b, h, i, w] == 0, base_name="Storage Energy Balance Initial Hour")


    @constraint(emp, storageEnergyBalanceRuleLater[(n, b)=sets.StoragesOfNode - sets.StoragesOfHydrogen, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h ∉ sets.FirstHoursOfRegSeason && h ∉ sets.FirstHoursOfPeakSeason],
        par.storageBleedEff[b] * storOperational[n, b, (h-1), i, w] + par.storageChargeEff[b] * storCharge[n, b, h, i, w] - storDischarge[n, b, h, i, w] - storOperational[n, b, h, i, w] == 0, base_name="Storage Energy Balance Later Hours")

    @constraint(emp, SeasonalNetZeroBalanceStorageReg[(n, b)=sets.StoragesOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h in sets.FirstHoursOfRegSeason],
        storOperational[n, b, h + par.lengthRegSeason - 1, i, w] - par.storOperationalInit[b] * storENInstalledCap[n, b, i] == 0, base_name="Storage: Zero Regular Season")

    @constraint(emp, SeasonalNetZeroBalanceStoragePeak[(n, b)=sets.StoragesOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h in sets.FirstHoursOfPeakSeason],
        storOperational[n, b, h + par.lengthPeakSeason - 1, i, w] - par.storOperationalInit[b] * storENInstalledCap[n, b, i] == 0, base_name="Storage: Zero Peak Season")

    @constraint(emp, storage_operational_cap[(n, b)=sets.StoragesOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario],
        storOperational[n, b, h, i, w] <= storENInstalledCap[n, b, i], base_name="Storage: Operational Capacity")

    @constraint(emp, storage_power_charg_cap[(n, b)=sets.StoragesOfNode, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario],
        storCharge[n, b, h, i, w] <= storPWInstalledCap[n, b, i], base_name="Storage: Power Charging Capacity")

    @constraint(emp, installedCapDefinitionStorEN[(n, g)=sets.StoragesOfNode, i=sets.Period; (n, g, i) in keys(par.storENInitCap)],
        sum(storENInvCap[n, g, j] for j in sets.Period if j >= max((1 + i - par.storageLifetime[g] / par.LeapYearsInvestment), 1) && j <= i) - storENInstalledCap[n, g, i] + par.storENInitCap[n, g, i] == 0, base_name="Installed Capacity Storage Energy")

    @constraint(emp, installedCapDefinitionStorPOW[(n, g)=sets.StoragesOfNode, i=sets.Period; (n, g, i) in keys(par.storPWInitCap)],
        sum(storPWInvCap[n, g, j] for j in sets.Period if j >= max(1 + i - par.storageLifetime[g] / par.LeapYearsInvestment, 1) && j <= i) - storPWInstalledCap[n, g, i] + par.storPWInitCap[n, g, i] == 0, base_name="Installed Capacity Storage Power")

    @constraint(emp, investment_storage_power_cap[(n, b)=sets.StoragesOfNode, i=sets.Period; (n, b, i) in keys(par.storPWMaxBuiltCap)],
        storPWInvCap[n, b, i] - par.storPWMaxBuiltCap[n, b, i] <= 0, base_name="Investment Storage Power Capacity")

    @constraint(emp, investment_storage_energy_cap[(n, b)=sets.StoragesOfNode, i=sets.Period; (n, b, i) in keys(par.storENMaxBuiltCap)],
        storENInvCap[n, b, i] <= par.storENMaxBuiltCap[n, b, i], base_name="Investment Storage Energy Capacity")

    @constraint(emp, installed_storage_power_cap[(n, b)=sets.StoragesOfNode, i=sets.Period; (n, b, i) in keys(par.storPWMaxInstalledCap)],
        storPWInstalledCap[n, b, i] <= par.storPWMaxInstalledCap[n, b, i], base_name="Installed Storage Power Capacity")

    @constraint(emp, installed_storage_energy_cap[(n, b)=sets.StoragesOfNode, i=sets.Period; (n, b, i) in keys(par.storENMaxInstalledCap)],
        storENInstalledCap[n, b, i] <= par.storENMaxInstalledCap[n, b, i], base_name="Installed Storage Energy Capacity")

    @constraint(emp, power_energy_relate[(n, b)=sets.StoragesOfNode, i=sets.Period; b in sets.DependentStorage],
        storPWInstalledCap[n, b, i] <= par.storagePowToEnergy[b] * storENInstalledCap[n, b, i], base_name="Power-to-Energy Storage Relation")

    if opts.HYDROGEN
        @constraint(emp, NoH2Sale1[n=sets.Node, b=sets.Storage, h=sets.Operationalhour, i=sets.Period, sc=sets.Scenario; b ∉ sets.AvailableSale && ((n, b), h, i, sc) in eachindex(amountsold)],
            amountsold[(n, b), h, i, sc] == 0, base_name="No Hydrogen sale if not available")

        if (opts.USUAL || opts.AMBITIOUS || opts.MODERATE == 1) && (opts.H2MAX == true)

            @constraint(emp, H2MaximumSale[n=sets.Node, b=sets.StorageHydrogen, h=sets.Operationalhour, i=sets.Period, sc=sets.Scenario; b in sets.AvailableSale && (n, b, i) in keys(par.MaxHydrogenDemand)],
                sum(par.sceProbab[w] * par.seasScale[s] * amountsold[(n, b), h, i, w] * par.storageDischargeEff[b] * par.storageChargeEff[b] for (s, h) in sets.HoursOfSeason for w in sets.Scenario) <= par.MaxHydrogenDemand[n, b, i], base_name="Maximum Hydrogen Sale")
                # sum(par.sceProbab[w] *amountsold[(n, b), h, i, w] * par.storageDischargeEff[b]* par.storageChargeEff[b]  for (s, h) in sets.HoursOfSeason for w in sets.Scenario) <= par.MaxHydrogenDemand[n, b, i], base_name="Maximum Hydrogen Sale")
        end

        if (opts.USUAL || opts.AMBITIOUS || opts.MODERATE == 1) && (opts.H2MIN == true)
            @constraint(emp, H2MinimumSale[n=sets.Node, b=sets.StorageHydrogen, h=sets.Operationalhour, i=sets.Period, sc=sets.Scenario; b in sets.AvailableSale && (n, b, i) in keys(par.MaxHydrogenDemand)],
                sum(par.sceProbab[w] * par.seasScale[s] * amountsold[(n, b), h, i, w] * par.storageDischargeEff[b] * par.storageChargeEff[b] for (s, h) in sets.HoursOfSeason for w in sets.Scenario) >= par.MaxHydrogenDemand[n, b, i], base_name="Minimum Hydrogen Sale")
        end


        @constraint(emp, storageEnergyBalanceRuleInitialH2[(n, b)=sets.StoragesOfHydrogen, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h in sets.FirstHoursOfRegSeason || h in sets.FirstHoursOfPeakSeason],
            par.storOperationalInit[b] * storENInstalledCap[n, b, i] + par.storageChargeEff[b] * storCharge[n, b, h, i, w] - storDischarge[n, b, h, i, w] - storOperational[n, b, h, i, w] + storMovedIn[n, b, h, i, w] - storMovedOut[n, b, h, i, w] - amountsold[(n, b), h, i, w] == 0, base_name="Storage Energy Balance Initial Hour Hydrogen")


        @constraint(emp, storageEnergyBalanceRuleLaterH2[(n, b)=sets.StoragesOfHydrogen, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; h ∉ sets.FirstHoursOfRegSeason && h ∉ sets.FirstHoursOfPeakSeason],
            par.storageBleedEff[b] * storOperational[n, b, (h-1), i, w] + par.storageChargeEff[b] * storCharge[n, b, h, i, w] - storDischarge[n, b, h, i, w] - storOperational[n, b, h, i, w] + storMovedIn[n, b, h, i, w] - storMovedOut[n, b, h, i, w] - amountsold[(n, b), h, i, w] == 0, base_name="Storage Energy Balance Later Hours Hydrogen")
    end

    # Transmission Constraints
    @constraint(emp, transmission_cap1[(n1, n2)=sets.DirectionalLink, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; (n1, n2) in sets.BidirectionalArc],
        transmissionOperational[n1, n2, h, i, w] <= transmissionInstalledCap[n1, n2, i], base_name="Transmission Capacity 1")

    @constraint(emp, transmission_cap2[(n1, n2)=sets.DirectionalLink, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; (n2, n1) in sets.BidirectionalArc],
        transmissionOperational[n2, n1, h, i, w] <= transmissionInstalledCap[n2, n1, i], base_name="Transmission Capacity 2")

    @constraint(emp, installedCapDefinitionTrans[(n1, n2)=sets.BidirectionalArc, i=sets.Period; (n1, n2, i) in sets.NodeNodeTransm],
        sum(transmissionInvCap[n1, n2, j] for j in sets.Period if j >= 1 + i - par.transmissionLifetime[n1, n2] / par.LeapYearsInvestment && j >= 1 && j <= i) - transmissionInstalledCap[n1, n2, i] + par.transmissionInitCap[n1, n2, i] == 0, base_name="Installed Transmission Capacity")
    @constraint(emp, investment_trans_cap[(n1, n2)=sets.BidirectionalArc, i=sets.Period; (n1, n2, i) in sets.NodeNodeTransm],
        transmissionInvCap[n1, n2, i] <= par.transmissionMaxBuiltCap[n1, n2, 1], base_name="Investment Transmission Capacity")

    @constraint(emp, installed_trans_cap[n1=sets.Node, n2=sets.Node, i=sets.Period; (n1, n2, i) in sets.NodeNodeTransm],
        transmissionInstalledCap[n1, n2, i] <= par.transmissionMaxInstalledCap[n1, n2, i], base_name="Installed Transmission Capacity")

    if opts.HYDROGEN_TRANSPORT
        @constraint(emp, transmission_cap1_H2[(n1, n2)=sets.DirectionalLink_H2, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; (n1, n2) in sets.BidirectionalArc_H2],
            transmissionOperational_H2[n1, n2, h, i, w] <= transmissionInstalledCap_H2[n1, n2, i], base_name="Transmission Capacity 1 Hydrogen")

        @constraint(emp, transmission_cap2_H2[(n1, n2)=sets.DirectionalLink_H2, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; (n2, n1) in sets.BidirectionalArc_H2],
            transmissionOperational_H2[n2, n1, h, i, w] <= transmissionInstalledCap_H2[n2, n1, i], base_name="Transmission Capacity 2 Hydrogen")

        @constraint(emp, installedCapDefinitionTrans_H2[(n1, n2)=sets.BidirectionalArc_H2, i=sets.Period; (n1, n2, i) in eachindex(par.transmissionMaxInstalledCap_H2)],
            sum(transmissionInvCap_H2[n1, n2, j] for j in sets.Period if j >= 1 + i - par.transmissionLifetime_H2[n1, n2] / par.LeapYearsInvestment && j >= 1 && j <= i) - transmissionInstalledCap_H2[n1, n2, i] + par.transmissionInitCap_H2[n1, n2, i] == 0, base_name="Installed Transmission Capacity Hydrogen")

        @constraint(emp, investment_trans_cap_H2[(n1, n2)=sets.BidirectionalArc_H2, i=sets.Period],
            transmissionInvCap_H2[n1, n2, i] <= par.transmissionMaxBuiltCap_H2[n1, n2, i], base_name="Investment Transmission Capacity Hydrogen")

        @constraint(emp, installed_trans_cap_H2[n1=sets.Node, n2=sets.Node, i=sets.Period; (n1, n2, i) in eachindex(par.transmissionMaxInstalledCap_H2)],
            transmissionInstalledCap_H2[n1, n2, i] <= par.transmissionMaxInstalledCap_H2[n1, n2, i], base_name="Installed Transmission Capacity Hydrogen")
        @constraint(emp, transmission_node_H2_1[n1=sets.Node, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario],
            sum(storMovedIn[n1, b, h, i, w] for (n1, b) ∈ sets.StoragesOfHydrogen) == sum(transmissionOperational_H2[n1, n2, h, i, w] for n2 ∈ sets.Node if (n1, n2) in sets.DirectionalLink_H2), base_name="Transmission Node Hydrogen In")


        @constraint(emp, transmission_node_H2_2[n1=sets.Node, h=sets.Operationalhour, i=sets.Period, w=sets.Scenario; n1 in [n[1] for n in sets.DirectionalLink_H2]],
            sum(storMovedOut[n1, b, h, i, w] for (n1, b) ∈ sets.StoragesOfHydrogen) == sum(transmissionOperational_H2[n2, n1, h, i, w] for n2 ∈ sets.Node if (n2, n1) in sets.DirectionalLink_H2), base_name="Transmission Node Hydrogen Out")
    end

    # For each constraint in emp, check if its empty and notify this
    for c in keys(emp.obj_dict)
        if !isa(emp.obj_dict[c], ConstraintRef)
            if length(emp.obj_dict[c]) == 0 && !(occursin("v_", string(c)))
                println("Constraint $(c) is empty.")
            end
        end
    end

    println("Objective and constraints read...")

    println("----------------------Problem Statistics---------------------")
    if opts.HEATMODULE == 1 println("Heat module activated") end
    if opts.EVMODULE == 1 println("EV module activated") end

    println("")
    println("Nodes: "* string(length(sets.Node)))
    println("Lines: "* string(length(sets.BidirectionalArc)))
    println("")
    println("GeneratorTypes: "* string(length(sets.Generator)))
    if opts.HEATMODULE == 1
        println("GeneratorEL: "* string(length(sets.GeneratorEL)))
        println("GeneratorTR: "* string(length(sets.GeneratorTR)))
    end

    println("TotalGenerators: "* string(length(sets.GeneratorsOfNode)))
    println("StorageTypes: "* string(length(sets.Storage)))
    println("TotalStorages: "* string(length(sets.StoragesOfNode)))
    if opts.HEATMODULE == 1 println("ElToHeatConverters: "* string(length(sets.ElToHeat))) end
    println("")
    println("InvestmentYears: "* string(length(sets.Period)))
    println("Scenarios: "* string(length(sets.Scenario)))
    println("TotalOperationalHoursPerScenario: "* string(length(sets.Operationalhour)))
    println("TotalOperationalHoursPerInvYear: " * string(length(sets.Operationalhour) * length(sets.Scenario)))
    println("Seasons: "* string(length(sets.Season)))
    println("RegularSeasons: "* string(length(sets.FirstHoursOfRegSeason)))
    println("LengthOfRegSeason: "*string(value(par.lengthRegSeason)))
    println("PeakSeasons: "* string(length(sets.FirstHoursOfPeakSeason)))
    println("LengthOfPeakSeason: "*string(value(par.lengthPeakSeason)))
    println("")
    println("Discount rate: "*string(value(par.discountrate)))
    println("Operational discount scale: "*string(value(par.operationalDiscountRate)))
    println("--------------------------------------------------------------")

    print("Solving...")
end
=#
