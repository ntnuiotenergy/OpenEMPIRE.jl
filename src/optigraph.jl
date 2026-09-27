using JuMP
using Plasmo

function create_master_node!(
    master, 
    sets, #nodes, generators, storage, technologies, etc.
    par, #model parameters
    periods, #strategic + operational time structure
    discounter, #objective discounting
)

    N = nodes(sets)
    G = generators(sets)
    S = storages(sets)
    SP = strat_periods(periods)
    HUB = collect(offshore_energy_hubs(sets))

    #INVESTMENT VARIABLES
    @variable(master, genInvCap[N, G, SP] >= 0)
    @variable(master, transmissionInvCap[N, N, SP] >= 0)
    @variable(master, offshoreConvInvCap[HUB, SP] >= 0)
    @variable(master, storPWInvCap[N, S, SP] >= 0)
    @variable(master, storENInvCap[N, S, SP] >= 0)

    #INSTALLED CAPACITY VARIABLES
    @variable(master, genInstalledCap[N, G, SP] >= 0)
    @variable(master, transmissionInstalledCap[N, N, SP] >= 0)
    @variable(master, offshoreConvInstalledCap[HUB, SP] >= 0)
    @variable(master, storPWInstalledCap[N, S, SP] >= 0)
    @variable(master, storENInstalledCap[N, S, SP] >= 0)

    #BENDERS VARIABLES
    #@variable(master, θ[SP] >= 0)

    #INVESTMENT CONSTRIAINTS
    #Constraint 2 for generators
    @constraint(
        master,
        installed_cap_gen[
            n in N,
            g in generators(sets, n),
            sp in SP,
        ],
        sum(
            genInvCap[n, g, spp]
            for spp in SP
            if duration_aggr(spp, sp, SP) <=
            gen_lifetime(par, g) - duration_strat(sp)
        )
        +
        gencap_init(par, n, g, sp)
        ==
        genInstalledCap[n, g, sp]
    )

    #Constraint 2 for transmission
    @constraint(
        master,
        trans_track_cap[
            (m, n) in bidir_arcs(sets),
            sp in SP
        ],
        sum(
            transmissionInvCap[m, n, spp]
            for spp in SP
            if duration_aggr(spp, sp, SP) <=
            trans_lifetime(par, m, n) - duration_strat(sp)
        )
        +
        trans_cap_init(par, m, n, sp)
        ==
        transmissionInstalledCap[m, n, sp]
    )

    #Constraint 2 for storage energy capacity
    @constraint(
        master,
        storage_installed_cap_en[
            n in N,
            s in storages(sets, n),
            sp in SP
        ],
        sum(
            storENInvCap[n, s, spp]
            for spp in SP
            if duration_aggr(spp, sp, SP) <=
            lifetime_storage(par, s) - duration_strat(sp)
        )
        +
        stor_cap_init_en(par, n, s, sp)
        ==
        storENInstalledCap[n, s, sp]
    )

    #Constraint 2 for storage power capacity
    @constraint(
        master,
        storage_installed_cap_pow[
            n in N,
            s in storages(sets, n),
            sp in SP
        ],
        sum(
            storPWInvCap[n, s, spp]
            for spp in SP
            if duration_aggr(spp, sp, SP) <=
            lifetime_storage(par, s) - duration_strat(sp)
        )
        +
        stor_cap_init_pow(par, n, s, sp)
        ==
        storPWInstalledCap[n, s, sp]
    )

    #Constraint 2 for offshore converter capacity
    @constraint(
        master,
        offshore_conv_track_cap[
            hub in HUB,
            sp in SP
        ],
        sum(
            offshoreConvInvCap[hub, spp]
            for spp in SP
            if duration_aggr(spp, sp, SP) <=
            DEFAULT_OFFSHORE_CONV_LIFETIME - duration_strat(sp)
        )
        ==
        offshoreConvInstalledCap[hub, sp]
    )

    #Constraint 12 for generators
    @constraint(
        master,
        max_inv_tech[
            n in N,
            tc in techs(sets),
            sp in SP,
        ],
        sum(
            genInvCap[n, g, sp]
            for g in generators_tech(sets, n, tc)
        )
        <= max_build_cap(par, n, tc, sp)
    )

    #Constraint 12 for storage power capacity
    @constraint(
        master,
        storage_max_inv_pow[
            n in N, s in storages(sets, n),
            sp in SP;
            stor_pw_max_build_cap(par, n, s, sp) !== nothing,
        ],
        storPWInvCap[n, s, sp]
        <= stor_pw_max_build_cap(par, n, s, sp)
    )

    #Constraint 12 for storage energy capacity
    @constraint(
        master,
        storage_max_inv_en[
            n in N, s in storages(sets, n),
            sp in SP;
            stor_en_max_build_cap(par, n, s, sp) !== nothing,
        ],
        storENInvCap[n, s, sp]
        <= stor_en_max_build_cap(par, n, s, sp)
    )

    # Constraint 12 for transmission
    @constraint(
        master,
        trans_max_capacity[
            (m, n) in bidir_arcs(sets),
            sp in SP;
            !isnothing(trans_max_build_cap(par, m, n, sp))
        ],
        transmissionInvCap[m, n, sp]
        <=
        trans_max_build_cap(par, m, n, sp)
    )

    #Constraint 13 for generators
    @constraint(
        master,
        max_inst_tech[
            n in N,
            tc in techs(sets),
            sp in SP,
        ],
        sum(
            genInstalledCap[n, g, sp]
            for g in generators_tech(sets, n, tc)
        )
        <= max_inst_cap(par, n, tc, sp)
    )

    #Constraint 13 for storage power capacity
    @constraint(
        master,
        storage_max_inst_pow[
            n in N,
            s in storages(sets, n),
            sp in SP;
            stor_pw_max_inst_cap(par, n, s, sp) !== nothing,
        ],
        storPWInstalledCap[n, s, sp]
        <= stor_pw_max_inst_cap(par, n, s, sp)
    )

    #Constraint 13 for storage energy capacity
    @constraint(
        master,
        storage_max_inst_en[
            n in N,
            s in storages(sets, n),
            sp in SP;
            stor_en_max_inst_cap(par, n, s, sp) !== nothing,
        ],
        storENInstalledCap[n, s, sp]
        <= stor_en_max_inst_cap(par, n, s, sp)
    )

    # Constraint 13 for transmission
    @constraint(
        master,
        trans_installed_cap[
            (m, n) in bidir_arcs(sets),
            sp in SP;
            !isnothing(trans_max_inst_cap(par, m, n, sp))
        ],
        transmissionInstalledCap[m, n, sp]
        <=
        trans_max_inst_cap(par, m, n, sp)
    )
    
    #Constraint 14
    @constraint(
        master,
        storage_power_energy_relation[
            n in N,
            s in storages(sets, n),
            sp in SP;
            s in dependent_storages(sets)
        ],
        master[:storPWInstalledCap][n, s, sp]
        ==
        power_to_energy(par, s) *
        master[:storENInstalledCap][n, s, sp]
    )

    # Offshore wind-farm transmission capacity constraint
    @constraint(
        master,
        wind_farm_transmission_cap[
            (m, n) in arcs(sets),
            sp in SP;
            !isnothing(_offshore_endpoint(sets, m, n))
        ],
        master[:transmissionInstalledCap][
            _canonical_arc(m, n)...,
            sp
        ]
        <=
        sum(
            master[:genInstalledCap][
                _offshore_endpoint(sets, m, n),
                g,
                sp
            ]
            for g in generators(
                sets,
                _offshore_endpoint(sets, m, n)
            );
            init = 0
        )
    )

    @objective(
        master,
        Min,
        sum(
            objective_weight(sp, discounter) *
            (
                sum(
                    gen_invest_cost(par, g, sp) *
                    genInvCap[n, g, sp]
                    for n in N
                    for g in generators(sets, n)
                )
                +
                sum(
                    stor_pw_invest_cost(par, s, sp) *
                    storPWInvCap[n, s, sp]
                    +
                    stor_en_invest_cost(par, s, sp) *
                    storENInvCap[n, s, sp]
                    for n in N
                    for s in storages(sets, n)
                )
                +
                sum(
                    trans_invest_cost(par, m, n, sp) *
                    transmissionInvCap[m, n, sp]
                    for (m, n) in bidir_arcs(sets);
                    init = 0.0
                )
                +
                sum(
                    offshore_conv_invest_cost(par, sp) *
                    master[:offshoreConvInvCap][hub, sp]
                    for hub in HUB;
                    init = 0.0
                )
            )
            for sp in SP
        )
        #+
        #@sum(θ[sp] for sp in SP)
    )
end

function create_subproblem_node!(
    node,
    sets,
    par,
    periods,
    sp,
    discounter,
)

    N = nodes(sets)
    G = generators(sets)
    S = storages(sets)
    HUB = collect(offshore_energy_hubs(sets))

    #OPERATIONAL VARIABLES
    @variable(node, genOperational[N, G, t in sp] >= 0)
    @variable(node, transmissionOperational[N, N, t in sp] >= 0)
    @variable(node, storCharge[N, S, t in sp] >= 0)
    @variable(node, storDischarge[N, S, t in sp] >= 0)
    @variable(node, storOperational[N, S, t in sp] >= 0)
    @variable(node, loadShed[N, t in sp] >= 0)

    #EMISSIONS
    @variable(node, emissions[N, sc in 1:_opscenario_count(sp)] >= 0)

    #CONSTRAINTS
    #Constraint 1 flow balance
    @constraint(
        node,
        flow_balance[
            n in N,
            t in sp
        ],
        sum(
            node[:genOperational][n, g, t]
            for g in generators(sets, n)
        )
        +
        sum(
            discharge_eff(par, s) * node[:storDischarge][n, s, t]
            -
            node[:storCharge][n, s, t]
            for s in storages(sets, n)
        )
        +
        # incoming transmission
        sum(
            line_eff(par, m, n) *
            node[:transmissionOperational][m, n, t]
            for m in N
            if (m, n) in arcs(sets)
        )
        -
        # outgoing transmission
        sum(
            node[:transmissionOperational][n, m, t]
            for m in N
            if (n, m) in arcs(sets)
        )
        +
        node[:loadShed][n, t]
        ==
        load(par, n, t)
    )

    #Constraint 9
    @constraint(
        node,
        gen_hydro_limit[
            n in N,
            g in generators(sets, n),
            sc in opscenarios(sp);
            is_reg_hydro(sets, g)
        ],
        sum(
            node[:genOperational][n, g, t]
            for t in sc
        )
        <=
        max_hydro_gen(par, n, sc)
    )

    #Constraint 10
    @constraint(
        node,
        gen_hydro_node_limit[
            n in N;
            !isnothing(max_hydro_node(par, n))
        ],
        sum(
            multiple_strat(sp, t) *
            probability(t) *
            node[:genOperational][n, g, t]
            for g in generators(sets, n)
            if is_hydro(sets, g)
            for t in sp
        )
        <=
        max_hydro_node(par, n)
    )

    # Biomass availability constraint
    if par.availableBioEnergy !== nothing
        @constraint(
            node,
            max_bio_availability[
                sc in 1:_opscenario_count(sp)
            ],
            sum(
                multiple_strat(sp, t) *
                (occursin("cofiring", lowercase(g)) ? 0.1 : 1.0) *
                node[:genOperational][n, g, t] *
                3.6 / par.genEfficiency[g][sp]
                for n in N
                for g in generators(sets, n)
                if occursin("bio", lowercase(g))
                for rp in repr_periods(sp)
                for (scenario_index, scenario) in enumerate(opscenarios(rp))
                if scenario_index == sc
                for t in scenario;
                init = 0.0
            ) <= available_bioenergy(par, sp)
        )
    end

    # Biomethane availability constraint
    if !isempty(par.genMaxBiomethaneAvailability)
        @constraint(
            node,
            gen_fuel_use_limit[
                n in N,
                sc in 1:_opscenario_count(sp)
            ],
            sum(
                multiple_strat(sp, t) *
                node[:genOperational][n, g, t] *
                3.6 / par.genEfficiency[g][sp]
                for g in generators(sets, n)
                if occursin("biomethane", lowercase(g))
                for rp in repr_periods(sp)
                for (scenario_index, scenario) in enumerate(opscenarios(rp))
                if scenario_index == sc
                for t in scenario;
                init = 0.0
            ) <= 1e3 * max_biomethane_availability(par, n, sp)
        )
    end

    # Emissions
    if par.CO2cap !== nothing

        @constraint(
            node,
            node_emission[
                n in N,
                sc in 1:_opscenario_count(sp)
            ],
            node[:emissions][n, sc] ==
                sum(
                    multiple_strat(sp, t) *
                    co2_content(par, g) *
                    (3.6 / par.genEfficiency[g][sp]) *
                    node[:genOperational][n, g, t]
                    for g in generators(sets, n)
                    for rp in repr_periods(sp)
                    for (scenario_index, scenario) in enumerate(opscenarios(rp))
                    if scenario_index == sc
                    for t in scenario;
                    init = 0.0
                )
        )

        @constraint(
            node,
            emission_cap[
                sc in 1:_opscenario_count(sp);
                co2_cap(par, sp) !== nothing
            ],
            sum(
                node[:emissions][n, sc]
                for n in N;
                init = 0.0
            ) <= 1e6 * co2_cap(par, sp)
        )
    end

    #Filtered constraint 3 - Not linking
    @constraint(
        node,
        [
            n in nodes(sets),
            g in generators(sets, n),
            t in sp;
            gencap_avail(par, n, g, t) == 0
        ],
        node[:genOperational][n, g, t] <= 0
    )

    #OBJECTIVE FUNCTION
    @objective(
        node,
        Min,
        sum(
            objective_weight(t, discounter; type = "avg_year") *
            (
                sum(
                    lost_load_cost(par, n, t) *
                    node[:loadShed][n, t]
                    for n in N
                )
                +
                sum(
                    gen_marginal_cost(par, g, t) *
                    node[:genOperational][n, g, t]
                    for n in N
                    for g in generators(sets, n)
                )
            )
            for t in sp
        ) 
    )

end

function create_linking_constraints!(
    graph,
    master,
    node,
    sets,
    par,
    sp,
)

    N = nodes(sets)
    HUB = collect(offshore_energy_hubs(sets))

    #Filtered constraint 3
    @linkconstraint(
        graph,
        [
            n in nodes(sets),
            g in generators(sets, n),
            t in sp;
            gencap_avail(par, n, g, t) > 0
        ],
        node[:genOperational][n, g, t]
        <=
        gencap_avail(par, n, g, t) *
        master[:genInstalledCap][n, g, sp]
    )

    #=
    #Constraint 3 old
    @linkconstraint(
        graph,
        [
            n in nodes(sets),
            g in generators(sets, n),
            t in sp
        ],
        node[:genOperational][n, g, t]
        <=
        gencap_avail(par, n, g, t) *
        master[:genInstalledCap][n, g, sp]
    )
    =#

    #Constraint 4
    @linkconstraint(
        graph,
        [
            n in nodes(sets),
            g in generators(sets, n),
            (prev, t) in withprev(sp);
            !isnothing(prev) && is_thermal(sets, g)
        ],
        node[:genOperational][n, g, t]
        <=
        node[:genOperational][n, g, prev]
        +
        rampup_cap(par, g) *
        master[:genInstalledCap][n, g, sp]
    )

    #Constraint 5
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            (prev, t) in withprev(sp)
        ],
        (
            isnothing(prev) ?
            storage_init(par, s) *
            master[:storENInstalledCap][n, s, sp] :
            bleed_eff(par, s) *
            node[:storOperational][n, s, prev]
        )
        +
        charge_eff(par, s) *
        node[:storCharge][n, s, t]
        -
        node[:storDischarge][n, s, t]
        ==
        node[:storOperational][n, s, t]
    )

    #Constraint 6
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            t in sp
        ],
        node[:storOperational][n, s, t]
        <=
        master[:storENInstalledCap][n, s, sp]
    )

    #Constraint 7
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            t in sp
        ],
        node[:storCharge][n, s, t]
        <=
        master[:storPWInstalledCap][n, s, sp]
    )

    #Constraint 8
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            t in sp
        ],
        node[:storDischarge][n, s, t]
        <=
        storage_disc_to_char_ratio(par, s) *
        master[:storPWInstalledCap][n, s, sp]
    )

    #Constraint 11
    @linkconstraint(
        graph,
        [
            (m, n) in arcs(sets),
            t in sp
        ],
        node[:transmissionOperational][m, n, t]
        <=
        (
            is_bidir(m, n) ?
            master[:transmissionInstalledCap][m, n, sp] :
            master[:transmissionInstalledCap][n, m, sp]
        )
    )

    #storage cyclic condition
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            sc in opscenarios(sp)
        ],
        node[:storOperational][n, s, last(sc)]
        ==
        storage_init(par, s) *
        master[:storENInstalledCap][n, s, sp]
    )

    # Offshore hub: incoming transmission
    @linkconstraint(
        graph,
        [
            hub in HUB,
            t in sp
        ],
        sum(
            node[:transmissionOperational][m, hub, t]
            for m in N
            if (m, hub) in arcs(sets)
        )
        <=
        master[:offshoreConvInstalledCap][hub, sp]
    )

    # Offshore hub: outgoing transmission
    @linkconstraint(
        graph,
        [
            hub in HUB,
            t in sp
        ],
        sum(
            node[:transmissionOperational][hub, n, t]
            for n in N
            if (hub, n) in arcs(sets)
        )
        <=
        master[:offshoreConvInstalledCap][hub, sp]
    )

end

function create_benders_graph(sets, par, periods, discounter)
    graph = OptiGraph() #creates the empty graph

    SP = strat_periods(periods)

    #@optinode(graph, master) #Adds the master node to the graph
    master = add_node(graph)
    set_name(master, :master)

    create_master_node!(
        master,
        sets,
        par,
        periods,
        discounter,
    )


    subproblem_nodes = Dict() #Save nodes so that function can return them 

    for sp in SP
        #@optinode(graph, node)
        node = add_node(graph)
        set_name(node, :node)

        subproblem_nodes[sp] = node

        create_subproblem_node!(
            node,
            sets,
            par,
            periods,
            sp,
            discounter,
        )

        create_linking_constraints!(
            graph,
            master,
            node,
            sets,
            par,
            sp,
        )
    end
    return graph, master, subproblem_nodes
end

