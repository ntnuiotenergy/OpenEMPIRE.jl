function _country_constraint_test_sets(; with_country = true)
    return OpenEMPIRE.EmpireSets(
        Generator = ["gas"],
        ThermalGenerators = ["gas"],
        Technology = ["thermal"],
        Node = ["A1", "A2"],
        Countries = with_country ? ["Country A"] : String[],
        NodesOfCountry = with_country ? [("Country A", "A1"), ("Country A", "A2")] : Tuple{String, String}[],
        GeneratorsOfTechnology = [("thermal", "gas")],
        GeneratorsOfNode = [("A1", "gas"), ("A2", "gas")],
    )
end

function _country_constraint_test_params(; with_country = true)
    params = OpenEMPIRE.EmpireParams(
        genCapAvailType = Dict("gas" => 1.0),
        genLifetime = Dict("gas" => 30.0),
        genInitCap = Dict(
            ("A1", "gas") => StrategicProfile([60.0]),
            ("A2", "gas") => StrategicProfile([50.0]),
        ),
    )
    if with_country
        params.genCountryMaxBuiltCap[("Country A", "thermal")] = StrategicProfile([30.0])
        params.genCountryMinBuiltCap[("Country A", "thermal")] = StrategicProfile([10.0])
        params.genCountryMaxInstalledCapRaw[("Country A", "thermal")] = 100.0
    end
    return params
end

function test_country_generator_capacity_constraints()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sp = first(strat_periods(periods))
    sets = _country_constraint_test_sets()
    params = _country_constraint_test_params()

    OpenEMPIRE.preprocess_country_max_installed_cap(params, sets, periods)
    @test OpenEMPIRE.country_max_inst_cap(params, "Country A", "thermal", sp) == 110.0

    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)
    OpenEMPIRE.create_generator_constraints(model, sets, params, periods)
    @test length(model[:max_inv_tech_country]) == 1
    @test length(model[:min_inv_tech_country]) == 1
    @test length(model[:max_inst_tech_country]) == 1
end

function test_country_generator_constraints_are_data_driven()
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    sets = _country_constraint_test_sets(; with_country = false)
    params = _country_constraint_test_params(; with_country = false)

    OpenEMPIRE.preprocess_country_max_installed_cap(params, sets, periods)
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)
    OpenEMPIRE.create_generator_constraints(model, sets, params, periods)
    @test isempty(model[:max_inv_tech_country])
    @test isempty(model[:min_inv_tech_country])
    @test isempty(model[:max_inst_tech_country])
end
