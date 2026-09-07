# Targeted tests for CCS captured-CO2 resolution and CCS cost accounting parity with
# Python (EMPIER_Python_NUTS @ e9031e4d: empire/core/generator_costs.py + empire.py
# prepInvCost_rule / prepOperationalCostGen_rule).
#
# Confirmed Python precedence in resolve_captured_co2_factor:
#   1. explicit_captured_co2_factor  (>= 0, else ValueError)
#   2. gross_co2_factor - net_co2_factor  (>= 0, else ValueError "negative capture")
#   3. capture_rate fallback: abs(net) if net<0; 0.0 if net==0; else net/(1-rate)*rate
# Counterpart name = CCS name minus "CCS", except "GasCCS" -> "GasCCGT"; None if the
# twin is not a generator.  Capture rate is the fixed 0.9 (model.CCSRemFrac).
#
# CCS cost formulas (per Python generator_costs.py, x 3.6/efficiency where noted):
#   fixed  += CCSCostTSFix * captured * 3.6/eff                         (prepInvCost_rule)
#   marginal carbon term  = co2_price * net    (full signed net factor)
#   marginal ccs term     = captured * ccs_variable_cost                (both x 3.6/eff)

const _CCS_RTOL = 1e-9

_res(net, rate; explicit = nothing, gross = nothing) =
    OpenEMPIRE.resolve_captured_co2_factor(
        net, rate; explicit_captured_co2_factor = explicit, gross_co2_factor = gross,
    )

# --- 1: explicit value wins ----------------------------------------------------------

function test_ccs_explicit_captured_co2_takes_precedence()
    # Python test_explicit_captured_co2_factor_wins_over_the_gross_factor
    @test _res(0.013296, 0.9; explicit = 0.09, gross = 0.1108) == 0.09
    # Python test_explicit_captured_co2_factor_is_used_without_capture_rate_again
    @test _res(-0.1, 0.9; explicit = 0.1) == 0.1
end

# --- 2: gross-minus-net counterpart when explicit absent ----------------------------

function test_ccs_counterpart_gross_minus_net()
    # Python test_gross_factor_gives_exact_capture_without_assuming_the_capture_rate
    @test _res(0.013296, 0.9; gross = 0.1108) ≈ 0.097504 rtol = _CCS_RTOL
    # and NOT the capture-rate fallback value for the same net factor
    @test _res(0.013296, 0.9) ≈ 0.119664 rtol = _CCS_RTOL
end

# --- 3: 0.9 fallback only when explicit and counterpart are both unavailable --------

function test_ccs_capture_rate_fallback_only_as_last_resort()
    # Python test_legacy_fossil_ccs_factor_is_treated_as_residual_emissions
    @test _res(0.01298059776, 0.9) ≈ 0.11682537984 rtol = _CCS_RTOL
    # Python test_legacy_bioccs_factor_resolves_to_positive_captured_co2
    @test _res(-0.1, 0.9) ≈ 0.1 rtol = _CCS_RTOL
    # net == 0 -> exactly 0.0
    @test _res(0.0, 0.9) == 0.0
    # rate outside [0,1] rejected; rate == 1 with positive residual rejected
    @test_throws ArgumentError _res(0.05, 1.5)
    @test_throws ArgumentError _res(0.05, -0.1)
    @test_throws ArgumentError _res(0.05, 1.0)
    # explicit / counterpart both present -> fallback never consulted (bad rate ignored)
    @test _res(0.05, 2.0; explicit = 0.2) == 0.2
    @test _res(0.05, 2.0; gross = 0.2) ≈ 0.15 rtol = _CCS_RTOL
end

# --- 4/5: counterpart lookup for Gas and Lignite ----------------------------------

function _ccs_counterpart_fixture()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["LigniteCCS", "Lignite", "GasCCS", "GasCCGT", "BioCCS", "Bio",
                     "CoalCCS", "Coal", "Nuclear", "NoTwinCCS"],
        Technology = ["CCS", "Lignite", "Gas_CCGT", "Bio", "Coal", "Nuclear"],
        Node = ["A"],
        GeneratorsOfTechnology = [
            ("CCS", "LigniteCCS"), ("CCS", "GasCCS"), ("CCS", "BioCCS"),
            ("CCS", "CoalCCS"), ("CCS", "NoTwinCCS"),
            ("Lignite", "Lignite"), ("Gas_CCGT", "GasCCGT"), ("Bio", "Bio"),
            ("Coal", "Coal"), ("Nuclear", "Nuclear"),
        ],
        GeneratorsOfNode = [("A", g) for g in
            ("LigniteCCS", "Lignite", "GasCCS", "GasCCGT", "BioCCS", "Bio",
             "CoalCCS", "Coal", "Nuclear", "NoTwinCCS")],
    )
    par = OpenEMPIRE.EmpireParams(
        genCO2Content = Dict(
            "Lignite" => 0.1108, "GasCCGT" => 0.0558, "Bio" => 0.0, "Coal" => 0.0939,
            "Nuclear" => 0.0,
            "LigniteCCS" => 0.013296, "GasCCS" => 0.004527771428571429,
            "BioCCS" => -0.050850969, "CoalCCS" => 0.007619314285714287,
            "NoTwinCCS" => -0.1,
        ),
    )
    return sets, par
end

function test_ccs_gasccs_counterpart_resolution()
    sets, par = _ccs_counterpart_fixture()
    # GasCCS -> GasCCGT (the one non-prefix case), not "Gas"
    @test OpenEMPIRE._gross_co2_factor_of_ccs_generator(sets, par, "GasCCS") == 0.0558
    @test OpenEMPIRE.ccs_captured_co2_factor(sets, par, "GasCCS") ≈
          0.0558 - 0.004527771428571429 rtol = _CCS_RTOL
end

function test_ccs_ligniteccs_counterpart_resolution()
    sets, par = _ccs_counterpart_fixture()
    @test OpenEMPIRE._gross_co2_factor_of_ccs_generator(sets, par, "LigniteCCS") == 0.1108
    @test OpenEMPIRE.ccs_captured_co2_factor(sets, par, "LigniteCCS") ≈
          0.1108 - 0.013296 rtol = _CCS_RTOL
    # CoalCCS -> Coal
    @test OpenEMPIRE._gross_co2_factor_of_ccs_generator(sets, par, "CoalCCS") == 0.0939
    # no identifiable twin -> nothing -> capture-rate fallback path
    @test OpenEMPIRE._gross_co2_factor_of_ccs_generator(sets, par, "NoTwinCCS") === nothing
    @test OpenEMPIRE.ccs_captured_co2_factor(sets, par, "NoTwinCCS") ≈ 0.1 rtol = _CCS_RTOL  # abs(-0.1)
end

# --- 6: negative-emission / BioCCS exactly matches Python -------------------------

function test_ccs_negative_emission_and_bioccs()
    # Python test_gross_factor_captures_the_full_removal_of_a_negative_net_factor
    @test _res(-0.050851, 0.9; gross = 0.0) ≈ 0.050851 rtol = _CCS_RTOL
    sets, par = _ccs_counterpart_fixture()
    # BioCCS counterpart Bio has gross 0.0 -> captured = 0.0 - (-0.050850969)
    @test OpenEMPIRE.ccs_captured_co2_factor(sets, par, "BioCCS") ≈ 0.050850969 rtol = _CCS_RTOL
    @test OpenEMPIRE.ccs_captured_co2_factor(sets, par, "BioCCS") > 0   # never negative
end

# --- 7: invalid explicit values rejected exactly as Python -----------------------

function test_ccs_invalid_values_rejected()
    # Python test_negative_explicit_captured_co2_factor_is_rejected
    @test_throws ArgumentError _res(-0.1, 0.9; explicit = -0.1)
    # Python test_gross_factor_below_net_factor_is_rejected  ("negative capture")
    @test_throws ArgumentError _res(0.05, 0.9; gross = 0.01)

    # Loader-level guard (Python reader.py): a negative CapturedCO2Content.csv value
    # is rejected when the dataset is read.
    mktempdir() do root
        dataset = _write_toy_csv_dataset(root)
        _write_csv(joinpath(dataset, "Generator", "CapturedCO2Content.csv"),
                   "Generator,Value\ngas,-0.01\n")
        err = try
            OpenEMPIRE.read_params_csv(dataset); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("negative captured-CO2", sprint(showerror, err))
    end
end

function test_ccs_explicit_captured_co2_loaded_and_used()
    mktempdir() do root
        dataset = _write_toy_csv_dataset(root)
        _write_csv(joinpath(dataset, "Generator", "CapturedCO2Content.csv"),
                   "Generator,Value\ngas,0.15\n")
        par = OpenEMPIRE.read_params_csv(dataset)
        @test par.genCapturedCO2Factor["gas"] == 0.15
        @test OpenEMPIRE.explicit_captured_co2_factor(par, "gas") == 0.15
        # a generator with no row -> nothing (Python -1.0 sentinel)
        @test OpenEMPIRE.explicit_captured_co2_factor(par, "wind") === nothing
        # absent CSV entirely -> empty dict, all nothing
        par2 = OpenEMPIRE.read_params_csv(_write_toy_csv_dataset(mktempdir()))
        @test isempty(par2.genCapturedCO2Factor)
        @test OpenEMPIRE.explicit_captured_co2_factor(par2, "gas") === nothing
    end
end

# --- shared numeric fixture (Python test_bioccs_transport_storage_costs_are_positive) --

const _PY_EFF = 0.2742054895939017
const _PY_FUEL = 8.81123090912966
const _PY_VOM = 7.01568
const _PY_CCS_VAR = 13.62876233745015

function _ccs_numeric_fixture(; co2price = 0.0, with_capital = false)
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["NoTwinCCS", "Nuclear"],
        Technology = ["CCS", "Nuclear"],
        Node = ["A"],
        GeneratorsOfTechnology = [("CCS", "NoTwinCCS"), ("Nuclear", "Nuclear")],
        GeneratorsOfNode = [("A", "NoTwinCCS"), ("A", "Nuclear")],
    )
    par = OpenEMPIRE.EmpireParams(
        genCO2Content = Dict("NoTwinCCS" => -0.1, "Nuclear" => 0.0),
        genLifetime = Dict("NoTwinCCS" => 30.0, "Nuclear" => 30.0),
        genEfficiency = Dict("NoTwinCCS" => FixedProfile(_PY_EFF),
                             "Nuclear" => FixedProfile(_PY_EFF)),
        genFuelCost = Dict("NoTwinCCS" => FixedProfile(_PY_FUEL),
                           "Nuclear" => FixedProfile(_PY_FUEL)),
        genVariableOMCost = Dict("NoTwinCCS" => _PY_VOM, "Nuclear" => _PY_VOM),
        CCSCostTSVariable = FixedProfile(_PY_CCS_VAR),
        CO2price = FixedProfile(co2price),
        # genCapitalCost/genFixedOMCost zero so genInvCost isolates the CCS fixed term
        genCapitalCost = Dict("NoTwinCCS" => FixedProfile(with_capital ? 100.0 : 0.0),
                              "Nuclear" => FixedProfile(with_capital ? 100.0 : 0.0)),
        genFixedOMCost = Dict("NoTwinCCS" => FixedProfile(0.0), "Nuclear" => FixedProfile(0.0)),
        WACC = 0.05, discountRate = 0.05,
        # CCSCostTSFixed left nothing -> ccs_cost_fixed == DEFAULT_CCS_COST_FIXED (Python hardcode)
    )
    return sets, par
end

# --- 8: non-CCS investment and marginal costs are exactly unchanged --------------

function test_ccs_non_ccs_costs_unchanged()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))

    sets, par = _ccs_numeric_fixture(; co2price = 100.0, with_capital = true)
    OpenEMPIRE.preprocess_invest_cost(par, sets, periods)
    OpenEMPIRE.preprocess_operational_cost(par, sets, periods)

    # Nuclear (non-CCS): base annuity/present-value investment, no CCS term.
    base_inv = OpenEMPIRE.present_value(
        (100.0 / OpenEMPIRE.annuity_factor(0.05, 30.0)) * 1000, 0.05, 5.0; at_start = true,
    )
    @test par.genInvCost["Nuclear"][sp] ≈ base_inv rtol = _CCS_RTOL
    # marginal = 3.6/eff * (fuel + co2_price*co2_content) + vom, co2_content(Nuclear)=0
    @test par.genMargCost["Nuclear"][sp] ≈ (3.6 / _PY_EFF) * (_PY_FUEL + 100.0 * 0.0) + _PY_VOM rtol = _CCS_RTOL
end

# --- 9: fixed CCS cost matches Python numerically -------------------------------

function test_ccs_fixed_cost_matches_python()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))
    sets, par = _ccs_numeric_fixture()          # zero capital/OM -> genInvCost == CCS term
    OpenEMPIRE.preprocess_invest_cost(par, sets, periods)

    captured = OpenEMPIRE.ccs_captured_co2_factor(sets, par, "NoTwinCCS")   # abs(-0.1) = 0.1
    @test captured ≈ 0.1 rtol = _CCS_RTOL
    expected = OpenEMPIRE.DEFAULT_CCS_COST_FIXED * captured * 3.6 / _PY_EFF
    @test par.genInvCost["NoTwinCCS"][sp] ≈ expected rtol = _CCS_RTOL
    # cross-check against the published Python value
    @test par.genInvCost["NoTwinCCS"][sp] ≈ 1_509_650.8090 atol = 1e-3
end

# --- 10: variable CCS cost matches Python numerically -------------------------

function test_ccs_marginal_cost_matches_python()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))
    sets, par = _ccs_numeric_fixture(; co2price = 0.0)
    OpenEMPIRE.preprocess_operational_cost(par, sets, periods)

    captured = 0.1
    expected = (3.6 / _PY_EFF) * (_PY_FUEL + 0.0 * (-0.1) + captured * _PY_CCS_VAR) + _PY_VOM
    @test par.genMargCost["NoTwinCCS"][sp] ≈ expected rtol = _CCS_RTOL
    @test par.genMargCost["NoTwinCCS"][sp] ≈ 140.58990482 atol = 1e-6
end

# --- 11: residual CO2-price cost uses the complete signed net factor ---------

function test_ccs_residual_co2_price_matches_python()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))

    sets0, par0 = _ccs_numeric_fixture(; co2price = 0.0)
    sets0.Generator  # touch
    par0.genEfficiency["NoTwinCCS"] = FixedProfile(0.25)
    OpenEMPIRE.preprocess_operational_cost(par0, sets0, periods)

    sets1, par1 = _ccs_numeric_fixture(; co2price = 100.0)
    par1.genEfficiency["NoTwinCCS"] = FixedProfile(0.25)
    OpenEMPIRE.preprocess_operational_cost(par1, sets1, periods)

    delta = par1.genMargCost["NoTwinCCS"][sp] - par0.genMargCost["NoTwinCCS"][sp]
    # -0.1 t/GJ * 3.6 GJ/MWh / 0.25 * 100 EUR/t  = -144.0  (Python test)
    @test delta ≈ -144.0 rtol = _CCS_RTOL
end
