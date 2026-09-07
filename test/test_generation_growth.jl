# Targeted tests for the ported node generation-growth limit
# (Python empire.py `node_generation_growth_rule`).
#
# Confirmed Python formulation (EMPIER_Python_NUTS @ e9031e4d, empire.py:934-942):
#   Constraint(model.Node, model.PeriodActive, model.Scenario)
#   rule(n, i, w):
#     if (i-1) not in PeriodActive: Constraint.Skip
#     currentGen     = sum(seasScale[s] * genOperational[n,g,h,i,w]
#                          for g if (n,g) in GeneratorsOfNode for (s,h) in HoursOfSeason)
#     previousAvgGen = sum(sceProbab[w2] * seasScale[s] * genOperational[n,g,h,i-1,w2]
#                          for g if (n,g) in GeneratorsOfNode for (s,h) in HoursOfSeason
#                          for w2 in Scenario)
#     return currentGen - (1 + LeapYearsInvestment * generationGrowthRate[i]) * previousAvgGen <= 0
#
# Julia mapping: seasScale[s] -> multiple_strat(sp, t); fixed w -> one opscenario `sc`;
# sceProbab[w2] -> probability(t) with `for t in prev_sp`; LeapYearsInvestment ->
# duration_strat(sp); generationGrowthRate[i] -> generation_growth_rate(par, sp) with the
# run-config fallback when the sheet/CSV is absent.

function _gg_sets()
    return OpenEMPIRE.EmpireSets(
        Generator = ["G1", "G2"],
        ThermalGenerators = String[],
        Technology = ["T"],
        Node = ["A", "B"],
        GeneratorsOfTechnology = [("T", "G1"), ("T", "G2")],
        GeneratorsOfNode = [("A", "G1"), ("A", "G2"), ("B", "G1")],
    )
end

function _gg_params(; growth = nothing)
    p = OpenEMPIRE.EmpireParams(
        genCapAvailType = Dict("G1" => 1.0, "G2" => 1.0),
        genEfficiency = Dict("G1" => FixedProfile(0.5), "G2" => FixedProfile(0.5)),
        genLifetime = Dict("G1" => 30.0, "G2" => 30.0),
    )
    growth === nothing || (p.generationGrowthRate = growth)
    return p
end

# 1 season, 1 hour, 0 peaks -> multiple_strat(sp, t) == op_per_strat == 8760 for the
# single modelled hour; nscen equiprobable scenarios -> probability(t) == 1/nscen.
const _GG_MULT = 8760.0

function _gg_build(; npers = 3, years = 5, nscen = 1, flag = true, rate = 0.04, growth = nothing)
    periods = OpenEMPIRE.create_timestruct(npers, years, 1, 1, 0, 0, nscen)
    sets = _gg_sets()
    params = _gg_params(; growth)
    m = JuMP.Model()
    OpenEMPIRE.create_variables(m, sets, periods)
    OpenEMPIRE.create_generation_growth_constraints(
        m, sets, params, periods;
        generation_growth_limit_flag = flag,
        generation_growth_limit_rate = rate,
    )
    return m, sets, periods, params
end

_gg_growth(vals) = StrategicProfile([FixedProfile(v) for v in vals])

# The constraint is a SparseAxisArray (the `sc` axis length depends on the period),
# so inspect its (node, k, sc) tuple keys directly rather than via `axes`.
_gg_keys(con) = collect(keys(con.data))
_gg_period_indices(con) = sort(unique(key[2] for key in _gg_keys(con)))

# --- F2: loader maps every Excel period to the correct strategic period -----------------

function test_generation_growth_loader_maps_periods()
    mktempdir() do d
        gdir = joinpath(d, "General")
        mkpath(gdir)
        open(joinpath(gdir, "GenerationGrowthRate.csv"), "w") do io
            write(io, "Period,generationGrowthRate\n1,0.005\n2,0.04\n3,0.04\n4,0.04\n5,0.04\n6,0.04\n7,0.04\n")
        end
        prof = OpenEMPIRE._read_strategic_profile_csv(joinpath(gdir, "GenerationGrowthRate.csv"))
        periods = OpenEMPIRE.create_timestruct(7, 5, 1, 1, 0, 0, 1)
        SP = collect(strat_periods(periods))
        @test prof[SP[1]] == 0.005
        for k in 2:7
            @test prof[SP[k]] == 0.04
        end
    end
end

function test_generation_growth_loader_absent_is_nothing()
    # A dataset whose General/ has no GenerationGrowthRate.csv -> field stays `nothing`
    # so the constraint builder uses the run-config fallback for every period.
    mktempdir() do d
        mkpath(joinpath(d, "General"))
        write(joinpath(d, "General", "CO2cap.csv"), "Period,CO2cap\n1,100\n")
        path = OpenEMPIRE._optional_csv(d, "General", "GenerationGrowthRate.csv")
        @test path === nothing
    end
end

function test_generation_growth_loader_reads_northsea_csv()
    ds = joinpath(pkgdir(OpenEMPIRE), "data", "NorthSea_NECPEssentials")
    (isdir(ds) && isfile(joinpath(ds, "General", "GenerationGrowthRate.csv"))) || return
    par = OpenEMPIRE.read_params_csv(ds)
    @test par.generationGrowthRate !== nothing
    periods = OpenEMPIRE.create_timestruct(7, 5, 1, 1, 0, 0, 1)
    SP = collect(strat_periods(periods))
    @test par.generationGrowthRate[SP[1]] == 0.005
    for k in 2:7
        @test par.generationGrowthRate[SP[k]] == 0.04
    end
end

# --- F3 / F4: flag gate ----------------------------------------------------------------

function test_generation_growth_flag_false_creates_nothing()
    for npers in (1, 2, 3), nscen in (1, 2)
        m, _, _, _ = _gg_build(; npers, nscen, flag = false)
        @test !haskey(JuMP.object_dictionary(m), :node_generation_growth)
    end
end

function test_generation_growth_flag_true_creates_constraints()
    m, _, _, _ = _gg_build(; npers = 3, nscen = 1, flag = true)
    @test haskey(JuMP.object_dictionary(m), :node_generation_growth)
    @test length(m[:node_generation_growth]) > 0
end

# --- F5: first strategic period has no growth constraint ------------------------------

function test_generation_growth_first_period_skipped()
    m, _, _, _ = _gg_build(; npers = 3, nscen = 2, flag = true)
    ks = _gg_period_indices(m[:node_generation_growth])
    @test 1 ∉ ks
    @test minimum(ks) == 2

    # A single strategic period -> no predecessor anywhere -> no constraint container.
    m1, _, _, _ = _gg_build(; npers = 1, nscen = 1, flag = true)
    @test !haskey(JuMP.object_dictionary(m1), :node_generation_growth)
end

# --- F6: later-period count and indices match Python semantics -----------------------

function test_generation_growth_count_and_indices_match_python()
    # Python builds |Node| x (|PeriodActive| - 1) x |Scenario| rows (period 1 skipped).
    for (npers, nscen) in ((2, 1), (3, 1), (4, 2), (5, 3))
        m, sets, _, _ = _gg_build(; npers, nscen, flag = true)
        @test length(m[:node_generation_growth]) ==
              length(OpenEMPIRE.nodes(sets)) * (npers - 1) * nscen
        @test _gg_period_indices(m[:node_generation_growth]) == collect(2:npers)
    end
end

# --- F7: a period-specific data rate is used correctly -------------------------------

function test_generation_growth_uses_period_specific_data_rate()
    growth = _gg_growth([0.005, 0.01, 0.04])          # sp1, sp2, sp3
    m, _, periods, _ = _gg_build(; npers = 3, nscen = 1, flag = true, rate = 0.99, growth)
    SP = collect(strat_periods(periods))
    con = m[:node_generation_growth]
    genOp = m[:genOperational]

    # k = 2 -> rate = 0.01 -> multiplier 1 + 5*0.01 = 1.05
    c2 = con["A", 2, 1]
    @test JuMP.normalized_coefficient(c2, genOp["A", "G1", first(SP[2])]) ≈ _GG_MULT
    @test JuMP.normalized_coefficient(c2, genOp["A", "G1", first(SP[1])]) ≈ -(1 + 5 * 0.01) * _GG_MULT

    # k = 3 -> rate = 0.04 -> multiplier 1 + 5*0.04 = 1.20   (config rate 0.99 unused)
    c3 = con["A", 3, 1]
    @test JuMP.normalized_coefficient(c3, genOp["A", "G1", first(SP[3])]) ≈ _GG_MULT
    @test JuMP.normalized_coefficient(c3, genOp["A", "G1", first(SP[2])]) ≈ -(1 + 5 * 0.04) * _GG_MULT
end

# --- F8: config fallback rate is used when the CSV/profile is absent -----------------

function test_generation_growth_uses_config_fallback_when_absent()
    m, _, periods, _ = _gg_build(; npers = 3, nscen = 1, flag = true, rate = 0.02, growth = nothing)
    SP = collect(strat_periods(periods))
    c2 = m[:node_generation_growth]["A", 2, 1]
    @test JuMP.normalized_coefficient(c2, m[:genOperational]["A", "G1", first(SP[1])]) ≈
          -(1 + 5 * 0.02) * _GG_MULT
end

# --- F9: growth multiplier == 1 + leap_years_investment * rate (confirmed) -----------

function test_generation_growth_multiplier_scales_with_leap_years()
    # Confirmed from empire.py: (1 + model.LeapYearsInvestment * model.generationGrowthRate[i]).
    for years in (5, 10)
        m, _, periods, _ = _gg_build(; npers = 2, years, nscen = 1, flag = true, rate = 0.04)
        SP = collect(strat_periods(periods))
        c = m[:node_generation_growth]["A", 2, 1]
        prev_coef = JuMP.normalized_coefficient(c, m[:genOperational]["A", "G1", first(SP[1])])
        @test prev_coef ≈ -(1 + years * 0.04) * _GG_MULT
    end
end

# --- F10: exact JuMP coefficients / RHS for a small deterministic fixture ------------

function test_generation_growth_exact_coefficients_small_fixture()
    m, _, periods, _ = _gg_build(; npers = 2, years = 5, nscen = 1, flag = true, rate = 0.04)
    SP = collect(strat_periods(periods))
    genOp = m[:genOperational]
    mult = 1 + 5 * 0.04                       # = 1.20
    t_prev = first(SP[1]); t_cur = first(SP[2])

    cA = m[:node_generation_growth]["A", 2, 1]
    @test JuMP.normalized_coefficient(cA, genOp["A", "G1", t_cur])  ≈  _GG_MULT
    @test JuMP.normalized_coefficient(cA, genOp["A", "G2", t_cur])  ≈  _GG_MULT
    @test JuMP.normalized_coefficient(cA, genOp["A", "G1", t_prev]) ≈ -mult * _GG_MULT
    @test JuMP.normalized_coefficient(cA, genOp["A", "G2", t_prev]) ≈ -mult * _GG_MULT
    @test JuMP.normalized_coefficient(cA, genOp["B", "G1", t_cur])  == 0.0   # other node absent
    @test JuMP.normalized_rhs(cA) == 0.0

    cB = m[:node_generation_growth]["B", 2, 1]                       # node B has only G1
    @test JuMP.normalized_coefficient(cB, genOp["B", "G1", t_cur])  ≈  _GG_MULT
    @test JuMP.normalized_coefficient(cB, genOp["B", "G1", t_prev]) ≈ -mult * _GG_MULT
    @test JuMP.normalized_coefficient(cB, genOp["A", "G1", t_cur])  == 0.0
end

# --- validation: narrowest Python-compatible rule (negative rate rejected) -----------

function test_generation_growth_rejects_negative_config_rate()
    @test_throws ArgumentError _gg_build(; npers = 2, flag = true, rate = -0.01)
end

# --- partial-profile fallback: supplied period wins, omitted period uses config rate ---
# Python: generation_growth_limit_rate is the Param default for every period the sheet
# does not supply, including an interior gap when the sheet exists.

function test_generation_growth_partial_profile_per_period_fallback()
    mktempdir() do d
        gdir = joinpath(d, "General")
        mkpath(gdir)
        # supplies P1 and P3, omits P2
        open(joinpath(gdir, "GenerationGrowthRate.csv"), "w") do io
            write(io, "Period,generationGrowthRate\n1,0.005\n3,0.02\n")
        end
        # exact loader call from read_params_csv (NaN sentinel for omitted periods)
        prof = OpenEMPIRE._read_strategic_profile_csv(
            joinpath(gdir, "GenerationGrowthRate.csv"); default_value = NaN,
        )
        @test length(prof.vals) == 3
        @test prof[first(strat_periods(OpenEMPIRE.create_timestruct(3, 5, 1, 1, 0, 0, 1)))] == 0.005
        @test isnan(prof.vals[2][first(strat_periods(OpenEMPIRE.create_timestruct(3, 5, 1, 1, 0, 0, 1)))])

        periods = OpenEMPIRE.create_timestruct(3, 5, 1, 1, 0, 0, 1)
        sets = _gg_sets()
        params = _gg_params(; growth = prof)
        m = JuMP.Model()
        OpenEMPIRE.create_variables(m, sets, periods)
        OpenEMPIRE.create_generation_growth_constraints(
            m, sets, params, periods;
            generation_growth_limit_flag = true,
            generation_growth_limit_rate = 0.09,     # fallback
        )
        SP = collect(strat_periods(periods))
        genOp = m[:genOperational]

        # k = 2: P2 omitted -> fallback 0.09 -> multiplier 1 + 5*0.09 = 1.45
        c2 = m[:node_generation_growth]["A", 2, 1]
        @test JuMP.normalized_coefficient(c2, genOp["A", "G1", first(SP[1])]) ≈ -(1 + 5 * 0.09) * _GG_MULT

        # k = 3: P3 supplied = 0.02 -> multiplier 1 + 5*0.02 = 1.10 (fallback NOT used)
        c3 = m[:node_generation_growth]["A", 3, 1]
        @test JuMP.normalized_coefficient(c3, genOp["A", "G1", first(SP[2])]) ≈ -(1 + 5 * 0.02) * _GG_MULT
    end
end

# a supplied 0.0 is a real value, not a gap
function test_generation_growth_supplied_zero_is_not_fallback()
    prof = _gg_growth([0.005, 0.0])          # P2 explicitly 0.0
    m, _, periods, _ = _gg_build(; npers = 2, nscen = 1, flag = true, rate = 0.09, growth = prof)
    SP = collect(strat_periods(periods))
    c2 = m[:node_generation_growth]["A", 2, 1]
    # multiplier 1 + 5*0.0 = 1.0 (config rate 0.09 must NOT be substituted)
    @test JuMP.normalized_coefficient(c2, m[:genOperational]["A", "G1", first(SP[1])]) ≈ -1.0 * _GG_MULT
end

# trailing gap: CSV shorter than the run horizon -> later periods use the config rate
function test_generation_growth_trailing_gap_uses_fallback()
    prof = _gg_growth([0.005, 0.02])         # only P1, P2 supplied
    m, _, periods, _ = _gg_build(; npers = 3, nscen = 1, flag = true, rate = 0.09, growth = prof)
    SP = collect(strat_periods(periods))
    genOp = m[:genOperational]
    # k = 2: supplied 0.02 -> 1.10
    c2 = m[:node_generation_growth]["A", 2, 1]
    @test JuMP.normalized_coefficient(c2, genOp["A", "G1", first(SP[1])]) ≈ -(1 + 5 * 0.02) * _GG_MULT
    # k = 3: beyond supplied profile -> fallback 0.09 -> 1.45
    c3 = m[:node_generation_growth]["A", 3, 1]
    @test JuMP.normalized_coefficient(c3, genOp["A", "G1", first(SP[2])]) ≈ -(1 + 5 * 0.09) * _GG_MULT
end
