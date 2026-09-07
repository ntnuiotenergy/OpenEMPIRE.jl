# Regression tests for the biomass "country"/"both" per-node fallback parity fix.
#
# Python (empire.py, biomass "country"/"both" scope) bounds every node that has
# nodal biomass availability: nodes mapped in NodesOfCountry are pooled per
# country, and every unmapped node is bounded individually at
# biomass_limit_factor * maxBiomassNode[n, sp]. The Julia port previously built
# only the per-country rows, leaving unmapped nodes' Bio/BioCCS output
# unconstrained under scope "country" (and under the national half of "both").

function _biomass_fallback_sets()
    # Country "Mapped" is NUTS-disaggregated into M1, M2 (country-level biomass).
    # U1 is an aggregated node with positive nodal biomass and no country mapping.
    # U0 is an aggregated node whose nodal biomass availability is zero.
    return OpenEMPIRE.EmpireSets(
        Generator = ["Bio", "BioCCS", "Gas"],
        ThermalGenerators = ["Gas"],
        Technology = ["Bio", "CCS", "Gas_OCGT"],
        Node = ["M1", "M2", "U1", "U0"],
        Countries = ["Mapped"],
        NodesOfCountry = [("Mapped", "M1"), ("Mapped", "M2")],
        GeneratorsOfTechnology = [("Bio", "Bio"), ("CCS", "BioCCS"), ("Gas_OCGT", "Gas")],
        GeneratorsOfNode = [
            ("M1", "Bio"), ("M1", "BioCCS"),
            ("M2", "Bio"),
            ("U1", "Bio"), ("U1", "BioCCS"), ("U1", "Gas"),
            ("U0", "Bio"),
        ],
    )
end

# Two strategic periods so the period-indexed profiles are exercised.
_biomass_fallback_periods() = OpenEMPIRE.create_timestruct(2, 5, 1, 1, 0, 0, 1)

function _biomass_fallback_params(; nodal = true, country = true)
    params = OpenEMPIRE.EmpireParams(
        genCapAvailType = Dict("Bio" => 1.0, "BioCCS" => 1.0, "Gas" => 1.0),
        genEfficiency = Dict(
            "Bio" => FixedProfile(0.5),
            "BioCCS" => FixedProfile(0.5),
            "Gas" => FixedProfile(0.5),
        ),
        genLifetime = Dict("Bio" => 30.0, "BioCCS" => 30.0, "Gas" => 30.0),
    )
    if nodal
        params.maxBiomassNode = Dict(
            "U1" => StrategicProfile([100.0, 200.0]),
            "U0" => StrategicProfile([0.0, 0.0]),
        )
    end
    if country
        params.maxBiomassCountry = Dict("Mapped" => StrategicProfile([500.0, 600.0]))
    end
    return params
end

function _build_biomass_model(scope; factor = 1.2, system_factor = 1.04, flag = true, kwargs...)
    sets = _biomass_fallback_sets()
    periods = _biomass_fallback_periods()
    params = _biomass_fallback_params(; kwargs...)
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)
    OpenEMPIRE.create_bioenergy_constraints(
        model,
        sets,
        params,
        periods;
        biomass_limit_flag = flag,
        biomass_limit_factor = factor,
        biomass_system_limit_factor = system_factor,
        biomass_limit_scope = scope,
    )
    return model, sets, periods, params
end

_has_biomass_row(model, sym) = haskey(JuMP.object_dictionary(model), sym)

_annual_biomass_syms() =
    (:biomass_country_usage_limit, :biomass_node_usage_limit, :biomass_system_usage_limit)

_first_time(sp) = first(first(opscenarios(first(repr_periods(sp)))))

# ---------------------------------------------------------------------------

function test_biomass_fallback_country_scope_covers_unmapped_nodes()
    model, _, periods, _ = _build_biomass_model("country")
    SP = collect(strat_periods(periods))

    # Existing per-country rows are preserved: one country x two strategic periods.
    @test haskey(JuMP.object_dictionary(model), :biomass_country_usage_limit)
    @test length(model[:biomass_country_usage_limit]) == 2

    # New per-node fallback rows: the two unmapped biomass nodes x two periods.
    @test haskey(JuMP.object_dictionary(model), :biomass_node_usage_limit)
    node_axis = first(axes(model[:biomass_node_usage_limit]))
    @test Set(node_axis) == Set(["U1", "U0"])
    @test length(model[:biomass_node_usage_limit]) == 4

    # No pooled system row under scope "country".
    @test !haskey(JuMP.object_dictionary(model), :biomass_system_usage_limit)

    # RHS matches biomass_limit_factor * maxBiomassNode[n, sp] (Python formulation).
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U1", SP[1]]) ≈ 1.2 * 100.0
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U1", SP[2]]) ≈ 1.2 * 200.0

    # The bound acts on Bio and BioCCS output at the node, not on other generators.
    t = _first_time(SP[1])
    con = model[:biomass_node_usage_limit]["U1", SP[1]]
    @test JuMP.normalized_coefficient(con, model[:genOperational]["U1", "Bio", t]) > 0.0
    @test JuMP.normalized_coefficient(con, model[:genOperational]["U1", "BioCCS", t]) > 0.0
    @test JuMP.normalized_coefficient(con, model[:genOperational]["U1", "Gas", t]) == 0.0
end

function test_biomass_fallback_no_duplicate_rows_for_mapped_nodes()
    model, _, _, _ = _build_biomass_model("country")

    # Mapped nodes are covered by biomass_country_usage_limit only; they must not
    # also appear as single-node rows.
    node_axis = first(axes(model[:biomass_node_usage_limit]))
    @test "M1" ∉ node_axis
    @test "M2" ∉ node_axis
    @test issubset(Set(node_axis), Set(["U1", "U0"]))
end

function test_biomass_fallback_zero_availability_node_is_constrained_and_warns()
    # The zero-availability unmapped node still gets a row (production forced to 0),
    # exactly as in Python, and a build-time warning is emitted.
    sets = _biomass_fallback_sets()
    periods = _biomass_fallback_periods()
    params = _biomass_fallback_params()
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    @test_logs (:warn,) match_mode = :any OpenEMPIRE.create_bioenergy_constraints(
        model,
        sets,
        params,
        periods;
        biomass_limit_factor = 1.2,
        biomass_limit_scope = "country",
    )

    SP = collect(strat_periods(periods))
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U0", SP[1]]) == 0.0
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U0", SP[2]]) == 0.0
    t = _first_time(SP[1])
    con = model[:biomass_node_usage_limit]["U0", SP[1]]
    @test JuMP.normalized_coefficient(con, model[:genOperational]["U0", "Bio", t]) > 0.0
end

function test_biomass_fallback_system_scope_unchanged()
    model, _, periods, _ = _build_biomass_model("system")

    # Scope "system" keeps a single pooled row per period and builds neither the
    # per-country nor the per-node rows.
    @test haskey(JuMP.object_dictionary(model), :biomass_system_usage_limit)
    @test length(model[:biomass_system_usage_limit]) == 2
    @test !haskey(JuMP.object_dictionary(model), :biomass_country_usage_limit)
    @test !haskey(JuMP.object_dictionary(model), :biomass_node_usage_limit)

    SP = collect(strat_periods(periods))
    # Pooled reference = country figure (500) + unmapped nodal (100 + 0); factor 1.2.
    @test JuMP.normalized_rhs(model[:biomass_system_usage_limit][SP[1]]) ≈ 1.2 * 600.0
end

function test_biomass_fallback_both_scope_builds_all_three_row_families()
    model, _, periods, _ = _build_biomass_model("both"; factor = 1.2, system_factor = 1.04)
    SP = collect(strat_periods(periods))

    @test length(model[:biomass_country_usage_limit]) == 2
    @test length(model[:biomass_node_usage_limit]) == 4
    @test length(model[:biomass_system_usage_limit]) == 2

    # Per-node rows use the national factor (1.2), never the system factor.
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U1", SP[1]]) ≈ 1.2 * 100.0
    @test JuMP.normalized_rhs(model[:biomass_node_usage_limit]["U1", SP[2]]) ≈ 1.2 * 200.0

    # System row keeps the tighter system factor (1.04) over the pooled reference.
    @test JuMP.normalized_rhs(model[:biomass_system_usage_limit][SP[1]]) ≈ 1.04 * 600.0
    @test JuMP.normalized_rhs(model[:biomass_system_usage_limit][SP[2]]) ≈ 1.04 * (600.0 + 200.0)
end

function test_biomass_fallback_absent_when_no_unmapped_nodal_data()
    # Only country-level biomass data: there are no unmapped biomass nodes, so the
    # per-node container is built but empty, and the per-country rows are intact.
    model, _, _, _ = _build_biomass_model("country"; nodal = false, country = true)

    @test length(model[:biomass_country_usage_limit]) == 2
    @test haskey(JuMP.object_dictionary(model), :biomass_node_usage_limit)
    @test isempty(model[:biomass_node_usage_limit])
end

# --- biomass_limit_flag gate (Python parity: `if BIOMASS_LIMIT and <tab present>`) ------

function test_biomass_limit_flag_true_builds_annual_constraints()
    # Flag true (Python's neutral default) + biomass data present + scope "both":
    # every applicable annual-biomass row family is built.
    model, _, _, _ = _build_biomass_model("both"; flag = true)

    @test _has_biomass_row(model, :biomass_country_usage_limit)
    @test _has_biomass_row(model, :biomass_node_usage_limit)
    @test _has_biomass_row(model, :biomass_system_usage_limit)
    @test length(model[:biomass_country_usage_limit]) == 2
    @test length(model[:biomass_node_usage_limit]) == 4
    @test length(model[:biomass_system_usage_limit]) == 2
end

function test_biomass_limit_flag_false_suppresses_annual_constraints()
    # Flag false + biomass data present: none of the three annual-biomass row
    # families are built, for every scope (matches empire.py, where biomass_limit_active
    # stays false and the whole `if biomass_limit_active:` block is skipped).
    for scope in ("country", "system", "both")
        model, _, _, _ = _build_biomass_model(scope; flag = false)
        for sym in _annual_biomass_syms()
            @test !_has_biomass_row(model, sym)
        end
    end
end

function test_biomass_limit_flag_ignored_when_no_annual_data()
    # No maxBiomassNode / maxBiomassCountry data: no annual biomass constraints are
    # built regardless of the flag value.
    for flag in (true, false)
        model, _, _, _ = _build_biomass_model("both"; flag = flag, nodal = false, country = false)
        for sym in _annual_biomass_syms()
            @test !_has_biomass_row(model, sym)
        end
    end
end
