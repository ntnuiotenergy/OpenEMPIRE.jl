#!/usr/bin/env julia

using CSV
using HiGHS
using JuMP
using OpenEMPIRE
using TimeStruct

function _industry_fixture_scalars(path)
    return Dict(String(row.Parameter) => Float64(row.Value) for row in CSV.File(path))
end

function _industry_metric(metric, hour, technology, value)
    return (; Metric = metric, Hour = hour, Technology = technology, Value = Float64(value))
end

function solve_industry_parity_fixture(
    fixture_dir::AbstractString,
    output_path::AbstractString;
    emission_cap::Bool = false,
)
    scalar = _industry_fixture_scalars(joinpath(fixture_dir, "parameters.csv"))
    technology_rows = collect(CSV.File(joinpath(fixture_dir, "technologies.csv")))
    steel = [String(row.Technology) for row in technology_rows if row.Sector == "Steel"]
    cement = [String(row.Technology) for row in technology_rows if row.Sector == "Cement"]
    ammonia = [String(row.Technology) for row in technology_rows if row.Sector == "Ammonia"]
    all_plants = vcat(steel, cement, ammonia)
    by_plant = Dict(String(row.Technology) => row for row in technology_rows)
    industry_sets = OpenEMPIRE.IndustrySets(
        SteelProducer = ["A"], CementProducer = ["A"],
        AmmoniaProducer = ["A"], OilProducer = ["A"],
        SteelPlant = steel, CementPlant = cement, AmmoniaPlant = ammonia,
        hydrogen = true,
    )
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        NaturalGas = OpenEMPIRE.NaturalGasSets(Node = ["A"], OnshoreNode = ["A"]),
        Hydrogen = OpenEMPIRE.HydrogenSets(ProductionNode = ["A"]),
        Industry = industry_sets,
    )
    zero_initial(plants) = Dict(("A", plant) => 0.0 for plant in plants)
    plant_period(plants, column) = Dict(
        (plant, 1) => Float64(getproperty(by_plant[plant], column)) for plant in plants
    )
    industry = OpenEMPIRE.IndustryParams(
        steelLifetime = Dict(plant => 30.0 for plant in steel),
        steelInitialCapacity = zero_initial(steel),
        steelRetirementFactor = Dict((plant, 1) => 0.0 for plant in steel),
        steelCapitalCost = Dict((plant, 1) => 0.0 for plant in steel),
        steelFixedOMCost = Dict((plant, 1) => 0.0 for plant in steel),
        steelInvestmentCost = Dict((plant, 1) => 0.0 for plant in steel),
        steelVariableOMCost = plant_period(steel, :VariableOM_EUR_per_ton),
        steelCoalConsumption = plant_period(steel, :Coal_MWh_per_ton),
        steelHydrogenConsumption = plant_period(steel, :HydrogenOrFuel_kg_per_ton),
        steelBiomassConsumption = plant_period(steel, :Biomass_MWh_per_ton),
        steelOilConsumption = plant_period(steel, :Oil_MWh_per_ton),
        steelElectricityConsumption = plant_period(steel, :Electricity_MWh_per_ton),
        steelCO2Emissions = Dict(
            plant => Float64(by_plant[plant].CO2Emitted_ton_per_ton) for plant in steel
        ),
        steelCO2Captured = Dict(
            plant => Float64(by_plant[plant].CO2Captured_ton_per_ton) for plant in steel
        ),
        steelYearlyProduction = Dict(("A", 1) => scalar["steel_demand_ton"]),
        cementLifetime = Dict(plant => 30.0 for plant in cement),
        cementInitialCapacity = zero_initial(cement),
        cementRetirementFactor = Dict((plant, 1) => 0.0 for plant in cement),
        cementCapitalCost = Dict((plant, 1) => 0.0 for plant in cement),
        cementFixedOMCost = Dict((plant, 1) => 0.0 for plant in cement),
        cementInvestmentCost = Dict((plant, 1) => 0.0 for plant in cement),
        cementFuelConsumption = plant_period(cement, :HydrogenOrFuel_kg_per_ton),
        cementCO2CaptureRate = Dict(
            plant => Float64(by_plant[plant].CaptureFraction) for plant in cement
        ),
        cementElectricityConsumption = plant_period(cement, :Electricity_MWh_per_ton),
        cementYearlyProduction = Dict("A" => scalar["cement_demand_ton"]),
        ammoniaLifetime = Dict(plant => 30.0 for plant in ammonia),
        ammoniaInitialCapacity = zero_initial(ammonia),
        ammoniaRetirementFactor = Dict((plant, 1) => 0.0 for plant in ammonia),
        ammoniaCapitalCost = Dict((plant, 1) => 0.0 for plant in ammonia),
        ammoniaFixedOMCost = Dict((plant, 1) => 0.0 for plant in ammonia),
        ammoniaInvestmentCost = Dict((plant, 1) => 0.0 for plant in ammonia),
        ammoniaFeedstockConsumption = Dict(
            plant => Float64(by_plant[plant].HydrogenOrFuel_kg_per_ton) for plant in ammonia
        ),
        ammoniaElectricityConsumption = Dict(
            plant => Float64(by_plant[plant].Electricity_MWh_per_ton) for plant in ammonia
        ),
        ammoniaYearlyProduction = Dict(("A", 1) => scalar["ammonia_demand_ton"]),
        refineryYearlyProduction = Dict(("A", 1) => scalar["oil_demand_ton"]),
        availableBioEnergy = Dict(1 => scalar["available_biomass_mwh"]),
        industryShedCost = scalar["industry_shed_cost_eur_per_ton"],
        oilShedCost = scalar["oil_shed_cost_eur_per_ton"],
        refineryHydrogenConsumption = scalar["refinery_hydrogen_ton_per_ton"],
        refineryHeatConsumption = scalar["refinery_heat_mwh_per_ton"],
        rampFractionPerHour = scalar["ramp_fraction_per_hour"],
        maximumScrapShare = scalar["maximum_scrap_share"],
        hoursPerYear = scalar["hours_per_year"],
    )
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.0,
        genFuelCost = Dict(
            "Coal" => FixedProfile(scalar["coal_cost_eur_per_mwh"]),
            "Oilexisting" => FixedProfile(scalar["oil_cost_eur_per_mwh"]),
            "Bioexisting" => FixedProfile(scalar["biomass_cost_eur_per_mwh"]),
        ),
        genCO2Content = Dict("Gasexisting" => scalar["gas_co2_content_ton_per_gj"]),
        CO2cap = emission_cap ? FixedProfile(scalar["emission_cap_ton"]) : nothing,
        CO2price = emission_cap ? nothing : FixedProfile(scalar["carbon_price_eur_per_ton"]),
        NaturalGas = OpenEMPIRE.NaturalGasParams(mwhPerTon = scalar["natural_gas_mwh_per_ton"]),
        Industry = industry,
    )
    hour_count = Int(scalar["hours"])
    periods = OpenEMPIRE.create_timestruct(
        1, 1, 1, hour_count, 0, 0, 1; operational_hours_per_year = hour_count,
    )
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_industry_variables!(model, sets, periods)
    OpenEMPIRE.create_industry_constraints!(
        model, sets, params, periods; include_investment_constraints = false,
    )
    strategic_period = only(collect(strat_periods(periods)))
    for plant in steel
        JuMP.fix(model[:steelPlantBuiltCapacity]["A", plant, strategic_period], 0.0; force = true)
        JuMP.fix(
            model[:steelPlantInstalledCapacity]["A", plant, strategic_period],
            Float64(by_plant[plant].Capacity_ton_per_h); force = true,
        )
    end
    for plant in cement
        JuMP.fix(model[:cementPlantBuiltCapacity]["A", plant, strategic_period], 0.0; force = true)
        JuMP.fix(
            model[:cementPlantInstalledCapacity]["A", plant, strategic_period],
            Float64(by_plant[plant].Capacity_ton_per_h); force = true,
        )
    end
    for plant in ammonia
        JuMP.fix(model[:ammoniaPlantBuiltCapacity]["A", plant, strategic_period], 0.0; force = true)
        JuMP.fix(
            model[:ammoniaPlantInstalledCapacity]["A", plant, strategic_period],
            Float64(by_plant[plant].Capacity_ton_per_h); force = true,
        )
    end
    @variable(model, grid[periods] >= 0)
    @variable(model, gas_import[periods] >= 0)
    @variable(model, hydrogen_import[periods] >= 0)
    @variable(model, captured_co2[periods] >= 0)
    @constraint(model, electricity_balance[t in periods],
        grid[t] == OpenEMPIRE.industry_electricity_demand(model, sets, params, "A", t))
    @constraint(model, gas_balance[t in periods],
        gas_import[t] == OpenEMPIRE.industry_natural_gas_demand(model, sets, params, "A", t))
    @constraint(model, hydrogen_balance[t in periods],
        hydrogen_import[t] == OpenEMPIRE.industry_hydrogen_demand(model, sets, params, "A", t))
    @constraint(model, co2_balance[t in periods],
        captured_co2[t] == OpenEMPIRE.industry_captured_co2(model, sets, params, "A", t))
    total_emissions = @expression(model, sum(
        OpenEMPIRE.industry_emissions(model, sets, params, "A", t) for t in periods
    ))
    emission_cap && @constraint(model, total_emissions <= scalar["emission_cap_ton"])
    discounter = OpenEMPIRE.Discounter(0.0, 1, periods)
    components = OpenEMPIRE.industry_objective_expressions(
        model, sets, params, periods, discounter,
    )
    energy_cost = @expression(model,
        sum(
            scalar["electricity_cost_eur_per_mwh"] * grid[t] +
            scalar["gas_cost_eur_per_ton"] * gas_import[t] +
            scalar["hydrogen_cost_eur_per_ton"] * hydrogen_import[t]
            for t in periods
        ))
    @objective(model, Min, sum(values(components)) + energy_cost)
    JuMP.optimize!(model)
    JuMP.termination_status(model) == JuMP.MOI.OPTIMAL || error(
        "Julia Industry fixture did not solve: $(JuMP.termination_status(model))",
    )
    rows = NamedTuple[]
    push!(rows, _industry_metric("objective_total", 0, "all", JuMP.objective_value(model)))
    for (name, expression) in pairs(components)
        push!(rows, _industry_metric("objective_$name", 0, "all", JuMP.value(expression)))
    end
    push!(rows, _industry_metric("objective_energy", 0, "all", JuMP.value(energy_cost)))
    push!(rows, _industry_metric("total_emissions", 0, "all", JuMP.value(total_emissions)))
    for (hour, operational_period) in enumerate(periods)
        for plant in all_plants
            variable = if plant in steel
                model[:steelProduced]["A", plant, operational_period]
            elseif plant in cement
                model[:cementProduced]["A", plant, operational_period]
            else
                model[:ammoniaProduced]["A", plant, operational_period]
            end
            push!(rows, _industry_metric("production", hour, plant, JuMP.value(variable)))
        end
        for (name, variable) in (
            ("steel_shed", model[:steelLoadShed]["A", operational_period]),
            ("cement_shed", model[:cementLoadShed]["A", operational_period]),
            ("ammonia_shed", model[:ammoniaLoadShed]["A", operational_period]),
            ("oil_refined", model[:oilRefined]["A", operational_period]),
            ("oil_shed", model[:oilLoadShed]["A", operational_period]),
            ("electricity", grid[operational_period]),
            ("natural_gas", gas_import[operational_period]),
            ("hydrogen", hydrogen_import[operational_period]),
            ("captured_co2", captured_co2[operational_period]),
        )
            push!(rows, _industry_metric(name, hour, "A", JuMP.value(variable)))
        end
    end
    mkpath(dirname(output_path))
    CSV.write(output_path, rows)
    println("Julia Industry parity output: $output_path")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 3) || error(
        "Usage: julia --project=. scripts/industry_parity_julia.jl FIXTURE_DIR OUTPUT.csv [--emission-cap]",
    )
    length(ARGS) == 3 && ARGS[3] != "--emission-cap" && error("unknown option $(ARGS[3])")
    solve_industry_parity_fixture(ARGS[1], ARGS[2]; emission_cap = length(ARGS) == 3)
end
