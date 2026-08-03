function _write_natural_gas_csv_fixture(dataset; gas_scenarios::Int = 1)
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasNodes.csv"),
        "NaturalGasNodes\nA\nB\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasDirectionalLines.csv"),
        "NodeFrom,NodeTo\nA,B\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasTerminals.csv"),
        "NaturalGasTerminals\nDomesticProduction\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasTerminalsOfNode.csv"),
        "Node,NG_Terminal_Type\nA,DomesticProduction\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "OnshoreNode.csv"),
        "OnshoreNode\nA\nB\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "PipelineCapacity.csv"),
        "FromNode,ToNode,Capacity_(ton/h)\nA,B,100\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "PipelineElectricityUse.csv"),
        "Power_usage_[MWh/ton]\n0.024\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "StorageCapacity.csv"),
        "Node,Storage_(ton)\nA,10\nB,0\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "Reserves.csv"),
        "Node,Reserves_(tons)\nA,1000000\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCapacity.csv"),
        "Node,Terminal,Period,Capacity_(ton/hr)\nA,DomesticProduction,1,100\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCost.csv"),
        "Node,Terminal,Period,Scenario,Cost_(EUR/ton)\n" *
        "A,DomesticProduction,1,1,100\n",
    )
    stochastic_rows = join(
        (
            "A,DomesticProduction,1,$scenario,$(100 * scenario)"
            for scenario in 1:gas_scenarios
        ),
        "\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCost_stochastic.csv"),
        "Node,Terminal,Period,GasScenario,Cost_(EUR/ton)\n" *
        stochastic_rows *
        "\n",
    )
    _write_csv(
        joinpath(dataset, "Transport", "NaturalGasDemand.csv"),
        "Node,Period,Natural_gas_demand_[MWh/yr]\nA,1,0\nB,1,0\n",
    )
    _write_csv(
        joinpath(dataset, "Transport", "CurtailCost.csv"),
        "CurtailCost_(€/MWh)\n100000\n",
    )
    return dataset
end

function _natural_gas_solved_fixture(
    ;
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
    pipeline_power::Float64 = 0.024,
    pipeline_capacity::Float64 = 100.0,
    terminal_capacity::Float64 = 100.0,
    storage_capacity_b::Float64 = 0.0,
    transport_demand_b_ton_per_hour::Float64 = 0.0,
    transport_curtail_cost::Float64 = 100000.0,
    load_b::Vector{Float64} = [10.0],
    generator_marginal_cost::Float64 = 0.0,
    generator_capacity::Float64 = 100.0,
    fix_load_shed::Bool = false,
    natural_gas_gate::Bool = true,
    co2_content::Float64 = 0.0,
    co2_cap::Union{Nothing, Float64} = nothing,
)
    combined_scenarios = weather_scenarios * gas_scenarios
    hour_count = length(load_b)
    hour_count > 0 || throw(ArgumentError("load_b must contain at least one hour"))
    periods = OpenEMPIRE.create_timestruct(
        1,
        5,
        1,
        hour_count,
        0,
        0,
        combined_scenarios;
        operational_hours_per_year = hour_count,
    )
    gas_sets = OpenEMPIRE.NaturalGasSets(
        Node = ["A", "B"],
        DirectionalLink = [("A", "B")],
        Terminal = ["DomesticProduction"],
        TerminalsOfNode = [("A", "DomesticProduction")],
        OnshoreNode = ["A", "B"],
        Generator = ["GasCCGT"],
    )
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A", "B"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT"), ("B", "GasCCGT")],
        NaturalGas = gas_sets,
    )
    terminal_cost = Dict(
        ("A", "DomesticProduction", 1, scenario) => 100.0 * scenario
        for scenario in 1:gas_scenarios
    )
    gas = OpenEMPIRE.NaturalGasParams(
        pipelineCapacity = Dict(("A", "B") => pipeline_capacity),
        pipelinePowerDemandPerTon = pipeline_power,
        terminalCost = terminal_cost,
        terminalCapacity = Dict(
            ("A", "DomesticProduction", 1) => terminal_capacity,
        ),
        storageCapacity = Dict("A" => 0.0, "B" => storage_capacity_b),
        reserves = Dict("A" => 1.0e9),
        transportDemand = Dict(
            ("A", 1) => 0.0,
            ("B", 1) =>
                transport_demand_b_ton_per_hour * 8760 * 13.9,
        ),
        transportCurtailCost = transport_curtail_cost,
        weatherScenarioCount = weather_scenarios,
        gasScenarioCount = gas_scenarios,
    )
    scenario_profiles(values) = StrategicProfile([
        RepresentativeProfile([
            ScenarioProfile([
                OperationalProfile(copy(values))
                for _ in 1:combined_scenarios
            ]),
        ]),
    ])
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genCapAvail = Dict(
            ("A", "GasCCGT") => FixedProfile(1.0),
            ("B", "GasCCGT") => FixedProfile(1.0),
        ),
        # Maximum installed capacity defaults to zero, so the investment
        # constraints would cap genInstalledCap at 0 and make the fixed capacity
        # below infeasible. Give the fixture headroom instead of switching the
        # investment constraints off: the test still pins installed capacity and
        # asserts the same gas quantities, but it no longer depends on a
        # constraint-gating flag that lives in the unmerged out-of-sample stack.
        # Keyed by (node, TECHNOLOGY) - the max_inst_tech constraint is technology
        # level, not generator level.
        genMaxInstalledCap = Dict(
            ("A", "Gas") => FixedProfile(1.0e6),
            ("B", "Gas") => FixedProfile(1.0e6),
        ),
        genCO2Content = Dict("GasCCGT" => co2_content),
        genMargCost = Dict(
            "GasCCGT" => FixedProfile(generator_marginal_cost),
        ),
        CO2cap = isnothing(co2_cap) ? nothing : FixedProfile(co2_cap),
        sload = Dict(
            "A" => scenario_profiles(zeros(hour_count)),
            "B" => scenario_profiles(load_b),
        ),
        nodeLostLoadCost = Dict(
            "A" => FixedProfile(1.0e6),
            "B" => FixedProfile(1.0e6),
        ),
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        NaturalGas = gas,
    )

    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(
        model,
        sets,
        periods;
        natural_gas = natural_gas_gate,
    )
    OpenEMPIRE.create_constraints(
        model,
        sets,
        params,
        periods;
        natural_gas = natural_gas_gate,
    )
    strategic_period = only(collect(strat_periods(periods)))
    for node in ("A", "B")
        JuMP.fix(
            model[:genInstalledCap][node, "GasCCGT", strategic_period],
            generator_capacity;
            force = true,
        )
    end
    if fix_load_shed
        for node in ("A", "B"), operational_period in periods
            JuMP.fix(
                model[:loadShed][node, operational_period],
                0.0;
                force = true,
            )
        end
    end
    discounter = Discounter(0.05, 1, periods)
    OpenEMPIRE.create_objective(
        model,
        sets,
        params,
        periods,
        discounter;
        natural_gas = natural_gas_gate,
    )
    JuMP.optimize!(model)
    return model, periods, sets, params, discounter
end

function test_natural_gas_csv_loading_and_validation()
    mktempdir() do root
        dataset = _write_natural_gas_csv_fixture(
            _write_toy_csv_dataset(root);
            gas_scenarios = 2,
        )
        module_off_sets, _ = OpenEMPIRE.read_data(dataset; format = :csv)
        @test !OpenEMPIRE.has_natural_gas(module_off_sets)

        sets, params = OpenEMPIRE.read_data(
            dataset;
            format = :csv,
            natural_gas = true,
            weather_scenarios = 3,
            gas_scenarios = 2,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 6)
        @test OpenEMPIRE.has_natural_gas(sets)
        @test OpenEMPIRE.natural_gas_nodes(sets) == ["A", "B"]
        @test OpenEMPIRE.natural_gas_generators(sets) == Set(["gas"])
        @test params.NaturalGas.weatherScenarioCount == 3
        @test params.NaturalGas.gasScenarioCount == 2
        @test params.NaturalGas.terminalCost[
            ("A", "DomesticProduction", 1, 2)
        ] == 200.0
        validation_errors =
            OpenEMPIRE.validate(params; sets, periods, strict = false)
        @test any(
            occursin("gasScenarioCount must equal 1", error)
            for error in validation_errors
        )
        empty!(params.NaturalGas.reserves)
        reserve_error = try
            OpenEMPIRE.validate(params; sets, periods)
            nothing
        catch error
            error
        end
        @test reserve_error isa ArgumentError
        @test occursin(
            "NaturalGas.reserves is missing 1 required key",
            sprint(showerror, reserve_error),
        )

        malformed_cases = (
            (
                "Node,Reserves_(tons)\nA,1\nA,2\n",
                "Duplicate natural-gas key A",
            ),
            (
                "Node,Reserves_(tons)\nA,NaN\n",
                "value must be finite",
            ),
            (
                "Node,Reserves_(tons)\nA,-1\n",
                "value must be non-negative",
            ),
            (
                "Node,Reserves_(tons)\nA,alphabetic\n",
                "expected a number",
            ),
            (
                "Node,Reserves_(tons)\nA,\n",
                "empty value",
            ),
        )
        reserve_path = joinpath(dataset, "NaturalGas", "Reserves.csv")
        for (content, expected) in malformed_cases
            _write_csv(reserve_path, content)
            error = try
                OpenEMPIRE.read_data(
                    dataset;
                    format = :csv,
                    natural_gas = true,
                    weather_scenarios = 3,
                    gas_scenarios = 2,
                )
                nothing
            catch err
                err
            end
            @test error isa ArgumentError
            @test occursin(expected, sprint(showerror, error))
            @test occursin(reserve_path, sprint(showerror, error))
        end
    end
end

function test_natural_gas_scenario_mapping_and_costs()
    @test OpenEMPIRE.gas_scenario_count(
        Dict(
            "natural_gas" => false,
            "number_of_scenarios" => 3,
            "number_of_gas_scenarios" => 9,
        ),
    ) == 1
    for (weather_count, gas_count) in ((1, 1), (2, 2), (3, 3))
        config = Dict(
            "natural_gas" => true,
            "number_of_scenarios" => weather_count,
            "number_of_gas_scenarios" => gas_count,
        )
        @test OpenEMPIRE.combined_scenario_count(config) ==
              weather_count * gas_count
        @test [
            (
                OpenEMPIRE.weather_scenario_index(index, gas_count),
                OpenEMPIRE.gas_scenario_index(index, gas_count),
            ) for index in 1:(weather_count * gas_count)
        ] == [
            (weather, gas)
            for weather in 1:weather_count for gas in 1:gas_count
        ]
    end

    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT")],
        NaturalGas = OpenEMPIRE.NaturalGasSets(
            Node = ["A"],
            Generator = ["GasCCGT"],
        ),
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    parameters = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("GasCCGT" => FixedProfile(8.0)),
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genVariableOMCost = Dict("GasCCGT" => 5.0),
        genCO2Content = Dict("GasCCGT" => 0.2),
        CO2price = FixedProfile(10.0),
    )
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = false,
    )
    @test parameters.genMargCost["GasCCGT"][first(periods)] ≈ 77.0
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = true,
    )
    @test parameters.genMargCost["GasCCGT"][first(periods)] ≈ 19.4
end

# InternalEMPIRE prices natural gas through the gas module, so its workbooks
# carry no `genFuelCost` row for gas-fired generators at all. That is the real
# shipped condition, and it must still yield variable O&M plus carbon costs
# rather than silently falling back to DEFAULT_GEN_MARGINAL_COST.
function test_gas_marginal_cost_without_a_fuel_price()
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        Generator = ["GasCCGT", "Coal"],
        Technology = ["Gas", "Hcoal"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT"), ("Hcoal", "Coal")],
        GeneratorsOfNode = [("A", "GasCCGT"), ("A", "Coal")],
        NaturalGas = OpenEMPIRE.NaturalGasSets(
            Node = ["A"],
            Generator = ["GasCCGT"],
        ),
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)

    # No genFuelCost entry for the gas generator, exactly as in full_model_int.
    parameters = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("Coal" => FixedProfile(3.0)),
        genEfficiency = Dict(
            "GasCCGT" => FixedProfile(0.5),
            "Coal" => FixedProfile(0.4),
        ),
        genVariableOMCost = Dict("GasCCGT" => 2.31, "Coal" => 1.0),
        genCO2Content = Dict("GasCCGT" => 0.2, "Coal" => 0.35),
        CO2price = FixedProfile(10.0),
    )
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = true,
    )
    sp = first(periods)
    @test haskey(parameters.genMargCost, "GasCCGT")
    # (3.6 / 0.5) * (0 fuel + 10 * 0.2) + 2.31
    @test parameters.genMargCost["GasCCGT"][sp] ≈ 16.71
    @test OpenEMPIRE.gen_marginal_cost(parameters, "GasCCGT", sp) ≈ 16.71
    @test OpenEMPIRE.gen_marginal_cost(parameters, "GasCCGT", sp) !=
          OpenEMPIRE.DEFAULT_GEN_MARGINAL_COST
    # The non-gas generator is untouched: (3.6 / 0.4) * (3 + 10 * 0.35) + 1
    @test parameters.genMargCost["Coal"][sp] ≈ 59.5

    # Under an emission cap CO2price is cleared, leaving variable O&M only, which
    # is what InternalEMPIRE's prepOperationalCostGen_rule produces for gas.
    capped = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("Coal" => FixedProfile(3.0)),
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genVariableOMCost = Dict("GasCCGT" => 2.31),
        genCO2Content = Dict("GasCCGT" => 0.2),
        CO2price = nothing,
    )
    OpenEMPIRE.preprocess_operational_cost(
        capped,
        sets,
        periods;
        natural_gas = true,
    )
    @test capped.genMargCost["GasCCGT"][sp] ≈ 2.31

    # With the module off the same input has no gas price anywhere, so it must
    # fail loudly instead of pricing gas generation at zero.
    off = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("Coal" => FixedProfile(3.0)),
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genVariableOMCost = Dict("GasCCGT" => 2.31),
        genCO2Content = Dict("GasCCGT" => 0.2),
        CO2price = FixedProfile(10.0),
    )
    err = try
        OpenEMPIRE.preprocess_operational_cost(off, sets, periods; natural_gas = false)
        nothing
    catch caught
        caught
    end
    @test err isa ArgumentError
    @test occursin("GasCCGT", err.msg)
    @test occursin("natural_gas", err.msg)

    # A generator with no efficiency profile keeps the documented fallback.
    bare = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("Coal" => FixedProfile(3.0)),
        genEfficiency = Dict("Coal" => FixedProfile(0.4)),
        genVariableOMCost = Dict("Coal" => 1.0),
        genCO2Content = Dict("Coal" => 0.35),
        CO2price = FixedProfile(10.0),
    )
    OpenEMPIRE.preprocess_operational_cost(bare, sets, periods; natural_gas = false)
    @test !haskey(bare.genMargCost, "GasCCGT")
end

# Dataset-level guard: the five full_model_int gas generators must all carry a
# real marginal cost once the module is enabled.
function test_full_model_int_gas_generators_are_priced()
    dataset = joinpath(pkgdir(OpenEMPIRE), "data", "full_model_int")
    isdir(dataset) || return
    sets, parameters = OpenEMPIRE.read_data(
        dataset;
        format = :csv,
        natural_gas = true,
        weather_scenarios = 1,
        gas_scenarios = 1,
    )
    periods = OpenEMPIRE.create_timestruct(7, 5, 4, 24, 2, 24, 1)
    parameters.CO2price = nothing  # use_emission_cap: True
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = true,
    )
    sp = first(strat_periods(periods))
    gas_generators = OpenEMPIRE.natural_gas_generators(sets)
    @test Set(gas_generators) ==
          Set(["GasCCGT", "GasCCS", "GasCCSadv", "GasOCGT", "Gasexisting"])
    for generator in gas_generators
        @test haskey(parameters.genMargCost, generator)
        cost = OpenEMPIRE.gen_marginal_cost(parameters, generator, sp)
        @test cost > 0
        # Non-CCS gas generators reduce exactly to variable O&M under a cap; the
        # CCS variants additionally carry base OpenEMPIRE's CCS transport and
        # storage term, which InternalEMPIRE does not model.
        if ("CCS", generator) in sets.GeneratorsOfTechnology
            @test cost > parameters.genVariableOMCost[generator]
        else
            @test cost ≈ parameters.genVariableOMCost[generator]
        end
    end
end

# Gas input problems must be fatal rather than a single warning: a missing
# terminal cost silently becomes 99999 EUR/t and a missing capacity becomes zero.
function test_natural_gas_validation_is_enforced()
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT")],
        NaturalGas = OpenEMPIRE.NaturalGasSets(
            Node = ["A"],
            Terminal = ["DomesticProduction"],
            TerminalsOfNode = [("A", "DomesticProduction")],
            OnshoreNode = ["A"],
            Generator = ["GasCCGT"],
        ),
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)

    complete = OpenEMPIRE.EmpireParams(
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        NaturalGas = OpenEMPIRE.NaturalGasParams(
            terminalCost = Dict(("A", "DomesticProduction", 1, 1) => 100.0),
            terminalCapacity = Dict(("A", "DomesticProduction", 1) => 50.0),
            reserves = Dict("A" => 1000.0),
            transportDemand = Dict(("A", 1) => 0.0),
        ),
    )
    @test isempty(OpenEMPIRE.validate_natural_gas(complete, sets, periods))

    # Missing reserve for a DomesticProduction terminal.
    no_reserve = deepcopy(complete)
    empty!(no_reserve.NaturalGas.reserves)
    @test any(
        contains("reserves"),
        OpenEMPIRE.validate_natural_gas(no_reserve, sets, periods),
    )

    # Missing terminal cost for a required period/gas-scenario key.
    no_cost = deepcopy(complete)
    empty!(no_cost.NaturalGas.terminalCost)
    @test any(
        contains("terminalCost"),
        OpenEMPIRE.validate_natural_gas(no_cost, sets, periods),
    )

    # A gas generator without an efficiency profile would otherwise surface as a
    # bare KeyError while building the gas-to-power conversion constraint.
    no_efficiency = deepcopy(complete)
    empty!(no_efficiency.genEfficiency)
    @test any(
        contains("genEfficiency"),
        OpenEMPIRE.validate_natural_gas(no_efficiency, sets, periods),
    )
end

# The controlled Julia/Pyomo parity fixture has one strategic period, one
# representative period and one scenario, so it cannot exercise strategic
# duration, season multiplicity, scenario probability, or the gas-price axis.
# This checks those weightings directly against hand-computed values.
function test_natural_gas_multi_period_scenario_weighting()
    weather_count, gas_count = 2, 3
    strategic_count, season_count, season_hours = 2, 2, 3
    periods = OpenEMPIRE.create_timestruct(
        strategic_count,
        5,
        season_count,
        season_hours,
        1,
        2,
        weather_count * gas_count,
    )
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT")],
        NaturalGas = OpenEMPIRE.NaturalGasSets(
            Node = ["A"],
            Terminal = ["DomesticProduction"],
            TerminalsOfNode = [("A", "DomesticProduction")],
            OnshoreNode = ["A"],
            Generator = ["GasCCGT"],
        ),
    )
    # Encode (period, gas scenario) in the price so the objective coefficient
    # identifies exactly which terminal cost was applied.
    terminal_cost = Dict(
        ("A", "DomesticProduction", period, gas) => 1000.0 * period + gas
        for period in 1:strategic_count for gas in 1:gas_count
    )
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genCapAvail = Dict(("A", "GasCCGT") => FixedProfile(1.0)),
        genCO2Content = Dict("GasCCGT" => 0.0),
        genMargCost = Dict("GasCCGT" => FixedProfile(1.0)),
        sload = Dict("A" => FixedProfile(0.0)),
        nodeLostLoadCost = Dict("A" => FixedProfile(1000.0)),
        seasonNames = ["winter", "spring", "peak1"],
        regularSeasonCount = season_count,
        NaturalGas = OpenEMPIRE.NaturalGasParams(
            terminalCost = terminal_cost,
            terminalCapacity = Dict(
                ("A", "DomesticProduction", period) => 100.0
                for period in 1:strategic_count
            ),
            reserves = Dict("A" => 1.0e6),
            transportDemand = Dict(
                ("A", period) => 0.0 for period in 1:strategic_count
            ),
            weatherScenarioCount = weather_count,
            gasScenarioCount = gas_count,
        ),
    )

    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods; natural_gas = true)
    OpenEMPIRE.create_constraints(
        model,
        sets,
        params,
        periods;
        natural_gas = true,
    )
    discounter = OpenEMPIRE.Discounter(0.05, 1, periods)
    OpenEMPIRE.create_objective(model, sets, params, periods, discounter; natural_gas = true)

    imports = model[:ngTerminalImport]
    objective = JuMP.objective_function(model)

    # One reserve row per (finite-reserve terminal, weather scenario, gas scenario).
    @test length(model[:natural_gas_max_reserves]) == weather_count * gas_count

    # Storage resets once per representative period per scenario, per strategic
    # period -- not once per strategic period.
    @test length(model[:natural_gas_storage_cyclic]) ==
          strategic_count * (season_count + 1) * weather_count * gas_count

    reserve_rows = model[:natural_gas_max_reserves]
    period_context = OpenEMPIRE._natural_gas_period_maps(periods, gas_count)
    covered = Set{Any}()
    for strategic_period in strat_periods(periods)
        for representative_period in repr_periods(strategic_period)
            for (combined, scenario) in enumerate(opscenarios(representative_period))
                gas_scenario = OpenEMPIRE.gas_scenario_index(combined, gas_count)
                for operational_period in scenario
                    variable = imports["A", "DomesticProduction", operational_period]

                    # Objective weight embeds discounting, season multiplicity and
                    # the 1/(W*G) scenario probability; the price must come from
                    # this period's own gas scenario.
                    expected_cost = OpenEMPIRE.objective_weight(
                        operational_period,
                        discounter;
                        type = "avg_year",
                    ) * terminal_cost[(
                        "A",
                        "DomesticProduction",
                        period_context[operational_period].strategic,
                        gas_scenario,
                    )]
                    @test JuMP.coefficient(objective, variable) ≈ expected_cost

                    # Exactly one reserve row references this variable, with the
                    # LeapYearsInvestment * seasScale weight, row-scaled.
                    expected_reserve_coefficient =
                        OpenEMPIRE.NATURAL_GAS_ROW_SCALE *
                        duration_strat(strategic_period) *
                        multiple_strat(strategic_period, operational_period)
                    matching = [
                        row for row in reserve_rows
                        if !isapprox(
                            JuMP.normalized_coefficient(row, variable),
                            0.0;
                            atol = 0,
                        )
                    ]
                    @test length(matching) == 1
                    @test JuMP.normalized_coefficient(only(matching), variable) ≈
                          expected_reserve_coefficient
                    push!(covered, only(matching))
                end
            end
        end
    end
    # Every reserve row is reached, so no scenario is left unconstrained.
    @test length(covered) == weather_count * gas_count

    # Scenario probabilities are uniform over the weather x gas product.
    scenario_probabilities = unique(
        round(TimeStruct.probability(t); digits = 12) for t in periods
    )
    @test scenario_probabilities == [round(1 / (weather_count * gas_count); digits = 12)]
end

function test_weather_profiles_replicate_across_gas_scenarios()
    mktempdir() do root
        _write_fixed_sample_scenario_data(root)
        sampling_rows = ["Period,Scenario,Season,Year,Month,Hour"]
        for weather in 1:2
            sample_hour = weather
            for (season, month) in
                (("winter", 1), ("spring", 4), ("summer", 7), ("fall", 10))
                push!(
                    sampling_rows,
                    "1,$weather,$season,2020,$month,$sample_hour",
                )
            end
            push!(sampling_rows, "1,$weather,peak,2020,0,0")
        end
        _write_csv(
            joinpath(root, "ScenarioData", "sampling_key.csv"),
            join(sampling_rows, "\n") * "\n",
        )
        config = Dict{String, Any}(
            "natural_gas" => true,
            "number_of_scenarios" => 2,
            "number_of_gas_scenarios" => 3,
            "regular_seasons" => ["winter", "spring", "summer", "fall"],
            "length_of_regular_season" => 4,
            "n_peak_seasons" => 2,
            "len_peak_season" => 2,
            "use_fixed_sample" => true,
            "time_format" => "%d/%m/%Y %H:%M",
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 2, 6)
        sets = _scenario_test_sets()
        params = OpenEMPIRE.EmpireParams(
            genCapAvailType = Dict(generator => 0.0 for generator in sets.Generator),
        )
        OpenEMPIRE.generate_scenario_csv!(
            root,
            periods,
            params,
            sets,
            config;
            rng = MersenneTwister(17),
        )
        rows = collect(
            CSV.File(joinpath(root, "ScenarioData", "sloadRaw.csv")),
        )
        values = Dict(
            (Int(row.Operationalhour), String(row.Scenario)) =>
                Float64(row.ElectricLoadRaw_in_MW)
            for row in rows
        )
        for hour in sort!(unique(first(key) for key in keys(values)))
            @test values[(hour, "scenario1")] == values[(hour, "scenario2")] ==
                  values[(hour, "scenario3")]
            @test values[(hour, "scenario4")] == values[(hour, "scenario5")] ==
                  values[(hour, "scenario6")]
        end
        @test any(
            values[(hour, "scenario1")] != values[(hour, "scenario4")]
            for hour in sort!(unique(first(key) for key in keys(values)))
        )
    end
end

function test_natural_gas_model_and_results()
    pipeline_power = 0.024
    model, periods, sets, params, discounter = _natural_gas_solved_fixture(
        weather_scenarios = 1,
        gas_scenarios = 1,
        pipeline_power = pipeline_power,
    )
    @test JuMP.termination_status(model) == JuMP.MOI.OPTIMAL
    @test all(
        JuMP.value(model[:loadShed][node, operational_period]) ≈ 0.0
        for node in OpenEMPIRE.nodes(sets) for operational_period in periods
    )

    expected_pipeline = 10.0 / (0.5 * params.NaturalGas.mwhPerTon)
    expected_compressor_generation = pipeline_power * expected_pipeline
    expected_import =
        expected_pipeline +
        expected_compressor_generation / (0.5 * params.NaturalGas.mwhPerTon)
    for operational_period in periods
        @test JuMP.value(
            model[:ngTransmission]["A", "B", operational_period],
        ) ≈ expected_pipeline
        @test JuMP.value(
            model[:genOperational]["A", "GasCCGT", operational_period],
        ) ≈ expected_compressor_generation
        @test JuMP.value(
            model[:ngTerminalImport][
                "A",
                "DomesticProduction",
                operational_period,
            ],
        ) ≈ expected_import
    end
    @test length(model[:natural_gas_max_reserves]) == 1
    @test length(model[:natural_gas_storage_balance].data) ==
          2 * length(periods)

    components = OpenEMPIRE.objective_component_values(
        model,
        sets,
        params,
        periods,
        discounter,
    )
    @test components.natural_gas_terminal_import ≈ JuMP.objective_value(model)
    @test components.natural_gas_transport_shedding ≈ 0.0

    mktempdir() do output_dir
        OpenEMPIRE.write_natural_gas_csvs(
            output_dir,
            model,
            sets,
            params,
            periods,
        )
        expected_files = (
            "ngTerminalImport.csv",
            "ngTransmission.csv",
            "ngForPower.csv",
            "ngStorage.csv",
            "naturalGasBalance.csv",
            "transportNaturalGas.csv",
            "results_natural_gas_terminals.csv",
            "results_natural_gas_pipeline.csv",
            "results_natural_gas_for_power.csv",
            "results_natural_gas_storage.csv",
            "results_natural_gas_balance.csv",
            "results_transport_naturalGas_operations.csv",
            "naturalGasOperationalDuals.csv",
        )
        @test all(isfile(joinpath(output_dir, file)) for file in expected_files)
        terminal_rows = collect(CSV.File(joinpath(output_dir, "ngTerminalImport.csv")))
        @test Set(Int(row.WeatherScenario) for row in terminal_rows) == Set((1,))
        @test Set(Int(row.GasScenario) for row in terminal_rows) == Set((1,))
        balance_rows = collect(CSV.File(joinpath(output_dir, "naturalGasBalance.csv")))
        @test all(abs(Float64(row.BalanceResidual_ton)) <= 1.0e-10 for row in balance_rows)
    end
end

function test_natural_gas_storage_transport_and_supply_edges()
    module_off_model, module_off_periods, module_off_sets, module_off_params, _ =
        _natural_gas_solved_fixture(natural_gas_gate = false)
    @test JuMP.termination_status(module_off_model) == JuMP.MOI.OPTIMAL
    @test !haskey(
        JuMP.object_dictionary(module_off_model),
        :ngTerminalImport,
    )
    module_off_time = only(collect(module_off_periods))
    @test JuMP.value(
        module_off_model[:genOperational][
            "B",
            "GasCCGT",
            module_off_time,
        ],
    ) ≈ 10.0
    mktempdir() do result_dir
        output_dir = OpenEMPIRE.write_solution_tables(
            result_dir,
            module_off_model,
            module_off_sets,
            module_off_params,
            module_off_periods,
        )
        @test !isfile(joinpath(output_dir, "ngTerminalImport.csv"))
        @test !isfile(joinpath(output_dir, "naturalGasBalance.csv"))
    end

    storage_model, storage_periods, storage_sets, storage_params, storage_discounter =
        _natural_gas_solved_fixture(
            pipeline_capacity = 16.0,
            storage_capacity_b = 10.0,
            transport_demand_b_ton_per_hour = 1.0,
            load_b = [69.5, 139.0],
            generator_marginal_cost = 2.0,
            generator_capacity = 200.0,
        )
    @test JuMP.termination_status(storage_model) == JuMP.MOI.OPTIMAL
    storage_times = collect(storage_periods)
    @test [
        JuMP.value(storage_model[:ngTransmission]["A", "B", time])
        for time in storage_times
    ] ≈ [16.0, 16.0]
    @test [
        JuMP.value(storage_model[:ngStorageOperational]["B", time])
        for time in storage_times
    ] ≈ [10.0, 5.0]
    @test [
        JuMP.value(storage_model[:ngStorageCharge]["B", time])
        for time in storage_times
    ] ≈ [5.0, 0.0]
    @test [
        JuMP.value(storage_model[:ngStorageDischarge]["B", time])
        for time in storage_times
    ] ≈ [0.0, 5.0]

    # Storage and reserve rows are built scaled by NATURAL_GAS_ROW_SCALE for
    # conditioning, which inflates their duals by the reciprocal. With unit
    # charge/discharge efficiencies and interior storage the marginal value of
    # stored gas must equal the nodal gas price, so this pins the reported duals
    # to EUR/ton and fails loudly if the scale correction is ever dropped.
    mktempdir() do dual_dir
        dual_output = OpenEMPIRE.write_solution_tables(
            dual_dir,
            storage_model,
            storage_sets,
            storage_params,
            storage_periods,
        )
        dual_rows = collect(
            CSV.File(joinpath(dual_output, "naturalGasOperationalDuals.csv")),
        )
        @test !isempty(dual_rows)
        for row in dual_rows
            gas_price = Float64(row.GasPrice_EUR_per_ton)
            storage_dual = Float64(row.StorageBalanceDual_EUR_per_ton)
            @test isfinite(gas_price) && isfinite(storage_dual)
            @test storage_dual ≈ gas_price
        end
        # The upstream terminal price is 100 EUR/ton, so a lost 1e-3 row-scale
        # correction would show up here as ~1e5.
        @test all(
            99.0 <= Float64(row.GasPrice_EUR_per_ton) <= 110.0 for row in dual_rows
        )
    end
    @test all(
        JuMP.value(
            storage_model[:transportNaturalGasDemandMet]["B", time],
        ) ≈ 1.0 for time in storage_times
    )
    @test all(
        JuMP.value(
            storage_model[:transportNaturalGasDemandShed]["B", time],
        ) ≈ 0.0 for time in storage_times
    )
    storage_components = OpenEMPIRE.objective_component_values(
        storage_model,
        storage_sets,
        storage_params,
        storage_periods,
        storage_discounter,
    )
    @test storage_components.natural_gas_transport_shedding ≈ 0.0

    shed_cost = 54321.0
    transport_model, transport_periods, transport_sets, transport_params,
    transport_discounter = _natural_gas_solved_fixture(
        terminal_capacity = 0.0,
        pipeline_capacity = 0.0,
        pipeline_power = 0.0,
        transport_demand_b_ton_per_hour = 1.0,
        transport_curtail_cost = shed_cost,
        load_b = [0.0],
    )
    transport_time = only(collect(transport_periods))
    @test JuMP.termination_status(transport_model) == JuMP.MOI.OPTIMAL
    @test JuMP.value(
        transport_model[:transportNaturalGasDemandMet]["B", transport_time],
    ) ≈ 0.0
    @test JuMP.value(
        transport_model[:transportNaturalGasDemandShed]["B", transport_time],
    ) ≈ 1.0
    transport_components = OpenEMPIRE.objective_component_values(
        transport_model,
        transport_sets,
        transport_params,
        transport_periods,
        transport_discounter,
    )
    expected_shed_cost = shed_cost * OpenEMPIRE.objective_weight(
        transport_time,
        transport_discounter;
        type = "avg_year",
    )
    @test transport_components.natural_gas_transport_shedding ≈
          expected_shed_cost
    @test JuMP.objective_value(transport_model) ≈ expected_shed_cost

    zero_supply_model, zero_supply_periods, _, _, _ =
        _natural_gas_solved_fixture(
            terminal_capacity = 0.0,
            pipeline_capacity = 0.0,
            pipeline_power = 0.0,
        )
    zero_supply_time = only(collect(zero_supply_periods))
    @test JuMP.termination_status(zero_supply_model) == JuMP.MOI.OPTIMAL
    @test JuMP.value(
        zero_supply_model[:ngTerminalImport][
            "A",
            "DomesticProduction",
            zero_supply_time,
        ],
    ) ≈ 0.0
    @test JuMP.value(zero_supply_model[:loadShed]["B", zero_supply_time]) ≈
          10.0

    infeasible_model, _, _, _, _ = _natural_gas_solved_fixture(
        terminal_capacity = 0.0,
        pipeline_capacity = 0.0,
        pipeline_power = 0.0,
        fix_load_shed = true,
    )
    @test JuMP.termination_status(infeasible_model) ==
          JuMP.MOI.INFEASIBLE
    @test JuMP.primal_status(infeasible_model) == JuMP.MOI.NO_SOLUTION

    emission_cap_model, emission_cap_periods, _, _, _ =
        _natural_gas_solved_fixture(
            co2_content = 0.2,
            co2_cap = 0.0,
        )
    emission_cap_time = only(collect(emission_cap_periods))
    @test JuMP.termination_status(emission_cap_model) ==
          JuMP.MOI.OPTIMAL
    @test haskey(JuMP.object_dictionary(emission_cap_model), :emission_cap)
    @test JuMP.value(
        emission_cap_model[:genOperational][
            "B",
            "GasCCGT",
            emission_cap_time,
        ],
    ) ≈ 0.0 atol = 1.0e-9
    @test JuMP.value(
        emission_cap_model[:loadShed]["B", emission_cap_time],
    ) ≈ 10.0
end

function test_natural_gas_three_by_three_scenarios()
    params = OpenEMPIRE.EmpireParams(
        NaturalGas = OpenEMPIRE.NaturalGasParams(
            weatherScenarioCount = 3,
            gasScenarioCount = 3,
        ),
    )
    errors = String[]
    OpenEMPIRE._check_natural_gas_params!(errors, params, nothing, nothing)
    @test any(
        occursin("gasScenarioCount must equal 1", error) for error in errors
    )
end

# `test_natural_gas_oos_compatibility_and_full_year_streaming` is deliberately absent
# from this branch. It exercises the gas module against the out-of-sample runner
# (`_oos_structural_config`, full-year streaming), and the OOS stack is not part of
# this PR - it is still in review as PRs #18-#29. The test belongs on whichever branch
# carries both, and reintroducing it here would only add a dependency this change does
# not have. Everything it covered about the gas module itself is covered by the tests
# that remain.

"""
Configuring more than one gas scenario is rejected until reference parity exists.

The weather x gas combination convention has only ever been checked against a unit
test written alongside the implementation, never against `empire.py`, because
`full_model_int` carries only `GasScenario = 1`. A gas-major ordering in the
reference would attach prices to the wrong scenarios while leaving row counts,
coefficients and bounds identical, so deterministic delivery rejects the unverified
axis instead of returning a plausible but potentially mis-mapped result.
"""
function test_multiple_gas_scenarios_rejected_until_verified()
    par = OpenEMPIRE.EmpireParams()
    par.NaturalGas = OpenEMPIRE.NaturalGasParams(
        weatherScenarioCount = 2,
        gasScenarioCount = 2,
    )
    errs = String[]
    OpenEMPIRE._check_natural_gas_params!(errs, par, nothing, nothing)
    @test any(occursin("gasScenarioCount must equal 1", error) for error in errs)

    # One gas scenario is the verified configuration and must stay silent.
    quiet = OpenEMPIRE.EmpireParams()
    quiet.NaturalGas = OpenEMPIRE.NaturalGasParams(
        weatherScenarioCount = 2,
        gasScenarioCount = 1,
    )
    errs2 = String[]
    OpenEMPIRE._check_natural_gas_params!(errs2, quiet, nothing, nothing)
    @test isempty(errs2)
end

function test_gas_comparator_negative_controls()
    python = something(Sys.which("python3"), Sys.which("python"), nothing)
    python === nothing && return @test_skip "Python is unavailable"
    script = joinpath(pkgdir(OpenEMPIRE), "scripts", "test_gas_comparators.py")
    @test success(run(ignorestatus(`$python $script`)))
end
