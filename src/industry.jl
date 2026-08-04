const INDUSTRY_H2_KG_TO_TON = 1.0e-3
const INDUSTRY_ROW_SCALE = 1.0e-3

_industry_steel_pairs(sets) = [
    (node, plant) for node in industry_sets(sets).SteelProducer
    for plant in industry_sets(sets).ActiveSteelPlant
]
_industry_cement_pairs(sets) = [
    (node, plant) for node in industry_sets(sets).CementProducer
    for plant in industry_sets(sets).ActiveCementPlant
]
_industry_ammonia_pairs(sets) = [
    (node, plant) for node in industry_sets(sets).AmmoniaProducer
    for plant in industry_sets(sets).ActiveAmmoniaPlant
]

function _industry_expected_plant_periods(plants, period_count)
    return Set((plant, period) for plant in plants for period in 1:period_count)
end

function _industry_missing!(issues, name, expected, values; allow_extra::Bool = false)
    missing = setdiff(expected, Set(keys(values)))
    isempty(missing) || push!(
        issues, "Industry.$name is missing $(length(missing)) required key(s)",
    )
    if !allow_extra
        extra = setdiff(Set(keys(values)), expected)
        isempty(extra) || push!(
            issues, "Industry.$name has $(length(extra)) unexpected key(s)",
        )
    end
    return nothing
end

"""Return fatal deterministic Industry input issues."""
function validate_industry(par::EmpireParams, sets::EmpireSets, periods = nothing)
    industry = industry_sets(sets)
    params = par.Industry
    issues = String[]
    has_industry(sets) || return issues
    for (name, value, positive, fraction) in (
        ("industryShedCost", params.industryShedCost, false, false),
        ("refineryHydrogenConsumption", params.refineryHydrogenConsumption, false, false),
        ("refineryHeatConsumption", params.refineryHeatConsumption, false, false),
        ("rampFractionPerHour", params.rampFractionPerHour, false, true),
        ("maximumScrapShare", params.maximumScrapShare, false, true),
        ("hoursPerYear", params.hoursPerYear, true, false),
        ("oilShedCost", params.oilShedCost, false, false),
    )
        isfinite(value) || push!(issues, "Industry.$name must be finite")
        value >= 0 || push!(issues, "Industry.$name must be non-negative")
        positive && value <= 0 && push!(issues, "Industry.$name must be positive")
        fraction && value > 1 && push!(issues, "Industry.$name must be at most 1")
    end
    for (name, values) in (
        ("steelLifetime", params.steelLifetime),
        ("steelInitialCapacity", params.steelInitialCapacity),
        ("steelRetirementFactor", params.steelRetirementFactor),
        ("steelCapitalCost", params.steelCapitalCost),
        ("steelFixedOMCost", params.steelFixedOMCost),
        ("steelVariableOMCost", params.steelVariableOMCost),
        ("steelCoalConsumption", params.steelCoalConsumption),
        ("steelHydrogenConsumption", params.steelHydrogenConsumption),
        ("steelBiomassConsumption", params.steelBiomassConsumption),
        ("steelOilConsumption", params.steelOilConsumption),
        ("steelElectricityConsumption", params.steelElectricityConsumption),
        ("steelCO2Emissions", params.steelCO2Emissions),
        ("steelCO2Captured", params.steelCO2Captured),
        ("steelYearlyProduction", params.steelYearlyProduction),
        ("cementLifetime", params.cementLifetime),
        ("cementInitialCapacity", params.cementInitialCapacity),
        ("cementRetirementFactor", params.cementRetirementFactor),
        ("cementCapitalCost", params.cementCapitalCost),
        ("cementFixedOMCost", params.cementFixedOMCost),
        ("cementFuelConsumption", params.cementFuelConsumption),
        ("cementCO2CaptureRate", params.cementCO2CaptureRate),
        ("cementElectricityConsumption", params.cementElectricityConsumption),
        ("cementYearlyProduction", params.cementYearlyProduction),
        ("ammoniaLifetime", params.ammoniaLifetime),
        ("ammoniaInitialCapacity", params.ammoniaInitialCapacity),
        ("ammoniaRetirementFactor", params.ammoniaRetirementFactor),
        ("ammoniaCapitalCost", params.ammoniaCapitalCost),
        ("ammoniaFixedOMCost", params.ammoniaFixedOMCost),
        ("ammoniaFeedstockConsumption", params.ammoniaFeedstockConsumption),
        ("ammoniaElectricityConsumption", params.ammoniaElectricityConsumption),
        ("ammoniaYearlyProduction", params.ammoniaYearlyProduction),
        ("refineryYearlyProduction", params.refineryYearlyProduction),
        ("availableBioEnergy", params.availableBioEnergy),
    )
        for (key, value) in values
            isfinite(value) || push!(issues, "Industry.$name[$key] must be finite")
            value >= 0 || push!(issues, "Industry.$name[$key] must be non-negative")
        end
    end
    for (name, values) in (
        ("steelLifetime", params.steelLifetime),
        ("cementLifetime", params.cementLifetime),
        ("ammoniaLifetime", params.ammoniaLifetime),
    )
        for (key, value) in values
            value > 0 || push!(issues, "Industry.$name[$key] must be positive")
        end
    end
    for (key, value) in params.cementCO2CaptureRate
        value <= 1 || push!(issues, "Industry.cementCO2CaptureRate[$key] must be at most 1")
    end
    for (name, values) in (
        ("steelRetirementFactor", params.steelRetirementFactor),
        ("cementRetirementFactor", params.cementRetirementFactor),
        ("ammoniaRetirementFactor", params.ammoniaRetirementFactor),
    )
        for (key, value) in values
            value <= 1 || push!(issues, "Industry.$name[$key] must be at most 1")
        end
    end
    steel_plants = Set(industry.SteelPlant)
    cement_plants = Set(industry.CementPlant)
    ammonia_plants = Set(industry.AmmoniaPlant)
    for (name, expected, values) in (
        ("steelLifetime", steel_plants, params.steelLifetime),
        ("steelCO2Emissions", steel_plants, params.steelCO2Emissions),
        ("steelCO2Captured", steel_plants, params.steelCO2Captured),
        ("cementLifetime", cement_plants, params.cementLifetime),
        ("cementCO2CaptureRate", cement_plants, params.cementCO2CaptureRate),
        ("ammoniaLifetime", ammonia_plants, params.ammoniaLifetime),
        ("ammoniaFeedstockConsumption", ammonia_plants, params.ammoniaFeedstockConsumption),
        ("ammoniaElectricityConsumption", ammonia_plants, params.ammoniaElectricityConsumption),
    )
        _industry_missing!(issues, name, expected, values)
    end
    periods === nothing && return issues
    period_count = length(strat_periods(periods))
    steel_periods = _industry_expected_plant_periods(industry.SteelPlant, period_count)
    cement_periods = _industry_expected_plant_periods(industry.CementPlant, period_count)
    ammonia_periods = _industry_expected_plant_periods(industry.AmmoniaPlant, period_count)
    for (name, expected, values) in (
        ("steelRetirementFactor", steel_periods, params.steelRetirementFactor),
        ("steelCapitalCost", steel_periods, params.steelCapitalCost),
        ("steelFixedOMCost", steel_periods, params.steelFixedOMCost),
        ("steelVariableOMCost", steel_periods, params.steelVariableOMCost),
        ("steelCoalConsumption", steel_periods, params.steelCoalConsumption),
        ("steelHydrogenConsumption", steel_periods, params.steelHydrogenConsumption),
        ("steelBiomassConsumption", steel_periods, params.steelBiomassConsumption),
        ("steelOilConsumption", steel_periods, params.steelOilConsumption),
        ("steelElectricityConsumption", steel_periods, params.steelElectricityConsumption),
        ("cementRetirementFactor", cement_periods, params.cementRetirementFactor),
        ("cementCapitalCost", cement_periods, params.cementCapitalCost),
        ("cementFixedOMCost", cement_periods, params.cementFixedOMCost),
        ("cementFuelConsumption", cement_periods, params.cementFuelConsumption),
        ("cementElectricityConsumption", cement_periods, params.cementElectricityConsumption),
        ("ammoniaRetirementFactor", ammonia_periods, params.ammoniaRetirementFactor),
        ("ammoniaCapitalCost", ammonia_periods, params.ammoniaCapitalCost),
        ("ammoniaFixedOMCost", ammonia_periods, params.ammoniaFixedOMCost),
    )
        _industry_missing!(issues, name, expected, values; allow_extra = true)
    end
    _industry_missing!(
        issues, "steelInitialCapacity",
        Set((node, plant) for node in industry.SteelProducer for plant in industry.SteelPlant),
        params.steelInitialCapacity,
    )
    _industry_missing!(
        issues, "cementInitialCapacity",
        Set((node, plant) for node in industry.CementProducer for plant in industry.CementPlant),
        params.cementInitialCapacity,
    )
    _industry_missing!(
        issues, "ammoniaInitialCapacity",
        Set((node, plant) for node in industry.AmmoniaProducer for plant in industry.AmmoniaPlant),
        params.ammoniaInitialCapacity,
    )
    _industry_missing!(
        issues, "steelYearlyProduction",
        Set((node, period) for node in industry.SteelProducer for period in 1:period_count),
        params.steelYearlyProduction;
        allow_extra = true,
    )
    _industry_missing!(
        issues, "ammoniaYearlyProduction",
        Set((node, period) for node in industry.AmmoniaProducer for period in 1:period_count),
        params.ammoniaYearlyProduction;
        allow_extra = true,
    )
    _industry_missing!(
        issues, "cementYearlyProduction", Set(industry.CementProducer),
        params.cementYearlyProduction,
    )
    _industry_missing!(
        issues, "refineryYearlyProduction",
        Set((node, period) for node in industry.OilProducer for period in 1:period_count),
        params.refineryYearlyProduction;
        allow_extra = true,
    )
    _industry_missing!(
        issues, "availableBioEnergy", Set(1:period_count), params.availableBioEnergy;
        allow_extra = true,
    )
    return issues
end

function preprocess_industry_investment_costs!(par, sets, periods)
    has_industry(sets) || return nothing
    params = par.Industry
    strategic_periods = collect(strat_periods(periods))
    wacc_value = wacc(par)
    discount = discount_rate(par)
    for (plants, capital, fixed, lifetime, output) in (
        (industry_sets(sets).ActiveSteelPlant, params.steelCapitalCost,
         params.steelFixedOMCost, params.steelLifetime, params.steelInvestmentCost),
        (industry_sets(sets).ActiveCementPlant, params.cementCapitalCost,
         params.cementFixedOMCost, params.cementLifetime, params.cementInvestmentCost),
        (industry_sets(sets).ActiveAmmoniaPlant, params.ammoniaCapitalCost,
         params.ammoniaFixedOMCost, params.ammoniaLifetime, params.ammoniaInvestmentCost),
    )
        empty!(output)
        for plant in plants, (index, strategic_period) in enumerate(strategic_periods)
            output[(plant, index)] = _internalempire_investment_cost(
                capital[(plant, index)], fixed[(plant, index)], lifetime[plant],
                strategic_period, strategic_periods, wacc_value, discount,
            )
        end
    end
    return nothing
end

"""Declare sparse strategic and operational Industry variables."""
function create_industry_variables!(emp::JuMP.Model, sets, periods)
    has_industry(sets) || throw(ArgumentError("industry=true requires non-empty Industry sets"))
    industry = industry_sets(sets)
    strategic_periods = strat_periods(periods)
    steel_pairs = _industry_steel_pairs(sets)
    cement_pairs = _industry_cement_pairs(sets)
    ammonia_pairs = _industry_ammonia_pairs(sets)
    @variable(emp, steelPlantBuiltCapacity[industry.SteelProducer, industry.ActiveSteelPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, steelPlantInstalledCapacity[industry.SteelProducer, industry.ActiveSteelPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, cementPlantBuiltCapacity[industry.CementProducer, industry.ActiveCementPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, cementPlantInstalledCapacity[industry.CementProducer, industry.ActiveCementPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, ammoniaPlantBuiltCapacity[industry.AmmoniaProducer, industry.ActiveAmmoniaPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, ammoniaPlantInstalledCapacity[industry.AmmoniaProducer, industry.ActiveAmmoniaPlant, strategic_periods] >= 0; container = IndexedVarArray)
    for (node, plant) in steel_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(steelPlantBuiltCapacity, node, plant, strategic_period)
        unsafe_insertvar!(steelPlantInstalledCapacity, node, plant, strategic_period)
    end
    for (node, plant) in cement_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(cementPlantBuiltCapacity, node, plant, strategic_period)
        unsafe_insertvar!(cementPlantInstalledCapacity, node, plant, strategic_period)
    end
    for (node, plant) in ammonia_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(ammoniaPlantBuiltCapacity, node, plant, strategic_period)
        unsafe_insertvar!(ammoniaPlantInstalledCapacity, node, plant, strategic_period)
    end
    @variable(emp, steelProduced[industry.SteelProducer, industry.ActiveSteelPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, steelLoadShed[industry.SteelProducer, periods] >= 0; container = IndexedVarArray)
    @variable(emp, cementProduced[industry.CementProducer, industry.ActiveCementPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, cementLoadShed[industry.CementProducer, periods] >= 0; container = IndexedVarArray)
    @variable(emp, ammoniaProduced[industry.AmmoniaProducer, industry.ActiveAmmoniaPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, ammoniaLoadShed[industry.AmmoniaProducer, periods] >= 0; container = IndexedVarArray)
    for (node, plant) in steel_pairs, operational_period in periods
        unsafe_insertvar!(steelProduced, node, plant, operational_period)
    end
    for node in industry.SteelProducer, operational_period in periods
        unsafe_insertvar!(steelLoadShed, node, operational_period)
    end
    for (node, plant) in cement_pairs, operational_period in periods
        unsafe_insertvar!(cementProduced, node, plant, operational_period)
    end
    for node in industry.CementProducer, operational_period in periods
        unsafe_insertvar!(cementLoadShed, node, operational_period)
    end
    for (node, plant) in ammonia_pairs, operational_period in periods
        unsafe_insertvar!(ammoniaProduced, node, plant, operational_period)
    end
    for node in industry.AmmoniaProducer, operational_period in periods
        unsafe_insertvar!(ammoniaLoadShed, node, operational_period)
    end
    if industry.RefineryActive
        @variable(emp, oilRefined[industry.OilProducer, periods] >= 0; container = IndexedVarArray)
        @variable(emp, oilLoadShed[industry.OilProducer, periods] >= 0; container = IndexedVarArray)
        for node in industry.OilProducer, operational_period in periods
            unsafe_insertvar!(oilRefined, node, operational_period)
            unsafe_insertvar!(oilLoadShed, node, operational_period)
        end
    end
    return nothing
end

function industry_electricity_demand(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :steelProduced) || return JuMP.AffExpr(0.0)
    industry = industry_sets(sets)
    params = par.Industry
    period = emp.ext[:sector_period_context][operational_period].strategic
    baseline = 0.0
    demand = JuMP.AffExpr(0.0)
    if node in industry.SteelProducer
        for plant in industry.ActiveSteelPlant
            coefficient = params.steelElectricityConsumption[(plant, period)]
            baseline += params.steelInitialCapacity[(node, plant)] * coefficient
            JuMP.add_to_expression!(demand, coefficient, emp[:steelProduced][node, plant, operational_period])
        end
    end
    if node in industry.CementProducer
        for plant in industry.ActiveCementPlant
            coefficient = params.cementElectricityConsumption[(plant, period)]
            baseline += params.cementInitialCapacity[(node, plant)] * coefficient
            JuMP.add_to_expression!(demand, coefficient, emp[:cementProduced][node, plant, operational_period])
        end
    end
    if node in industry.AmmoniaProducer
        for plant in industry.ActiveAmmoniaPlant
            coefficient = params.ammoniaElectricityConsumption[plant]
            baseline += params.ammoniaInitialCapacity[(node, plant)] * coefficient
            JuMP.add_to_expression!(demand, coefficient, emp[:ammoniaProduced][node, plant, operational_period])
        end
    end
    demand.constant -= baseline
    return demand
end

function industry_natural_gas_demand(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :cementProduced) || return JuMP.AffExpr(0.0)
    industry = industry_sets(sets)
    params = par.Industry
    period = emp.ext[:sector_period_context][operational_period].strategic
    demand = JuMP.AffExpr(0.0)
    if node in industry.CementProducer
        for plant in industry.ActiveCementPlant
            occursin("ng", lowercase(plant)) || continue
            JuMP.add_to_expression!(
                demand, INDUSTRY_H2_KG_TO_TON * params.cementFuelConsumption[(plant, period)],
                emp[:cementProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.AmmoniaProducer
        for plant in industry.ActiveAmmoniaPlant
            occursin("ng", lowercase(plant)) || continue
            JuMP.add_to_expression!(
                demand, INDUSTRY_H2_KG_TO_TON * params.ammoniaFeedstockConsumption[plant],
                emp[:ammoniaProduced][node, plant, operational_period],
            )
        end
    end
    return demand
end

function industry_hydrogen_demand(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :steelProduced) || return JuMP.AffExpr(0.0)
    industry = industry_sets(sets)
    params = par.Industry
    period = emp.ext[:sector_period_context][operational_period].strategic
    demand = JuMP.AffExpr(0.0)
    if node in industry.SteelProducer
        for plant in industry.ActiveSteelPlant
            JuMP.add_to_expression!(
                demand, INDUSTRY_H2_KG_TO_TON * params.steelHydrogenConsumption[(plant, period)],
                emp[:steelProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.CementProducer
        for plant in industry.ActiveCementPlant
            occursin("h2", lowercase(plant)) || continue
            JuMP.add_to_expression!(
                demand, INDUSTRY_H2_KG_TO_TON * params.cementFuelConsumption[(plant, period)],
                emp[:cementProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.AmmoniaProducer
        for plant in industry.ActiveAmmoniaPlant
            occursin("h2", lowercase(plant)) || continue
            JuMP.add_to_expression!(
                demand, INDUSTRY_H2_KG_TO_TON * params.ammoniaFeedstockConsumption[plant],
                emp[:ammoniaProduced][node, plant, operational_period],
            )
        end
    end
    if industry.RefineryActive && node in industry.OilProducer
        JuMP.add_to_expression!(
            demand, params.refineryHydrogenConsumption,
            emp[:oilRefined][node, operational_period],
        )
    end
    return demand
end

function _industry_cement_emission_factor(par, plant, period; captured::Bool = false)
    occursin("ng", lowercase(plant)) || return 0.0
    rate = par.Industry.cementCO2CaptureRate[plant]
    share = captured ? rate : 1 - rate
    return co2_content(par, "Gasexisting") * 3.6 * par.NaturalGas.mwhPerTon *
           INDUSTRY_H2_KG_TO_TON * par.Industry.cementFuelConsumption[(plant, period)] *
           2.5 * share
end

function _industry_ammonia_emission_factor(par, plant)
    occursin("ng", lowercase(plant)) || return 0.0
    return co2_content(par, "Gasexisting") * 3.6 * par.NaturalGas.mwhPerTon *
           INDUSTRY_H2_KG_TO_TON * par.Industry.ammoniaFeedstockConsumption[plant]
end

function industry_emissions(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :steelProduced) || return JuMP.AffExpr(0.0)
    industry = industry_sets(sets)
    params = par.Industry
    period = emp.ext[:sector_period_context][operational_period].strategic
    emissions = JuMP.AffExpr(0.0)
    if node in industry.SteelProducer
        for plant in industry.ActiveSteelPlant
            JuMP.add_to_expression!(
                emissions, params.steelCO2Emissions[plant],
                emp[:steelProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.CementProducer
        for plant in industry.ActiveCementPlant
            JuMP.add_to_expression!(
                emissions, _industry_cement_emission_factor(par, plant, period),
                emp[:cementProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.AmmoniaProducer
        for plant in industry.ActiveAmmoniaPlant
            JuMP.add_to_expression!(
                emissions, _industry_ammonia_emission_factor(par, plant),
                emp[:ammoniaProduced][node, plant, operational_period],
            )
        end
    end
    return emissions
end

function industry_captured_co2(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :steelProduced) || return JuMP.AffExpr(0.0)
    industry = industry_sets(sets)
    params = par.Industry
    period = emp.ext[:sector_period_context][operational_period].strategic
    captured = JuMP.AffExpr(0.0)
    if node in industry.SteelProducer
        for plant in industry.ActiveSteelPlant
            JuMP.add_to_expression!(
                captured, params.steelCO2Captured[plant],
                emp[:steelProduced][node, plant, operational_period],
            )
        end
    end
    if node in industry.CementProducer
        for plant in industry.ActiveCementPlant
            JuMP.add_to_expression!(
                captured, _industry_cement_emission_factor(par, plant, period; captured = true),
                emp[:cementProduced][node, plant, operational_period],
            )
        end
    end
    return captured
end

function _industry_active_investments(variable, key, strategic_period, strategic_periods, lifetime)
    return sum(
        variable[key..., candidate] for candidate in strategic_periods
        if duration_aggr(candidate, strategic_period, strategic_periods) <=
           lifetime - duration_strat(strategic_period);
        init = 0.0,
    )
end

"""Add deterministic InternalEMPIRE-compatible Industry constraints."""
function create_industry_constraints!(
    emp::JuMP.Model, sets, par, periods;
    include_investment_constraints::Bool = true,
)
    industry = industry_sets(sets)
    params = par.Industry
    strategic_periods = collect(strat_periods(periods))
    context = _sector_period_context(emp, periods, par.NaturalGas.gasScenarioCount)
    strategic_index = Dict(period => index for (index, period) in enumerate(strategic_periods))
    steel_pairs = _industry_steel_pairs(sets)
    cement_pairs = _industry_cement_pairs(sets)
    ammonia_pairs = _industry_ammonia_pairs(sets)
    # Ramps are chronological only within one representative-season scenario.
    # Building these pairs per scenario deliberately resets the ramp at every
    # season and scenario boundary, matching the reference first-hour skips.
    ramp_pairs = [
        (strategic_period, previous, operational_period)
        for strategic_period in strategic_periods
        for representative_period in repr_periods(strategic_period)
        for scenario in opscenarios(representative_period)
        for (previous, operational_period) in withprev(scenario)
        if !isnothing(previous)
    ]
    @constraint(emp, industry_steel_capacity[(node, plant) in steel_pairs, strategic_period in strategic_periods, operational_period in strategic_period],
        emp[:steelProduced][node, plant, operational_period] <= emp[:steelPlantInstalledCapacity][node, plant, strategic_period])
    @constraint(emp, industry_cement_capacity[(node, plant) in cement_pairs, strategic_period in strategic_periods, operational_period in strategic_period],
        emp[:cementProduced][node, plant, operational_period] <= emp[:cementPlantInstalledCapacity][node, plant, strategic_period])
    @constraint(emp, industry_ammonia_capacity[(node, plant) in ammonia_pairs, strategic_period in strategic_periods, operational_period in strategic_period],
        emp[:ammoniaProduced][node, plant, operational_period] <= emp[:ammoniaPlantInstalledCapacity][node, plant, strategic_period])
    @constraint(emp, industry_steel_raw_material[node in industry.SteelProducer, operational_period in periods],
        sum(emp[:steelProduced][node, plant, operational_period] for plant in industry.ActiveSteelPlant if occursin("scrap", lowercase(plant)) || occursin("dri", lowercase(plant)); init = 0.0) ==
        sum(emp[:steelProduced][node, plant, operational_period] for plant in industry.ActiveSteelPlant if occursin("eaf", lowercase(plant)); init = 0.0))
    steel_ramp = JuMP.ConstraintRef[]
    cement_ramp = JuMP.ConstraintRef[]
    ammonia_ramp = JuMP.ConstraintRef[]
    for (strategic_period, previous, operational_period) in ramp_pairs
        for (node, plant) in steel_pairs
            occursin("scrap", lowercase(plant)) && continue
            constraint = @constraint(
                emp,
                emp[:steelProduced][node, plant, operational_period] -
                emp[:steelProduced][node, plant, previous] <=
                params.rampFractionPerHour *
                emp[:steelPlantInstalledCapacity][node, plant, strategic_period],
            )
            JuMP.set_name(constraint, "industry_steel_ramp[$node,$plant,$operational_period]")
            push!(steel_ramp, constraint)
        end
        for (node, plant) in cement_pairs
            constraint = @constraint(
                emp,
                emp[:cementProduced][node, plant, operational_period] -
                emp[:cementProduced][node, plant, previous] <=
                params.rampFractionPerHour *
                emp[:cementPlantInstalledCapacity][node, plant, strategic_period],
            )
            JuMP.set_name(constraint, "industry_cement_ramp[$node,$plant,$operational_period]")
            push!(cement_ramp, constraint)
        end
        for (node, plant) in ammonia_pairs
            constraint = @constraint(
                emp,
                emp[:ammoniaProduced][node, plant, operational_period] -
                emp[:ammoniaProduced][node, plant, previous] <=
                params.rampFractionPerHour *
                emp[:ammoniaPlantInstalledCapacity][node, plant, strategic_period],
            )
            JuMP.set_name(constraint, "industry_ammonia_ramp[$node,$plant,$operational_period]")
            push!(ammonia_ramp, constraint)
        end
    end
    emp[:industry_steel_ramp] = steel_ramp
    emp[:industry_cement_ramp] = cement_ramp
    emp[:industry_ammonia_ramp] = ammonia_ramp

    steel_demand = JuMP.ConstraintRef[]
    cement_demand = JuMP.ConstraintRef[]
    ammonia_demand = JuMP.ConstraintRef[]
    refinery_demand = JuMP.ConstraintRef[]
    for (period_index, strategic_period) in enumerate(strategic_periods)
        for scenario_index in 1:_opscenario_count(strategic_period)
            for node in industry.SteelProducer
                expression = JuMP.AffExpr(0.0)
                for representative_period in repr_periods(strategic_period)
                    scenario = _operational_scenario_at(representative_period, scenario_index)
                    for operational_period in scenario
                        weight = multiple_strat(strategic_period, operational_period)
                        for plant in industry.FinalSteelPlant
                            JuMP.add_to_expression!(expression, weight, emp[:steelProduced][node, plant, operational_period])
                        end
                        JuMP.add_to_expression!(expression, weight, emp[:steelLoadShed][node, operational_period])
                    end
                end
                constraint = @constraint(emp, expression == params.steelYearlyProduction[(node, period_index)])
                JuMP.set_name(constraint, "industry_steel_demand[$node,$(strategic_period)_sc$scenario_index]")
                push!(steel_demand, constraint)
            end
            for node in industry.CementProducer
                expression = JuMP.AffExpr(0.0)
                for representative_period in repr_periods(strategic_period)
                    scenario = _operational_scenario_at(representative_period, scenario_index)
                    for operational_period in scenario
                        weight = multiple_strat(strategic_period, operational_period)
                        for plant in industry.ActiveCementPlant
                            JuMP.add_to_expression!(expression, weight, emp[:cementProduced][node, plant, operational_period])
                        end
                        JuMP.add_to_expression!(expression, weight, emp[:cementLoadShed][node, operational_period])
                    end
                end
                constraint = @constraint(emp, expression == params.cementYearlyProduction[node])
                JuMP.set_name(constraint, "industry_cement_demand[$node,$(strategic_period)_sc$scenario_index]")
                push!(cement_demand, constraint)
            end
            for node in industry.AmmoniaProducer
                expression = JuMP.AffExpr(0.0)
                for representative_period in repr_periods(strategic_period)
                    scenario = _operational_scenario_at(representative_period, scenario_index)
                    for operational_period in scenario
                        weight = multiple_strat(strategic_period, operational_period)
                        for plant in industry.ActiveAmmoniaPlant
                            JuMP.add_to_expression!(expression, weight, emp[:ammoniaProduced][node, plant, operational_period])
                        end
                        JuMP.add_to_expression!(expression, weight, emp[:ammoniaLoadShed][node, operational_period])
                    end
                end
                constraint = @constraint(emp, expression == params.ammoniaYearlyProduction[(node, period_index)])
                JuMP.set_name(constraint, "industry_ammonia_demand[$node,$(strategic_period)_sc$scenario_index]")
                push!(ammonia_demand, constraint)
            end
            if industry.RefineryActive
                for node in industry.OilProducer
                    expression = JuMP.AffExpr(0.0)
                    for representative_period in repr_periods(strategic_period)
                        scenario = _operational_scenario_at(representative_period, scenario_index)
                        for operational_period in scenario
                            weight = multiple_strat(strategic_period, operational_period)
                            JuMP.add_to_expression!(expression, weight, emp[:oilRefined][node, operational_period])
                            JuMP.add_to_expression!(expression, weight, emp[:oilLoadShed][node, operational_period])
                        end
                    end
                    constraint = @constraint(emp, expression == params.refineryYearlyProduction[(node, period_index)])
                    JuMP.set_name(constraint, "industry_refinery_demand[$node,$(strategic_period)_sc$scenario_index]")
                    push!(refinery_demand, constraint)
                end
            end
        end
    end
    emp[:industry_steel_demand] = steel_demand
    emp[:industry_cement_demand] = cement_demand
    emp[:industry_ammonia_demand] = ammonia_demand
    industry.RefineryActive && (emp[:industry_refinery_demand] = refinery_demand)

    @constraint(emp, industry_max_scrap_capacity[plant in industry.ActiveSteelPlant, strategic_period in strategic_periods; occursin("scrap", lowercase(plant))],
        sum(emp[:steelPlantInstalledCapacity][node, plant, strategic_period] for node in industry.SteelProducer; init = 0.0) <=
        params.maximumScrapShare * sum(params.steelYearlyProduction[(node, strategic_index[strategic_period])] for node in industry.SteelProducer; init = 0.0) / params.hoursPerYear)

    biomass_constraints = JuMP.ConstraintRef[]
    for (period_index, strategic_period) in enumerate(strategic_periods), scenario_index in 1:_opscenario_count(strategic_period)
        use = JuMP.AffExpr(0.0)
        for representative_period in repr_periods(strategic_period)
            scenario = _operational_scenario_at(representative_period, scenario_index)
            for operational_period in scenario
                weight = multiple_strat(strategic_period, operational_period)
                for node in natural_gas_nodes(sets), generator in generators(sets, node)
                    occursin("bio", lowercase(generator)) || continue
                    share = occursin("cofiring", lowercase(generator)) ? 0.1 : 1.0
                    JuMP.add_to_expression!(use, weight * share * 3.6 / par.genEfficiency[generator][operational_period], emp[:genOperational][node, generator, operational_period])
                end
                for node in industry.SteelProducer, plant in industry.ActiveSteelPlant
                    JuMP.add_to_expression!(use, weight * params.steelBiomassConsumption[(plant, period_index)], emp[:steelProduced][node, plant, operational_period])
                end
            end
        end
        constraint = @constraint(emp, use <= params.availableBioEnergy[period_index])
        JuMP.set_name(constraint, "industry_biomass_limit[$(strategic_period)_sc$scenario_index]")
        push!(biomass_constraints, constraint)
    end
    emp[:industry_biomass_limit] = biomass_constraints

    include_investment_constraints || return nothing
    for (pairs, plants, built_name, installed_name, initial, retirement, lifetime, base_name) in (
        (steel_pairs, industry.ActiveSteelPlant, :steelPlantBuiltCapacity, :steelPlantInstalledCapacity, params.steelInitialCapacity, params.steelRetirementFactor, params.steelLifetime, "industry_steel_installed"),
        (cement_pairs, industry.ActiveCementPlant, :cementPlantBuiltCapacity, :cementPlantInstalledCapacity, params.cementInitialCapacity, params.cementRetirementFactor, params.cementLifetime, "industry_cement_installed"),
        (ammonia_pairs, industry.ActiveAmmoniaPlant, :ammoniaPlantBuiltCapacity, :ammoniaPlantInstalledCapacity, params.ammoniaInitialCapacity, params.ammoniaRetirementFactor, params.ammoniaLifetime, "industry_ammonia_installed"),
    )
        constraints = JuMP.ConstraintRef[]
        for (node, plant) in pairs, (period_index, strategic_period) in enumerate(strategic_periods)
            push!(constraints, @constraint(
                emp,
                _industry_active_investments(emp[built_name], (node, plant), strategic_period, strategic_periods, lifetime[plant]) +
                initial[(node, plant)] * (1 - retirement[(plant, period_index)]) ==
                emp[installed_name][node, plant, strategic_period],
                base_name = "$base_name[$node,$plant,$strategic_period]",
            ))
        end
        emp[Symbol(base_name)] = constraints
    end
    return nothing
end

function industry_objective_expressions(emp, sets, par, periods, discounter)
    industry = industry_sets(sets)
    params = par.Industry
    strategic_periods = collect(strat_periods(periods))
    context = _sector_period_context(emp, periods, par.NaturalGas.gasScenarioCount)
    investment = JuMP.AffExpr(0.0)
    for (period_index, strategic_period) in enumerate(strategic_periods)
        weight = objective_weight(strategic_period, discounter)
        for node in industry.SteelProducer, plant in industry.ActiveSteelPlant
            JuMP.add_to_expression!(investment, weight * params.steelInvestmentCost[(plant, period_index)], emp[:steelPlantBuiltCapacity][node, plant, strategic_period])
        end
        for node in industry.CementProducer, plant in industry.ActiveCementPlant
            JuMP.add_to_expression!(investment, weight * params.cementInvestmentCost[(plant, period_index)], emp[:cementPlantBuiltCapacity][node, plant, strategic_period])
        end
        for node in industry.AmmoniaProducer, plant in industry.ActiveAmmoniaPlant
            JuMP.add_to_expression!(investment, weight * params.ammoniaInvestmentCost[(plant, period_index)], emp[:ammoniaPlantBuiltCapacity][node, plant, strategic_period])
        end
    end
    steel_operation = JuMP.AffExpr(0.0)
    cement_operation = JuMP.AffExpr(0.0)
    ammonia_operation = JuMP.AffExpr(0.0)
    refinery_shedding = JuMP.AffExpr(0.0)
    for operational_period in periods
        period = context[operational_period].strategic
        weight = objective_weight(operational_period, discounter; type = "avg_year")
        for node in industry.SteelProducer, plant in industry.ActiveSteelPlant
            marginal = params.steelVariableOMCost[(plant, period)] +
                       par.genFuelCost["Coal"][operational_period] * params.steelCoalConsumption[(plant, period)] +
                       par.genFuelCost["Oilexisting"][operational_period] * params.steelOilConsumption[(plant, period)] +
                       par.genFuelCost["Bioexisting"][operational_period] * params.steelBiomassConsumption[(plant, period)]
            par.CO2cap === nothing && (marginal += co2_price(par, operational_period) * params.steelCO2Emissions[plant])
            JuMP.add_to_expression!(steel_operation, weight * marginal, emp[:steelProduced][node, plant, operational_period])
        end
        for node in industry.SteelProducer
            JuMP.add_to_expression!(steel_operation, weight * params.industryShedCost, emp[:steelLoadShed][node, operational_period])
        end
        for node in industry.CementProducer, plant in industry.ActiveCementPlant
            # InternalEMPIRE prices the direct gas combustion term here. Its
            # process-emission multiplier and capture split belong only to the
            # emissions/CO2-network accounting expressions below.
            marginal = if par.CO2cap === nothing && occursin("ng", lowercase(plant))
                co2_price(par, operational_period) * co2_content(par, "Gasexisting") *
                3.6 * par.NaturalGas.mwhPerTon * INDUSTRY_H2_KG_TO_TON *
                params.cementFuelConsumption[(plant, period)]
            else
                0.0
            end
            JuMP.add_to_expression!(cement_operation, weight * marginal, emp[:cementProduced][node, plant, operational_period])
        end
        for node in industry.CementProducer
            JuMP.add_to_expression!(cement_operation, weight * params.industryShedCost, emp[:cementLoadShed][node, operational_period])
        end
        for node in industry.AmmoniaProducer, plant in industry.ActiveAmmoniaPlant
            marginal = par.CO2cap === nothing ? co2_price(par, operational_period) * _industry_ammonia_emission_factor(par, plant) : 0.0
            JuMP.add_to_expression!(ammonia_operation, weight * marginal, emp[:ammoniaProduced][node, plant, operational_period])
        end
        for node in industry.AmmoniaProducer
            JuMP.add_to_expression!(ammonia_operation, weight * params.industryShedCost, emp[:ammoniaLoadShed][node, operational_period])
        end
        if industry.RefineryActive
            # InternalEMPIRE's refinery shedding expression is the one Industry
            # operating term without `operationalDiscountrate`; the strategic
            # discount, season multiplicity, duration, and scenario probability
            # are still applied by the enclosing objective.
            strategic_period = strategic_periods[period]
            refinery_weight = objective_weight(strategic_period, discounter) *
                              multiple_strat(strategic_period, operational_period) *
                              duration(operational_period) * probability(operational_period)
            for node in industry.OilProducer
                JuMP.add_to_expression!(
                    refinery_shedding,
                    refinery_weight * params.oilShedCost,
                    emp[:oilLoadShed][node, operational_period],
                )
            end
        end
    end
    return (; investment, steel_operation, cement_operation, ammonia_operation, refinery_shedding)
end
