"""
    create_timestruct(
        npers,
        years_period,
        nseasons,
        hours_season,
        npeaks,
        hours_peak,
        nscens = 1;
        operational_hours_per_year = 8760,
    )

Create EMPIRE's strategic and operational time structure.

`operational_hours_per_year` is the physical duration represented by each
strategic year. It defaults to 8760 for the existing representative-period
formulation. A chronological fixture can set it to the fixture length; a
full-year chronological run uses one regular season of length 8760 and keeps
the default, which gives every modeled hour a multiplicity of one.
"""
function create_timestruct(
    npers,
    years_period,
    nseasons,
    hours_season,
    npeaks,
    hours_peak,
    nscens = 1;
    operational_hours_per_year = 8760,
)
    annual_hours = Int(operational_hours_per_year)
    annual_hours > 0 || throw(ArgumentError("operational_hours_per_year must be positive"))
    nseasons > 0 || throw(ArgumentError("nseasons must be positive"))
    hours_season > 0 || throw(ArgumentError("hours_season must be positive"))
    npeaks >= 0 || throw(ArgumentError("npeaks must be non-negative"))
    hours_peak >= 0 || throw(ArgumentError("hours_peak must be non-negative"))
    nscens > 0 || throw(ArgumentError("nscens must be positive"))

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
    peak_hours <= annual_hours || throw(ArgumentError(
        "Modeled peak hours ($peak_hours) exceed operational_hours_per_year ($annual_hours)",
    ))

    # Give each season an equal share of each year outside peak periods
    seasons_share = [(annual_hours - peak_hours) / (annual_hours * nseasons) for _ in seasons]

    # Count each modeled peak hour once per year.
    peaks_share = [hours_peak / annual_hours for _ in peaks]

    # Create representative periods for each year
    repr_periods = RepresentativePeriods(
        annual_hours,
        vcat(seasons_share, peaks_share),
        vcat(seasons, peaks),
    )

    # Return a two level structure with yearly resolution
    return TwoLevel(npers, years_period, repr_periods; op_per_strat = annual_hours)
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

    # Investment in offshore energy-hub converter capacity and tracking installed capacity.
    # Hubs generate nothing, so what limits the power they can route is the converter
    # equipment on the platform, which has to be built and paid for.
    HUB = collect(offshore_energy_hubs(sets))
    @variable(emp, offshoreConvInvCap[HUB, SP] >= 0; container = IndexedVarArray)
    @variable(emp, offshoreConvInstalledCap[HUB, SP] >= 0; container = IndexedVarArray)

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
    for n in HUB, sp in SP
        unsafe_insertvar!(offshoreConvInvCap, n, sp)
        unsafe_insertvar!(offshoreConvInstalledCap, n, sp)
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
function create_constraints(
    emp::JuMP.Model,
    sets,
    par,
    periods::TimeStructure;
    offshore_transmission_cap::Bool = true,
    include_investment_constraints::Bool = true,
    biomass_limit_flag::Bool = true,
    biomass_limit_factor::Float64 = 1.2,
    biomass_system_limit_factor::Float64 = 1.04,
    biomass_limit_scope::String = "country",
    generation_growth_limit_flag::Bool = false,
    generation_growth_limit_rate::Float64 = 0.04,
    bioccs_capacity_limit_factor::Float64 = 1.0,
    progress = nothing,
)
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

    if !include_investment_constraints
        @info "Omitting investment-only constraints for fixed-capacity evaluation"
        _report_progress(progress, "Omitting investment-only constraints")
    end

    create_generator_constraints(
        emp,
        sets,
        par,
        periods;
        include_investment_constraints,
        biomass_limit_flag,
        biomass_limit_factor,
        biomass_system_limit_factor,
        biomass_limit_scope,
        generation_growth_limit_flag,
        generation_growth_limit_rate,
        bioccs_capacity_limit_factor,
        progress,
    )
    create_storage_constraints(
        emp,
        sets,
        par,
        periods;
        include_investment_constraints,
        progress,
    )
    create_transmission_constraints(
        emp,
        sets,
        par,
        periods;
        offshore_transmission_cap,
        include_investment_constraints,
        progress,
    )
    create_emission_constraints(emp, sets, par, periods; progress)
    return nothing

end

# Calculate the total duration of all strategic periods from spp to sp (inclusive)
# Return Inf if spp < sp
"""
    offshore_conv_investment_expr(emp, sets, par, sp)

Annuitised investment cost of offshore energy-hub converter capacity built in `sp`.

Zero when the dataset has no hubs. If it has hubs but ships no converter costs the
capacity would be unpriced rather than unavailable, so that case warns instead of
silently building free converters.
"""
function offshore_conv_investment_expr(emp::JuMP.Model, sets, par, sp)
    hubs = offshore_energy_hubs(sets)
    isempty(hubs) && return zero(JuMP.AffExpr)
    cost = offshore_conv_invest_cost(par, sp)
    if cost === nothing
        @warn(
            "Offshore energy hubs are present but the dataset has no " *
            "Transmission/OffshoreConverterCapitalCost.csv, so converter capacity is " *
            "free. Add the cost table, or remove the hubs from Sets/OffshoreEnergyHub.csv.",
            maxlog = 1,
        )
        return zero(JuMP.AffExpr)
    end
    convInv = emp[:offshoreConvInvCap]
    return sum(cost * convInv[n, sp] for n in hubs; init = zero(JuMP.AffExpr))
end

function duration_aggr(sp, spp, strat_periods)
    spp < sp && return Inf
    return sum(duration_strat(p) for p in strat_periods if p >= sp && p < spp; init = 0)
end

# Python parity (empire.py `_capacity_limit_contribution`): the share of a technology
# capacity budget that one generator's capacity term consumes on the constraint's
# left-hand side. A generator named exactly "BioCCS" (case-insensitive, whitespace
# stripped) consumes `capacity / bioccs_capacity_limit_factor`, so an all-BioCCS build
# may reach `factor` x the supplied limit; every other generator is accounted 1:1.
# `factor == 1.0` returns the capacity unchanged (x / 1.0 is exact in Float64).
_capacity_limit_contribution(capacity, generator, bioccs_capacity_limit_factor) =
    lowercase(strip(string(generator))) == "bioccs" ?
        capacity / bioccs_capacity_limit_factor : capacity

function create_generator_constraints(
    emp::JuMP.Model,
    sets,
    par,
    periods::TimeStructure;
    include_investment_constraints::Bool = true,
    biomass_limit_flag::Bool = true,
    biomass_limit_factor::Float64 = 1.2,
    biomass_system_limit_factor::Float64 = 1.04,
    biomass_limit_scope::String = "country",
    generation_growth_limit_flag::Bool = false,
    generation_growth_limit_rate::Float64 = 0.04,
    bioccs_capacity_limit_factor::Float64 = 1.0,
    progress = nothing,
)
    @info "Creating generator constraints"
    _report_progress(progress, "Creating generator constraints")

    # Python parity (empire.py / config.py): bioccs_capacity_limit_factor must be > 0.
    bioccs_capacity_limit_factor > 0.0 ||
        throw(ArgumentError(
            "bioccs_capacity_limit_factor must be > 0, got $(bioccs_capacity_limit_factor)"
        ))

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
        # Apply strategic yearly availability together with operational availability.
        genOp[n, g, t] <= gen_yearly_avail(par, n, g, sp) * gencap_avail(par, n, g, t) * genCap[n, g, sp]
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

    create_bioenergy_constraints(
        emp,
        sets,
        par,
        periods;
        biomass_limit_flag,
        biomass_limit_factor,
        biomass_system_limit_factor,
        biomass_limit_scope,
        progress,
    )
    create_generation_growth_constraints(
        emp,
        sets,
        par,
        periods;
        generation_growth_limit_flag,
        generation_growth_limit_rate,
        progress,
    )

    include_investment_constraints || return nothing

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
        sum(_capacity_limit_contribution(genInv[n, g, sp], g, bioccs_capacity_limit_factor)
            for g in generators_tech(sets, n, tc)) <= max_build_cap(par, n, tc, sp)
    )

    # Minimum generator investment required for each node and technology.
    # NB: Python's nodal minimum (empire.py investment_gen_min_rule) uses a plain sum of
    # genInvCap, NOT _capacity_limit_contribution - the BioCCS headroom does not apply here.
    @info " - minimum investment constraints"
    @constraint(
        emp,
        min_inv_tech[n in N, tc in techs(sets), sp in SP; min_build_cap(par, n, tc, sp) > 0.0],
        sum(genInv[n, g, sp] for g in generators_tech(sets, n, tc)) >= min_build_cap(par, n, tc, sp)
    )

    # Constraints on maximum installed capacity for each technology
    @info " - maximum installed capacity constraints: $(length(N) * length(techs(sets)) * length(SP))"
    _report_progress(progress, "Creating generator maximum-installed-capacity constraints ($(length(N) * length(techs(sets)) * length(SP)) constraints)")
    @constraint(
        emp,
        max_inst_tech[n in N, tc in techs(sets), sp in SP],
        sum(_capacity_limit_contribution(genCap[n, g, sp], g, bioccs_capacity_limit_factor)
            for g in generators_tech(sets, n, tc)) <= max_inst_cap(par, n, tc, sp)
    )

    C = countries(sets)
    @info " - country-level generator capacity constraints"
    @constraint(
        emp,
        max_inv_tech_country[c in C, tc in techs(sets), sp in SP; haskey(par.genCountryMaxBuiltCap, (c, tc))],
        sum(
            _capacity_limit_contribution(genInv[n, g, sp], g, bioccs_capacity_limit_factor)
            for n in nodes_of_country(sets, c)
            for g in generators_tech(sets, n, tc)
        ) <= country_max_build_cap(par, c, tc, sp)
    )
    # Python's country minimum (empire.py investment_country_gen_min_rule) DOES use
    # _countryTechSum, so unlike the nodal minimum the BioCCS headroom applies here.
    @constraint(
        emp,
        min_inv_tech_country[c in C, tc in techs(sets), sp in SP; haskey(par.genCountryMinBuiltCap, (c, tc)) && country_min_build_cap(par, c, tc, sp) > 0.0],
        sum(
            _capacity_limit_contribution(genInv[n, g, sp], g, bioccs_capacity_limit_factor)
            for n in nodes_of_country(sets, c)
            for g in generators_tech(sets, n, tc)
        ) >= country_min_build_cap(par, c, tc, sp)
    )
    @constraint(
        emp,
        max_inst_tech_country[c in C, tc in techs(sets), sp in SP; haskey(par.genCountryMaxInstalledCap, (c, tc))],
        sum(
            _capacity_limit_contribution(genCap[n, g, sp], g, bioccs_capacity_limit_factor)
            for n in nodes_of_country(sets, c)
            for g in generators_tech(sets, n, tc)
        ) <= country_max_inst_cap(par, c, tc, sp)
    )
    return nothing
end

"""
    create_bioenergy_constraints(emp, sets, par, periods; progress=nothing)

Add InternalEMPIRE's scenario-wise biomass and node-wise biomethane limits.
The source tables use GJ for biomass and TJ for biomethane.

The annual biomass usage limit (`maxBiomassNode` / `maxBiomassCountry`) is gated
exactly as in Python (`empire.py`: `if BIOMASS_LIMIT and <tab present>`): it is
built only when `biomass_limit_flag` is `true` (the neutral default, matching
Python's `biomass_limit_flag = True`) *and* the dataset provides annual biomass
data. Setting the flag to `false` builds none of `biomass_country_usage_limit`,
`biomass_node_usage_limit` or `biomass_system_usage_limit`. The legacy
InternalEMPIRE fuel-based limit (`availableBioEnergy`) and the biomethane limit
have no Python counterpart and are not affected by the flag.

Under `biomass_limit_scope` `"country"` or `"both"` the annual biomass limit is
enforced per country over `NodesOfCountry`, and, matching the Python NUTS
formulation (`empire.py`, biomass "country"/"both" scope), additionally per
individual node for every node that carries `maxBiomassNode` data but is not
mapped in `NodesOfCountry`. Without the per-node rows such nodes' Bio/BioCCS
output is left completely unconstrained under scope `"country"` (there is no
system row) and under the national half of scope `"both"`. Scope `"system"` is
unaffected.
"""
function create_bioenergy_constraints(
        emp::JuMP.Model,
        sets,
        par,
        periods::TimeStructure;
        biomass_limit_flag::Bool=true,
        biomass_limit_factor::Float64=1.2,
        biomass_system_limit_factor::Float64=1.04,
        biomass_limit_scope::String="country",
        progress = nothing,
    )
    # Check if the dataset has any biomass or biomethane limits. If not, skip the constraints.
    has_annual_biomass =
        !isempty(par.maxBiomassNode) || !isempty(par.maxBiomassCountry)

    # Python parity (empire.py): the annual biomass usage limit needs both the explicit
    # config flag and the presence of data. The legacy fuel-based limit and the biomethane
    # limit below are independent of the flag.
    build_annual_biomass = biomass_limit_flag && has_annual_biomass

    par.availableBioEnergy === nothing &&
        isempty(par.genMaxBiomethaneAvailability) &&
        !has_annual_biomass && return nothing

    biomass_limit_factor >= 0.0 ||
        throw(ArgumentError("biomass_limit_factor must be non-negative"))

    biomass_system_limit_factor >= 0.0 ||
        throw(ArgumentError("biomass_system_limit_factor must be non-negative"))

    biomass_limit_scope in ("country", "system", "both") ||
        throw(
            ArgumentError(
                "biomass_limit_scope must be \"country\", \"system\", or \"both\"",
            ),
        )

    _report_progress(progress, "Creating biomass and biomethane availability constraints")
    N = nodes(sets)
    SP = strat_periods(periods)
    genOp = emp[:genOperational]
    # Use the legacy fuel-based limit only when annual biomass data is absent.
    if !has_annual_biomass && par.availableBioEnergy !== nothing
        @constraint(
            emp,
            max_bio_availability[sp in SP, sc in 1:_opscenario_count(sp)],
            sum(
                multiple_strat(sp, t) *
                (occursin("cofiring", lowercase(g)) ? 0.1 : 1.0) *
                genOp[n, g, t] * 3.6 / par.genEfficiency[g][sp]
                for n in N
                for g in generators(sets, n) if occursin("bio", lowercase(g))
                for rp in repr_periods(sp)
                for (scenario_index, scenario) in enumerate(opscenarios(rp))
                if scenario_index == sc
                for t in scenario;
                init = 0.0
            ) <= available_bioenergy(par, sp)
        )
    end
    # Use the annual biomass limit when it is present and enabled, and apply it at the country level if requested.
    if build_annual_biomass && biomass_limit_scope in ("country", "both")
        C = countries(sets)

        @constraint(
            emp,
            biomass_country_usage_limit[c in C, sp in SP],
            sum(
                multiple_strat(sp, t) *
                probability(t) *
                genOp[n, g, t]
                for n in nodes_of_country(sets, c)
                for g in generators(sets, n)
                    if startswith(lowercase(strip(g)), "bio")
                for t in sp;
                init=0.0
            ) <= biomass_limit_factor * (
                max_biomass_country(par, c, sp) === nothing ?
                sum(
                    max_biomass_node(par, n, sp)
                    for n in nodes_of_country(sets, c);
                    init=0.0
                ) :
                max_biomass_country(par, c, sp)
            )
        )

        # Python parity (empire.py biomass "country"/"both" scope): a node that carries
        # nodal biomass data but is not mapped in NodesOfCountry forms its own single-node
        # group and is bounded individually at biomass_limit_factor * maxBiomassNode[n, sp]
        # (the national factor, not the system factor). Mapped nodes are already covered by
        # biomass_country_usage_limit above and are excluded here, so no row is duplicated.
        # This is deliberately NOT a pooled system row.
        unmapped_biomass_nodes = [
            n for n in N
            if haskey(par.maxBiomassNode, n) && country_of_node(sets, n) === nothing
        ]

        # A zero nodal reference silently forbids all Bio/BioCCS production at the node,
        # which surfaces only as an opaque infeasibility once the solve is running. Warn at
        # build time instead. Diagnostic only: the constraint below is emitted regardless,
        # exactly as in the Python formulation, so model mathematics are unchanged.
        for n in unmapped_biomass_nodes
            any(startswith(lowercase(strip(g)), "bio") for g in generators(sets, n)) || continue
            zero_periods = [sp for sp in SP if max_biomass_node(par, n, sp) <= 0.0]
            isempty(zero_periods) && continue
            @warn "Nodal biomass availability for unmapped node '$n' is zero in strategic " *
                  "period(s) $(join(string.(zero_periods), ", ")); the biomass usage limit forbids " *
                  "all Bio/BioCCS production there. Check Node/maxBiomassNode.csv (per node), or map " *
                  "the node in Sets/NodesOfCountry.csv with Node/maxBiomassCountry.csv (per country)."
        end

        @constraint(
            emp,
            biomass_node_usage_limit[n in unmapped_biomass_nodes, sp in SP],
            sum(
                multiple_strat(sp, t) *
                probability(t) *
                genOp[n, g, t]
                for g in generators(sets, n)
                    if startswith(lowercase(strip(g)), "bio")
                for t in sp;
                init=AffExpr(0.0)
            ) <= biomass_limit_factor * max_biomass_node(par, n, sp)
        )
    end
    # Use the annual biomass limit when it is present and enabled, and apply it at the system level if requested.
    if build_annual_biomass && biomass_limit_scope in ("system", "both")
        system_factor =
            biomass_limit_scope == "both" ?
            biomass_system_limit_factor :
            biomass_limit_factor

        @constraint(
            emp,
            biomass_system_usage_limit[sp in SP],
            sum(
                multiple_strat(sp, t) *
                probability(t) *
                genOp[n, g, t]
                for n in N
                for g in generators(sets, n)
                    if startswith(lowercase(strip(g)), "bio")
                for t in sp;
                init=0.0
            ) <= system_factor * (
                sum(
                    max_biomass_country(par, c, sp) === nothing ?
                    sum(
                        max_biomass_node(par, n, sp)
                        for n in nodes_of_country(sets, c);
                        init=0.0
                    ) :
                    max_biomass_country(par, c, sp)
                    for c in countries(sets);
                    init=0.0
                ) +
                sum(
                    max_biomass_node(par, n, sp)
                    for n in N
                    if country_of_node(sets, n) === nothing;
                    init=0.0
                )
            )
        )
    end
    if !isempty(par.genMaxBiomethaneAvailability)
        @constraint(
            emp,
            gen_fuel_use_limit[n in N, sp in SP, sc in 1:_opscenario_count(sp)],
            sum(
                multiple_strat(sp, t) * genOp[n, g, t] * 3.6 / par.genEfficiency[g][sp]
                for g in generators(sets, n) if occursin("biomethane", lowercase(g))
                for rp in repr_periods(sp)
                for (scenario_index, scenario) in enumerate(opscenarios(rp))
                if scenario_index == sc
                for t in scenario;
                init = 0.0
            ) <= 1e3 * max_biomethane_availability(par, n, sp)
        )
    end

    return nothing
end

"""
    create_generation_growth_constraints(emp, sets, par, periods;
        generation_growth_limit_flag=false, generation_growth_limit_rate=0.04, progress=nothing)

Node-level generation-growth cap, the mathematical equivalent of Python
`empire.py` `node_generation_growth_rule`. For every node `n`, every strategic
period `sp` that has an active predecessor `prev` (i.e. every period after the
first), and every operational scenario `sc`:

    sum over that node's generators and over `sc`'s times of
        multiple_strat(sp, t) * genOp[n, g, t]
  <=
    (1 + duration_strat(sp) * rate_sp)
      * sum over that node's generators and over ALL scenarios of the previous period of
          multiple_strat(prev, t) * probability(t) * genOp[n, g, t]

The current-period side is that one scenario only (no probability weighting); the
previous-period side is the scenario-probability-weighted expectation - exactly as
Python's `currentGen` / `previousAvgGen`. `duration_strat(sp)` is the years per
strategic period, the semantic equivalent of Python `LeapYearsInvestment`.
`rate_sp` is the per-year `GenerationGrowthRate` value for `sp` when the dataset
supplies it, otherwise `generation_growth_limit_rate` (the run-config fallback),
matching Python's `Param(model.Period, default=GEN_GROWTH_RATE)`.

No constraints are created when `generation_growth_limit_flag` is false, nor for
the first strategic period, nor when there is only one strategic period.
"""
function create_generation_growth_constraints(
        emp::JuMP.Model,
        sets,
        par,
        periods::TimeStructure;
        generation_growth_limit_flag::Bool = false,
        generation_growth_limit_rate::Float64 = 0.04,
        progress = nothing,
    )
    generation_growth_limit_flag || return nothing

    generation_growth_limit_rate >= 0.0 ||
        throw(ArgumentError(
            "generation_growth_limit_rate must be >= 0, got $(generation_growth_limit_rate)"
        ))

    SP = collect(strat_periods(periods))
    # Python skips a period whose predecessor is not an active period. The active
    # horizon is contiguous (periods 1..N), so that is exactly the first period;
    # with fewer than two periods no constraint applies at all.
    length(SP) < 2 && return nothing

    N = nodes(sets)
    genOp = emp[:genOperational]

    _report_progress(progress, "Creating node generation-growth constraints")

    # Per-year growth rate for strategic period SP[k]: the dataset value where the sheet
    # supplies it, otherwise the run-config fallback - matching Python's
    # Param(model.Period, default=GEN_GROWTH_RATE) per-period semantics:
    #   - no sheet/CSV at all            -> generationGrowthRate === nothing
    #   - sheet omits a trailing period  -> k beyond the supplied profile length
    #   - sheet omits an interior period -> NaN sentinel from the loader
    # A supplied 0.0 is a real value and still takes precedence.
    function rate_for(k)
        prof = par.generationGrowthRate
        prof === nothing && return generation_growth_limit_rate
        k > length(prof.vals) && return generation_growth_limit_rate
        r = generation_growth_rate(par, SP[k])
        (r === nothing || !isfinite(r)) ? generation_growth_limit_rate : r
    end

    @constraint(
        emp,
        node_generation_growth[
            n in N, k in 2:length(SP), sc in 1:_opscenario_count(SP[k])
        ],
        sum(
            multiple_strat(SP[k], t) * genOp[n, g, t]
            for g in generators(sets, n)
            for rp in repr_periods(SP[k])
            for (scenario_index, scenario) in enumerate(opscenarios(rp))
            if scenario_index == sc
            for t in scenario;
            init = AffExpr(0.0)
        )
        -
        (1 + duration_strat(SP[k]) * rate_for(k)) * sum(
            multiple_strat(SP[k - 1], t) * probability(t) * genOp[n, g, t]
            for g in generators(sets, n)
            for t in SP[k - 1];
            init = AffExpr(0.0)
        ) <= 0
    )
    return nothing
end

function create_storage_constraints(
    emp::JuMP.Model,
    sets,
    par,
    periods::TimeStructure;
    include_investment_constraints::Bool = true,
    progress = nothing,
)
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

    include_investment_constraints || return nothing

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

function create_transmission_constraints(
    emp::JuMP.Model,
    sets,
    par,
    periods::TimeStructure;
    offshore_transmission_cap::Bool = true,
    include_investment_constraints::Bool = true,
    progress = nothing,
)
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

    include_investment_constraints || return nothing

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

    # Offshore energy-hub converter constraints.
    #
    # Ports InternalEMPIRE's offshore_hub_capacity_in / _out (empire.py:2424-2429) and
    # installedCapDefinitionConv (:2748). A hub has no generation of its own, so what
    # bounds the power it can route is the converter capacity installed on it, in each
    # direction separately. Without these a hub is free, unlimited transmission.
    HUB = collect(offshore_energy_hubs(sets))
    if !isempty(HUB)
        @info " - offshore energy-hub converter constraints"
        _report_progress(progress, "Creating offshore energy-hub converter constraints")
        convCap = emp[:offshoreConvInstalledCap]
        convInv = emp[:offshoreConvInvCap]
        # Neighbours of each hub, so the in/out sums iterate only over real arcs.
        # Mirrors InternalEMPIRE's model.NodesLinked[n].
        hub_in = Dict(n => [m for (m, k) in arcs(sets) if k == n] for n in HUB)
        hub_out = Dict(n => [m for (k, m) in arcs(sets) if k == n] for n in HUB)

        # Power flowing into the hub, and out of it, each capped by converter capacity.
        @constraint(
            emp,
            offshore_hub_capacity_in[n in HUB, sp in SP, t in sp],
            sum(transOp[m, n, t] for m in hub_in[n]; init = 0) <= convCap[n, sp]
        )
        @constraint(
            emp,
            offshore_hub_capacity_out[n in HUB, sp in SP, t in sp],
            sum(transOp[n, m, t] for m in hub_out[n]; init = 0) <= convCap[n, sp]
        )

        # Installed converter capacity is what was built within the lifetime window,
        # the same accumulation the transmission and generator families use.
        @constraint(
            emp,
            offshore_conv_track_cap[n in HUB, sp in SP],
            sum(
                convInv[n, spp] for spp in SP
                if duration_aggr(spp, sp, SP) <= DEFAULT_OFFSHORE_CONV_LIFETIME - duration_strat(sp)
            ) == convCap[n, sp]
        )
    end

    # Deliberately after the investment-only early return, so it is omitted from
    # fixed-capacity evaluation. Both sides of the inequality are constant once
    # capacities are fixed, making the constraint redundant. Python does not merely
    # tolerate this case -- it cannot build it: under OUT_OF_SAMPLE the installed
    # capacities become Params, the expression collapses to a Boolean, and Pyomo
    # raises InvalidConstraintError. So an out-of-sample run there is incompatible
    # with north_sea entirely, and omitting the family here is the only behaviour
    # that both matches the reference in effect and actually runs.
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
        offshore_converter_investment = sum(
            objective_weight(sp, discounter) * offshore_conv_investment_expr(emp, sets, par, sp)
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
