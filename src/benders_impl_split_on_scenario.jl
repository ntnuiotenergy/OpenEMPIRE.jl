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
    )
end

function create_scenario_node!(
    node,
    sets,
    par,
    periods,
    sp,
    scenario_periods,
    discounter,
)

    N = nodes(sets)
    G = generators(sets)
    S = storages(sets)

    num_rp = length(scenario_periods)

    # =====================================================
    # OPERATIONAL VARIABLES
    # =====================================================

    @variable(
        node,
        genOperational[
            n in N,
            g in G,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
        node,
        transmissionOperational[
            n in N,
            m in N,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
        node,
        storCharge[
            n in N,
            s in S,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
        node,
        storDischarge[
            n in N,
            s in S,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
        node,
        storOperational[
            n in N,
            s in S,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
        node,
        loadShed[
            n in N,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ] >= 0
    )

    @variable(
    node,
    nodeEmission[n in N]
)

    # =====================================================
    # CONSTRAINT 1: FLOW BALANCE
    # =====================================================

    @constraint(
        node,
        flow_balance[
            n in N,
            rp in 1:num_rp,
            t in scenario_periods[rp]
        ],
        sum(
            node[:genOperational][n, g, rp, t]
            for g in generators(sets, n)
        )
        +
        sum(
            discharge_eff(par, s) *
            node[:storDischarge][n, s, rp, t]
            -
            node[:storCharge][n, s, rp, t]
            for s in storages(sets, n)
        )
        +
        sum(
            line_eff(par, m, n) *
            node[:transmissionOperational][m, n, rp, t]
            for m in N
            if (m, n) in arcs(sets)
        )
        -
        sum(
            node[:transmissionOperational][n, m, rp, t]
            for m in N
            if (n, m) in arcs(sets)
        )
        +
        node[:loadShed][n, rp, t]
        ==
        load(par, n, t)
    )


    # =====================================================
    # CONSTRAINT 9: HYDRO LIMIT
    # =====================================================

    @constraint(
        node,
        gen_hydro_limit[
            n in N,
            g in generators(sets, n),
            rp in 1:num_rp;
            is_reg_hydro(sets, g)
        ],
        sum(
            node[:genOperational][n, g, rp, t]
            for t in scenario_periods[rp]
        )
        <=
        max_hydro_gen(
            par,
            n,
            scenario_periods[rp]
        )
    )


    # =====================================================
    # CONSTRAINT 3: GENERATOR AVAILABILITY
    # =====================================================

    @constraint(
        node,
        generator_availability[
            n in N,
            g in generators(sets, n),
            rp in 1:num_rp,
            t in scenario_periods[rp];
            gencap_avail(par, n, g, t) == 0
        ],
        node[:genOperational][n, g, rp, t] <= 0
    )


    # =====================================================
    # CONSTRAINT 5: STORAGE BALANCE
    #
    # IMPORTANT:
    # withprev() is applied separately to each RP.
    # =====================================================

    @constraint(
        node,
        storage_balance[
            n in N,
            s in storages(sets, n),
            rp in 1:num_rp,
            (prev, t) in withprev(scenario_periods[rp]);
            !isnothing(prev)
        ],
        bleed_eff(par, s) *
        node[:storOperational][n, s, rp, prev]
        +
        charge_eff(par, s) *
        node[:storCharge][n, s, rp, t]
        -
        node[:storDischarge][n, s, rp, t]
        ==
        node[:storOperational][n, s, rp, t]
    )


    # =====================================================
    # CONSTRAINT 4: RAMP-UP = 0
    # =====================================================

    @constraint(
        node,
        ramp_up_zero[
            n in N,
            g in generators(sets, n),
            rp in 1:num_rp,
            (prev, t) in withprev(scenario_periods[rp]);
            !isnothing(prev) &&
            is_thermal(sets, g) &&
            rampup_cap(par, g) == 0
        ],
        node[:genOperational][n, g, rp, t]
        <=
        node[:genOperational][n, g, rp, prev]
    )

    # Bioenergy availability
    if par.availableBioEnergy !== nothing
        @constraint(
            node,
            max_bio_availability,
            sum(
                multiple_strat(sp, t) *
                (occursin("cofiring", lowercase(g)) ? 0.1 : 1.0) *
                node[:genOperational][n, g, rp, t] *
                3.6 / par.genEfficiency[g][sp]
                for n in N
                for g in generators(sets, n)
                if occursin("bio", lowercase(g))
                for rp in 1:length(repr_periods(sp))
                for t in scenario_periods[rp]
            ) <= available_bioenergy(par, sp)
        )
    end

    # Biomethane fuel limit
    if !isempty(par.genMaxBiomethaneAvailability)
        @constraint(
            node,
            gen_fuel_use_limit[
                n in N
            ],
            sum(
                multiple_strat(sp, t) *
                node[:genOperational][n, g, rp, t] *
                3.6 / par.genEfficiency[g][sp]
                for g in generators(sets, n)
                if occursin("biomethane", lowercase(g))
                for rp in 1:length(repr_periods(sp))
                for t in scenario_periods[rp]
            ) <= 1e3 * max_biomethane_availability(par, n, sp)
        )
    end

    # CO2 emissions
    if par.CO2cap !== nothing
        @variable(node, nodeEmission[n in N])

        @constraint(
            node,
            node_emission[n in N],
            node[:nodeEmission][n] ==
                sum(
                    multiple_strat(sp, t) *
                    co2_content(par, g) *
                    (3.6 / par.genEfficiency[g][sp]) *
                    node[:genOperational][n, g, rp, t]
                    for g in generators(sets, n)
                    for rp in 1:length(repr_periods(sp))
                    for t in scenario_periods[rp]
                )
        )

        @constraint(
            node,
            emission_cap,
            sum(
                node[:nodeEmission][n]
                for n in N
            ) <= 1e6 * co2_cap(par, sp)
        )
    end

    # Hydro node limit (constraint 10) --> Reformulated from the original to allow for decomposition of the problem into scenarios
    @constraint(
        node,
        gen_hydro_node_limit[
            n in N;
            !isnothing(max_hydro_node(par, n))
        ],
        sum(
            multiple_strat(sp, t) *
            node[:genOperational][n, g, rp, t]
            for g in generators(sets, n)
            if is_hydro(sets, g)
            for rp in 1:length(repr_periods(sp))
            for t in scenario_periods[rp]
        ) <= max_hydro_node(par, n)
    )


    # =====================================================
    # OBJECTIVE
    # =====================================================

    @objective(
        node,
        Min,
        sum(
            objective_weight(
                t,
                discounter;
                type = "avg_year"
            )
            *
            (
                sum(
                    lost_load_cost(par, n, t) *
                    node[:loadShed][n, rp, t]
                    for n in N
                )
                +
                sum(
                    gen_marginal_cost(par, g, t) *
                    node[:genOperational][n, g, rp, t]
                    for n in N
                    for g in generators(sets, n)
                )
            )
            for rp in 1:num_rp
            for t in scenario_periods[rp]
        )
    )

end

function create_linking_constraints!(
    graph,
    master,
    scenario_node,
    sets,
    par,
    sp,
    scenario_periods,
)

    N = nodes(sets)
    HUB = collect(offshore_energy_hubs(sets))

    #Filtered constraint 3
    @linkconstraint(
        graph,
        [
            n in N,
            g in generators(sets, n),
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp];
            gencap_avail(par, n, g, t) > 0
        ],
        scenario_node[:genOperational][n, g, rp, t]
        <=
        gencap_avail(par, n, g, t) *
        master[:genInstalledCap][n, g, sp]
    )


    #Constraint 4 (filtered for only existing rampup capacities)
    @linkconstraint(
        graph,
        [
            n in N,
            g in generators(sets, n),
            rp in 1:length(scenario_periods),
            (prev, t) in withprev(scenario_periods[rp]);
            !isnothing(prev) &&
            is_thermal(sets, g) &&
            rampup_cap(par, g) > 0
        ],
        scenario_node[:genOperational][n, g, rp, t]
        <=
        scenario_node[:genOperational][n, g, rp, prev]
        +
        rampup_cap(par, g) *
        master[:genInstalledCap][n, g, sp]
    )

    #constraint 5 --> linking constraint version
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            rp in 1:length(scenario_periods),
            (prev, t) in withprev(scenario_periods[rp]);
            isnothing(prev)
        ],
        storage_init(par, s) *
        master[:storENInstalledCap][n, s, sp]
        +
        charge_eff(par, s) *
        scenario_node[:storCharge][n, s, rp, t]
        -
        scenario_node[:storDischarge][n, s, rp, t]
        ==
        scenario_node[:storOperational][n, s, rp, t]
    )

    #Constraint 6
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        scenario_node[:storOperational][n, s, rp, t]
        <=
        master[:storENInstalledCap][n, s, sp]
    )

    
    #Constraint 7
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        scenario_node[:storCharge][n, s, rp, t]
        <=
        master[:storPWInstalledCap][n, s, sp]
    )

    #Constraint 8
    @linkconstraint(
        graph,
        [
            n in N,
            s in storages(sets, n),
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        scenario_node[:storDischarge][n, s, rp, t]
        <=
        storage_disc_to_char_ratio(par, s) *
        master[:storPWInstalledCap][n, s, sp]
    )

    #Constraint 11
    @linkconstraint(
        graph,
        [
            (m, n) in arcs(sets),
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        scenario_node[:transmissionOperational][m, n, rp, t]
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
            rp in 1:length(scenario_periods)
        ],
        scenario_node[:storOperational][n, s, rp, last(scenario_periods[rp])]
        ==
        storage_init(par, s) *
        master[:storENInstalledCap][n, s, sp]
    )

    # Offshore hub: incoming transmission
    @linkconstraint(
        graph,
        [
            hub in HUB,
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        sum(
            scenario_node[:transmissionOperational][m, hub, rp, t]
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
            rp in 1:length(scenario_periods),
            t in scenario_periods[rp]
        ],
        sum(
            scenario_node[:transmissionOperational][hub, n, rp, t]
            for n in N
            if (hub, n) in arcs(sets)
        )
        <=
        master[:offshoreConvInstalledCap][hub, sp]
    )

end

function create_benders_graph(sets, par, periods, discounter)

    graph = OptiGraph()

    SP = strat_periods(periods)

    # =====================================================
    # MASTER
    # =====================================================

    master_graph = OptiGraph()
    master = add_node(master_graph)

    set_name(master, :master)

    create_master_node!(
        master,
        sets,
        par,
        periods,
        discounter,
    )

    add_subgraph!(graph, master_graph)
    set_to_node_objectives(master_graph)


    # =====================================================
    # STRATEGIC-PERIOD SUBPROBLEMS
    # =====================================================

    scenario_graphs = []
    scenario_nodes = []

    for (sp_index, sp) in enumerate(SP)
        println("SP: ", sp)

        for sc_index in 1:_opscenario_count(sp)

             println(
                "Creating scenario node: SP ",
                sp_index,
                ", scenario ",
                sc_index
            )

            # Get this scenario's representative periods
            scenario_periods = [
                opscenarios(rp)[sc_index]
                for rp in repr_periods(sp)
            ]

            # Create one graph for this SP/scenario pair
            scenario_graph = OptiGraph()

            scenario_node = add_node(scenario_graph)

            set_name(
                scenario_node,
                Symbol("scenario_$(sp_index)_$(sc_index)")
            )

            # Add operational variables + constraints
            create_scenario_node!(
                scenario_node,
                sets,
                par,
                periods,
                sp,
                scenario_periods,
                discounter
            )

            set_to_node_objectives(scenario_graph)

            # Add directly to main graph
            add_subgraph!(
                graph,
                scenario_graph
            )

            # Link directly to master
            create_linking_constraints!(
                graph,
                master,
                scenario_node,
                sets,
                par,
                sp,
                scenario_periods
            )

            push!(scenario_graphs, scenario_graph)
            push!(
                scenario_nodes,
                (sp, sc_index, scenario_node)
            )
        end
    end

    return (
        graph,
        master_graph,
        master,
        scenario_graphs,
        scenario_nodes,
    )

end
