# CCS transport-and-storage cost provenance / mode selection.
#
#   python-nuts    : fixed = DEFAULT_CCS_COST_FIXED (1149873.72, the hard-coded
#                    Python constant), variable = genuine Excel/CSV values.
#   internalempire : fixed = 0.0 (CCSCostTSFixed.csv), variable = 0.0.
#
# The mode is selected at conversion time (`--ccs-cost-mode`); the Julia model
# reads whatever the dataset provides and falls back to DEFAULT_CCS_COST_FIXED
# for the fixed coefficient only when no CCSCostTSFixed.csv is present. A
# user-supplied CCSCostTSFixed value (CSV or field) is never silently overridden.
#
# Depends on _ccs_numeric_fixture / _PY_* from test_ccs_captured_co2.jl and
# _write_toy_csv_dataset / _write_csv from test_csv.jl.

const _NS_CCS_DS = joinpath(pkgdir(OpenEMPIRE), "data", "NorthSea_NECPEssentials")

# Exact Excel Generator.xlsx!CCSCostTSVariable values (full float64 precision), P1..P7.
const _NS_CCS_VAR = (
    14.07970349782249, 14.07970349782249, 14.0342893278903, 12.82179299472824,
    13.31699692878983, 13.62876233745015, 13.62876233745015,
)

# --- 1: fixed-cost provenance and mode selection ------------------------------------

function test_ccs_fixed_cost_provenance_and_modes()
    @test OpenEMPIRE.DEFAULT_CCS_COST_FIXED == 1149873.72

    # python-nuts: no CCSCostTSFixed -> the hard-coded constant
    p = OpenEMPIRE.EmpireParams()
    @test p.CCSCostTSFixed === nothing
    @test OpenEMPIRE.ccs_cost_fixed(p) == OpenEMPIRE.DEFAULT_CCS_COST_FIXED

    # internalempire: an explicit 0.0 is honoured
    p.CCSCostTSFixed = 0.0
    @test OpenEMPIRE.ccs_cost_fixed(p) == 0.0

    # the shipped North Sea dataset is python-nuts (no CCSCostTSFixed.csv)
    if isdir(_NS_CCS_DS)
        @test !isfile(joinpath(_NS_CCS_DS, "Generator", "CCSCostTSFixed.csv"))
        par = OpenEMPIRE.read_params_csv(_NS_CCS_DS)
        @test par.CCSCostTSFixed === nothing
        @test OpenEMPIRE.ccs_cost_fixed(par) == OpenEMPIRE.DEFAULT_CCS_COST_FIXED
    end
end

# --- 2: all seven variable-cost periods, Excel -> CSV -> loaded Julia parameter -----

function test_ccs_variable_cost_seven_periods_excel_to_param()
    isdir(_NS_CCS_DS) || return
    csv = joinpath(_NS_CCS_DS, "Generator", "CCSCostTSVariable.csv")
    @test isfile(csv)
    rows = readlines(csv)
    @test length(rows) == 8                     # header + 7 data rows
    for (k, line) in enumerate(rows[2:end])
        period_str, value_str = split(line, ',')
        @test parse(Int, period_str) == k
        @test parse(Float64, value_str) == _NS_CCS_VAR[k]
    end

    par = OpenEMPIRE.read_params_csv(_NS_CCS_DS)
    periods = OpenEMPIRE.create_timestruct(7, 5, 1, 1, 0, 0, 1)
    SP = collect(strat_periods(periods))
    for k in 1:7
        @test OpenEMPIRE.ccs_cost_variable(par, SP[k]) == _NS_CCS_VAR[k]
    end
    # none is zero (would have been the internalempire behaviour)
    @test all(OpenEMPIRE.ccs_cost_variable(par, SP[k]) > 0 for k in 1:7)
end

# --- 3: realized Julia CCS objective coefficients match Python (python-nuts) -------

function test_ccs_realized_coefficients_match_python_in_python_nuts_mode()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))

    # _PY_CCS_VAR (13.62876233745015) is exactly the North Sea P6/P7 CCSCostTSVariable.
    sets, par = _ccs_numeric_fixture(; co2price = 0.0)
    @test par.CCSCostTSFixed === nothing                     # python-nuts: constant, not a CSV value
    OpenEMPIRE.preprocess_invest_cost(par, sets, periods)
    OpenEMPIRE.preprocess_operational_cost(par, sets, periods)

    captured = OpenEMPIRE.ccs_captured_co2_factor(sets, par, "NoTwinCCS")   # abs(-0.1) = 0.1
    # fixed: DEFAULT_CCS_COST_FIXED * captured * 3.6/eff  (zero capital in the fixture)
    @test OpenEMPIRE.ccs_cost_fixed(par) == OpenEMPIRE.DEFAULT_CCS_COST_FIXED
    @test par.genInvCost["NoTwinCCS"][sp] ≈
          OpenEMPIRE.DEFAULT_CCS_COST_FIXED * captured * 3.6 / _PY_EFF rtol = 1e-9
    @test par.genInvCost["NoTwinCCS"][sp] ≈ 1_509_650.8090 atol = 1e-3   # Python published value

    # marginal: 3.6/eff*(fuel + co2_price*net + captured*ccs_variable) + vom
    @test par.genMargCost["NoTwinCCS"][sp] ≈
          (3.6 / _PY_EFF) * (_PY_FUEL + 0.0 * (-0.1) + captured * _PY_CCS_VAR) + _PY_VOM rtol = 1e-9
    @test par.genMargCost["NoTwinCCS"][sp] ≈ 140.58990482 atol = 1e-6    # Python published value
end

# --- 4: non-CCS technologies unaffected by the mode -------------------------------

function test_ccs_cost_mode_leaves_non_ccs_unchanged()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))

    function nuclear_costs(fixed_override)
        sets, par = _ccs_numeric_fixture(; co2price = 100.0, with_capital = true)
        par.CCSCostTSFixed = fixed_override          # nothing = python-nuts, 0.0 = internalempire
        OpenEMPIRE.preprocess_invest_cost(par, sets, periods)
        OpenEMPIRE.preprocess_operational_cost(par, sets, periods)
        return par.genInvCost["Nuclear"][sp], par.genMargCost["Nuclear"][sp]
    end

    inv_pn, marg_pn = nuclear_costs(nothing)
    inv_ie, marg_ie = nuclear_costs(0.0)
    @test inv_pn == inv_ie                           # non-CCS investment identical across modes
    @test marg_pn == marg_ie                         # non-CCS marginal identical across modes
    # and it equals the plain non-CCS formula (no CCS terms)
    base_inv = OpenEMPIRE.present_value(
        (100.0 / OpenEMPIRE.annuity_factor(0.05, 30.0)) * 1000, 0.05, 5.0; at_start = true)
    @test inv_pn ≈ base_inv rtol = 1e-9
    @test marg_pn ≈ (3.6 / _PY_EFF) * (_PY_FUEL + 100.0 * 0.0) + _PY_VOM rtol = 1e-9
end

# --- 5: an explicitly supplied user value is not silently overwritten ------------

function test_ccs_fixed_cost_explicit_user_value_not_overwritten()
    p = OpenEMPIRE.EmpireParams()
    p.CCSCostTSFixed = 987654.0
    @test OpenEMPIRE.ccs_cost_fixed(p) == 987654.0          # neither DEFAULT nor 0.0

    # via the loader: a user-supplied CCSCostTSFixed.csv is loaded verbatim
    mktempdir() do root
        dataset = _write_toy_csv_dataset(root)
        _write_csv(joinpath(dataset, "Generator", "CCSCostTSFixed.csv"), "CCSCostTSFixed\n555.5\n")
        par = OpenEMPIRE.read_params_csv(dataset)
        @test par.CCSCostTSFixed == 555.5
        @test OpenEMPIRE.ccs_cost_fixed(par) == 555.5
    end
    # and when absent, the loader leaves it nothing -> DEFAULT_CCS_COST_FIXED
    mktempdir() do root
        par = OpenEMPIRE.read_params_csv(_write_toy_csv_dataset(root))
        @test par.CCSCostTSFixed === nothing
        @test OpenEMPIRE.ccs_cost_fixed(par) == OpenEMPIRE.DEFAULT_CCS_COST_FIXED
    end
end
