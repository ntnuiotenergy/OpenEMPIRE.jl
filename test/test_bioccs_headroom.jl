# Targeted tests for BioCCS capacity headroom (Python `bioccs_capacity_limit_factor` /
# `_capacity_limit_contribution`, empire.py @ e9031e4d).
#
# Confirmed Python: `_capacity_limit_contribution(capacity, g, factor)` returns
# `capacity / factor` iff `str(g).strip().lower() == "bioccs"`, else `capacity`.
# It is applied via `_nodeTechCapacitySum` / `_countryTechSum` in exactly:
#   investment_gen_cap           (nodal max BUILT)      -> Julia max_inv_tech
#   installed_gen_cap            (nodal max INSTALLED)  -> Julia max_inst_tech
#   investment_country_gen_cap   (country max BUILT)    -> Julia max_inv_tech_country
#   installed_country_gen_cap    (country max INSTALLED)-> Julia max_inst_tech_country
#   investment_country_gen_min   (country MIN BUILT)    -> Julia min_inv_tech_country
# It is NOT applied in `investment_gen_min_rule` (nodal MIN BUILT, plain sum)
#   -> Julia min_inv_tech must keep coefficient 1.0 for BioCCS.
# Validation: `bioccs_capacity_limit_factor <= 0` raises (config.py:257, empire.py:78).

function _bioccs_sets()
    # Country CtryA = {A1, A2}; B1 uncovered. Tech CCS = {BioCCS, CoalCCS}; Tech Gas = {GasOCGT}.
    return OpenEMPIRE.EmpireSets(
        Generator = ["BioCCS", "CoalCCS", "GasOCGT"],
        ThermalGenerators = String[],
        Technology = ["CCS", "Gas"],
        Node = ["A1", "A2", "B1"],
        Countries = ["CtryA"],
        NodesOfCountry = [("CtryA", "A1"), ("CtryA", "A2")],
        GeneratorsOfTechnology = [("CCS", "BioCCS"), ("CCS", "CoalCCS"), ("Gas", "GasOCGT")],
        GeneratorsOfNode = [
            ("A1", "BioCCS"), ("A1", "CoalCCS"), ("A1", "GasOCGT"),
            ("A2", "BioCCS"),
            ("B1", "BioCCS"), ("B1", "GasOCGT"),
        ],
    )
end

function _bioccs_params()
    p = OpenEMPIRE.EmpireParams(
        genCapAvailType = Dict("BioCCS" => 1.0, "CoalCCS" => 1.0, "GasOCGT" => 1.0),
        genLifetime = Dict("BioCCS" => 30.0, "CoalCCS" => 30.0, "GasOCGT" => 30.0),
    )
    # Activate every optional capacity constraint on tech CCS.
    p.genMinBuiltCap[("A1", "CCS")]            = StrategicProfile([10.0])   # nodal min
    p.genCountryMaxBuiltCap[("CtryA", "CCS")]  = StrategicProfile([30.0])   # country max built
    p.genCountryMinBuiltCap[("CtryA", "CCS")]  = StrategicProfile([5.0])    # country min built
    p.genCountryMaxInstalledCapRaw[("CtryA", "CCS")] = 100.0                # country max installed
    return p
end

function _bioccs_build(factor)
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sets = _bioccs_sets()
    params = _bioccs_params()
    OpenEMPIRE.preprocess_country_max_installed_cap(params, sets, periods)
    m = JuMP.Model()
    OpenEMPIRE.create_variables(m, sets, periods)
    OpenEMPIRE.create_generator_constraints(
        m, sets, params, periods; bioccs_capacity_limit_factor = factor,
    )
    return m, sets, periods
end

# every (constraint, variable, generator-name) triple the audit says should carry 1/factor
function _discounted_triples(m, sp)
    genInv = m[:genInvCap]
    genCap = m[:genInstalledCap]
    return [
        (m[:max_inv_tech]["A1", "CCS", sp],          genInv["A1", "BioCCS", sp]),
        (m[:max_inst_tech]["A1", "CCS", sp],         genCap["A1", "BioCCS", sp]),
        (m[:max_inv_tech_country]["CtryA", "CCS", sp],  genInv["A1", "BioCCS", sp]),
        (m[:max_inv_tech_country]["CtryA", "CCS", sp],  genInv["A2", "BioCCS", sp]),
        (m[:max_inst_tech_country]["CtryA", "CCS", sp], genCap["A1", "BioCCS", sp]),
        (m[:min_inv_tech_country]["CtryA", "CCS", sp],  genInv["A1", "BioCCS", sp]),
        (m[:min_inv_tech_country]["CtryA", "CCS", sp],  genInv["A2", "BioCCS", sp]),
    ]
end

# non-BioCCS generators that must always stay at coefficient 1.0
function _unchanged_triples(m, sp)
    genInv = m[:genInvCap]
    genCap = m[:genInstalledCap]
    return [
        (m[:max_inv_tech]["A1", "CCS", sp],             genInv["A1", "CoalCCS", sp]),
        (m[:max_inst_tech]["A1", "CCS", sp],            genCap["A1", "CoalCCS", sp]),
        (m[:max_inv_tech]["A1", "Gas", sp],             genInv["A1", "GasOCGT", sp]),
        (m[:max_inv_tech_country]["CtryA", "CCS", sp],  genInv["A1", "CoalCCS", sp]),
        (m[:max_inst_tech_country]["CtryA", "CCS", sp], genCap["A1", "CoalCCS", sp]),
        (m[:min_inv_tech_country]["CtryA", "CCS", sp],  genInv["A1", "CoalCCS", sp]),
        # nodal minimum: Python uses a plain sum, so BioCCS is NOT discounted here
        (m[:min_inv_tech]["A1", "CCS", sp],             genInv["A1", "BioCCS", sp]),
        (m[:min_inv_tech]["A1", "CCS", sp],             genInv["A1", "CoalCCS", sp]),
    ]
end

# --- 1: factor = 1.0 reproduces the current coefficients exactly -----------------------

function test_bioccs_factor_one_is_identity()
    m, _, periods = _bioccs_build(1.0)
    sp = first(strat_periods(periods))
    for (con, v) in _discounted_triples(m, sp)
        @test JuMP.normalized_coefficient(con, v) == 1.0
    end
    for (con, v) in _unchanged_triples(m, sp)
        @test JuMP.normalized_coefficient(con, v) == 1.0
    end
end

# --- 2: factor > 1.0 changes only the BioCCS capacity contribution --------------------

function test_bioccs_factor_gt_one_changes_only_bioccs()
    m1, _, p1 = _bioccs_build(1.0)
    m2, _, p2 = _bioccs_build(2.0)
    sp1 = first(strat_periods(p1))
    sp2 = first(strat_periods(p2))
    for ((c1, v1), (c2, v2)) in zip(_discounted_triples(m1, sp1), _discounted_triples(m2, sp2))
        @test JuMP.normalized_coefficient(c1, v1) == 1.0
        @test JuMP.normalized_coefficient(c2, v2) ≈ 0.5          # 1 / 2.0
    end
    for ((c1, v1), (c2, v2)) in zip(_unchanged_triples(m1, sp1), _unchanged_triples(m2, sp2))
        @test JuMP.normalized_coefficient(c1, v1) == JuMP.normalized_coefficient(c2, v2) == 1.0
    end
end

# --- 3: non-BioCCS generators remain unchanged for any factor ------------------------

function test_bioccs_non_bioccs_generators_unchanged()
    for f in (1.0, 1.2, 2.5)
        m, _, periods = _bioccs_build(f)
        sp = first(strat_periods(periods))
        for (con, v) in _unchanged_triples(m, sp)
            @test JuMP.normalized_coefficient(con, v) == 1.0
        end
    end
end

# --- 4/5: exactly the Python-equivalent constraints are affected --------------------

function test_bioccs_affects_only_python_equivalent_constraints()
    f = 1.25
    m, _, periods = _bioccs_build(f)
    sp = first(strat_periods(periods))
    genInv = m[:genInvCap]; genCap = m[:genInstalledCap]
    inv = 1 / f

    # affected (nodal max built/installed, country max built/installed, country MIN built)
    @test JuMP.normalized_coefficient(m[:max_inv_tech]["A1", "CCS", sp], genInv["A1", "BioCCS", sp]) ≈ inv
    @test JuMP.normalized_coefficient(m[:max_inst_tech]["A1", "CCS", sp], genCap["A1", "BioCCS", sp]) ≈ inv
    @test JuMP.normalized_coefficient(m[:max_inv_tech_country]["CtryA", "CCS", sp], genInv["A1", "BioCCS", sp]) ≈ inv
    @test JuMP.normalized_coefficient(m[:max_inst_tech_country]["CtryA", "CCS", sp], genCap["A1", "BioCCS", sp]) ≈ inv
    @test JuMP.normalized_coefficient(m[:min_inv_tech_country]["CtryA", "CCS", sp], genInv["A1", "BioCCS", sp]) ≈ inv

    # NOT affected: nodal minimum built (Python plain sum)
    @test JuMP.normalized_coefficient(m[:min_inv_tech]["A1", "CCS", sp], genInv["A1", "BioCCS", sp]) == 1.0
    @test JuMP.normalized_coefficient(m[:min_inv_tech]["A1", "CCS", sp], genInv["A1", "CoalCCS", sp]) == 1.0
end

function test_bioccs_nodal_minimum_matches_python_plain_sum()
    # Explicit restatement of item 5: nodal min unchanged, country min changed.
    m, _, periods = _bioccs_build(4.0)
    sp = first(strat_periods(periods))
    @test JuMP.normalized_coefficient(m[:min_inv_tech]["A1", "CCS", sp], m[:genInvCap]["A1", "BioCCS", sp]) == 1.0
    @test JuMP.normalized_coefficient(m[:min_inv_tech_country]["CtryA", "CCS", sp], m[:genInvCap]["A1", "BioCCS", sp]) ≈ 0.25
end

# --- 6: invalid factors fail exactly per Python validation (<= 0) --------------------

function test_bioccs_invalid_factor_rejected()
    @test_throws ArgumentError _bioccs_build(0.0)
    @test_throws ArgumentError _bioccs_build(-1.0)
    # a small positive factor is accepted (Python only rejects <= 0)
    m, _, _ = _bioccs_build(1e-6)
    @test m isa JuMP.Model
end
