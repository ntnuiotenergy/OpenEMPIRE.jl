function _industry_dataset()
    dataset = joinpath(pkgdir(OpenEMPIRE), "data", "full_model_int")
    isdir(dataset) || return nothing
    return dataset
end

function test_industry_loading_gates_and_active_pathways()
    @test !OpenEMPIRE.industry_enabled(Dict{String, Any}())
    @test OpenEMPIRE.industry_enabled(Dict("industry" => true))
    dataset = _industry_dataset()
    dataset === nothing && return @test_skip "full_model_int dataset is unavailable"

    sets_off, params_off = OpenEMPIRE.read_data(dataset; format = :csv)
    @test !OpenEMPIRE.has_industry(sets_off)
    @test isempty(params_off.Industry.steelLifetime)
    @test_throws ArgumentError OpenEMPIRE.read_data(
        dataset; format = :csv, industry = true,
    )
    @test_throws ArgumentError OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, industry = true,
        gas_scenarios = 2,
    )

    gas_sets, gas_params = OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, industry = true,
    )
    @test OpenEMPIRE.has_industry(gas_sets)
    @test gas_sets.Industry.ActiveSteelPlant == [
        "BF-BOF", "BF-BOF-BioCarbon", "EAF", "Scrap",
    ]
    @test gas_sets.Industry.ActiveCementPlant == ["NG-Cement"]
    @test gas_sets.Industry.ActiveAmmoniaPlant == ["NG-Ammonia"]
    @test !gas_sets.Industry.RefineryActive
    @test Set(keys(gas_sets.Industry.InactivePathways)) == Set([
        "H2-DRI", "BF-BOF-CCS", "H2-Cement", "NG-CCS-Cement",
        "H2-Ammonia", "OilRefinery",
    ])
    @test isempty(OpenEMPIRE.validate_industry(gas_params, gas_sets))

    sets, params = OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, hydrogen = true, industry = true,
    )
    @test sets.Industry.ActiveSteelPlant == sets.Industry.SteelPlant
    @test sets.Industry.ActiveCementPlant == sets.Industry.CementPlant
    @test sets.Industry.ActiveAmmoniaPlant == sets.Industry.AmmoniaPlant
    @test sets.Industry.RefineryActive
    @test isempty(sets.Industry.InactivePathways)
    @test params.Industry.rampFractionPerHour == 0.1
    @test params.Industry.maximumScrapShare == 0.45
    @test params.Industry.hoursPerYear == 8760.0
end

function test_industry_validation_and_units()
    dataset = _industry_dataset()
    dataset === nothing && return @test_skip "full_model_int dataset is unavailable"
    sets, params = OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, hydrogen = true, industry = true,
    )
    periods = OpenEMPIRE.create_timestruct(7, 5, 1, 1, 0, 0, 1)
    @test isempty(OpenEMPIRE.validate_industry(params, sets, periods))

    saved = params.Industry.maximumScrapShare
    params.Industry.maximumScrapShare = 1.1
    @test any(occursin("maximumScrapShare must be at most 1", issue)
              for issue in OpenEMPIRE.validate_industry(params, sets, periods))
    params.Industry.maximumScrapShare = saved
    key, value = first(params.Industry.steelCapitalCost)
    delete!(params.Industry.steelCapitalCost, key)
    @test any(occursin("steelCapitalCost is missing 1 required key", issue)
              for issue in OpenEMPIRE.validate_industry(params, sets, periods))
    params.Industry.steelCapitalCost[key] = value
    params.Industry.steelCO2Emissions["BF-BOF"] = NaN
    @test any(occursin("steelCO2Emissions", issue)
              for issue in OpenEMPIRE.validate_industry(params, sets, periods))

    mktempdir() do directory
        general = joinpath(directory, "General")
        mkpath(general)
        write(joinpath(general, "availableBioEnergy.csv"), "Period,Value\n1,1\n")
        @test_throws ArgumentError OpenEMPIRE._required_csv(
            directory, "General", "AvailableBioEnergy.csv",
        )

        path = joinpath(directory, "Constants.csv")
        write(path, "Parameter,Value,Unit,Source\nramp_fraction_per_hour,nope,share,test\n")
        error = try
            OpenEMPIRE._read_industry_constants(path)
            nothing
        catch exception
            exception
        end
        @test error isa ArgumentError
        @test occursin("Industry", sprint(showerror, error))
        @test occursin("Value", sprint(showerror, error))
        @test occursin(path, sprint(showerror, error))

        table_path = joinpath(directory, "PlantPeriod.csv")
        headers = ("PlantType", "Period", "Value")
        cases = (
            ("PlantType,Period,Value\nA,1,\n", "empty value"),
            ("PlantType,Period,Value\nA,1,word\n", "expected a number"),
            ("PlantType,Period,Value\nA,1.5,1\n", "expected an integer"),
            ("PlantType,Period,Value\nA,999999999999999999999,1\n", "out of range"),
            ("PlantType,Period,Value\nA,1,NaN\n", "must be finite"),
            ("PlantType,Period,Value\nA,1,Inf\n", "must be finite"),
            ("PlantType,Period,Value\nA,1,-1\n", "must be non-negative"),
            ("PlantType,Period,Value\nA,1,1\nA,1,2\n", "duplicate industry key"),
            ("PlantType,Wrong,Value\nA,1,1\n", "has headers"),
        )
        for (contents, expected) in cases
            write(table_path, contents)
            error = try
                OpenEMPIRE._read_sector_plant_period_values(
                    table_path, headers, "Industry",
                )
                nothing
            catch exception
                exception
            end
            @test error isa ArgumentError
            message = sprint(showerror, error)
            @test occursin(lowercase(expected), lowercase(message))
            @test occursin(table_path, message)
        end
    end
end

function test_industry_dataset_validator_negative_controls()
    python = something(Sys.which("python3"), Sys.which("python"), nothing)
    python === nothing && return @test_skip "Python is unavailable"
    script = joinpath(pkgdir(OpenEMPIRE), "scripts", "test_industry_dataset_validator.py")
    @test success(run(ignorestatus(`$python $script`)))
end

function test_industry_gas_only_model()
    dataset = _industry_dataset()
    dataset === nothing && return @test_skip "full_model_int dataset is unavailable"
    sets, params = OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, industry = true,
    )
    periods = OpenEMPIRE.create_timestruct(
        1, 5, 1, 1, 0, 0, 1; operational_hours_per_year = 1,
    )
    params.WACC = 0.05
    params.discountRate = 0.05
    OpenEMPIRE.preprocess_params(
        params, sets, periods; natural_gas = true, industry = true,
    )
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(
        model, sets, periods; natural_gas = true, industry = true,
    )
    OpenEMPIRE.create_constraints(
        model, sets, params, periods; natural_gas = true, industry = true,
    )
    OpenEMPIRE.create_objective(
        model, sets, params, periods, Discounter(0.05, 1, periods);
        natural_gas = true, industry = true,
    )
    dictionary = JuMP.object_dictionary(model)
    @test !haskey(dictionary, :oilRefined)
    @test !haskey(dictionary, :hydrogen_flow_balance)
    @test Set(sets.Industry.ActiveSteelPlant) ==
          Set(("BF-BOF", "BF-BOF-BioCarbon", "EAF", "Scrap"))
    JuMP.optimize!(model)
    @test JuMP.termination_status(model) == JuMP.MOI.OPTIMAL
end

function test_industry_model_results_and_oos()
    dataset = _industry_dataset()
    dataset === nothing && return @test_skip "full_model_int dataset is unavailable"
    sets, params = OpenEMPIRE.read_data(
        dataset; format = :csv, natural_gas = true, hydrogen = true, industry = true,
    )
    periods = OpenEMPIRE.create_timestruct(
        1, 5, 1, 1, 0, 0, 1; operational_hours_per_year = 1,
    )
    params.WACC = 0.05
    params.discountRate = 0.05
    OpenEMPIRE.preprocess_params(
        params, sets, periods; natural_gas = true, hydrogen = true, industry = true,
    )
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(
        model, sets, periods; natural_gas = true, hydrogen = true, industry = true,
    )
    OpenEMPIRE.create_constraints(
        model, sets, params, periods;
        natural_gas = true, hydrogen = true, industry = true,
    )
    OpenEMPIRE.create_objective(
        model, sets, params, periods, Discounter(0.05, 1, periods);
        natural_gas = true, hydrogen = true, industry = true,
    )
    @test length(model[:steelProduced]) ==
          length(sets.Industry.SteelProducer) * length(sets.Industry.ActiveSteelPlant)
    @test length(model[:cementProduced]) ==
          length(sets.Industry.CementProducer) * length(sets.Industry.ActiveCementPlant)
    @test length(model[:ammoniaProduced]) ==
          length(sets.Industry.AmmoniaProducer) * length(sets.Industry.ActiveAmmoniaPlant)
    @test length(model[:industry_steel_demand]) == length(sets.Industry.SteelProducer)
    @test length(model[:industry_max_scrap_capacity]) == 1
    @test haskey(JuMP.object_dictionary(model), :industry_biomass_limit)

    steel_node = first(sets.Industry.SteelProducer)
    operational_period = first(periods)
    @test JuMP.normalized_rhs(
        model[:industry_steel_demand][steel_node, operational_period],
    ) ≈ params.Industry.steelYearlyProduction[(steel_node, 1)] /
         params.Industry.hoursPerYear

    node = first(intersect(Set(sets.Industry.CementProducer), Set(sets.NaturalGas.Node)))
    plant = first(filter(p -> occursin("ng", lowercase(p)), sets.Industry.ActiveCementPlant))
    gas_constraint = model[:natural_gas_flow_balance][node, operational_period]
    @test JuMP.normalized_coefficient(
        gas_constraint, model[:cementProduced][node, plant, operational_period],
    ) ≈ -OpenEMPIRE.INDUSTRY_H2_KG_TO_TON *
         params.Industry.cementFuelConsumption[(plant, 1)]

    flow_constraint = model[:flow_balance][node, operational_period]
    @test JuMP.normalized_coefficient(
        flow_constraint, model[:cementProduced][node, plant, operational_period],
    ) ≈ -params.Industry.cementElectricityConsumption[(plant, 1)]

    hydrogen_plant = only(filter(
        p -> lowercase(p) == "h2-cement", sets.Industry.ActiveCementPlant,
    ))
    hydrogen_constraint = model[:hydrogen_flow_balance][node, operational_period]
    @test JuMP.normalized_coefficient(
        hydrogen_constraint,
        model[:cementProduced][node, hydrogen_plant, operational_period],
    ) ≈ -OpenEMPIRE.INDUSTRY_H2_KG_TO_TON *
         params.Industry.cementFuelConsumption[(hydrogen_plant, 1)]

    ccs_plant = only(filter(
        p -> lowercase(p) == "ng-ccs-cement", sets.Industry.ActiveCementPlant,
    ))
    co2_constraint = model[:co2_flow_balance][node, operational_period]
    @test JuMP.normalized_coefficient(
        co2_constraint, model[:cementProduced][node, ccs_plant, operational_period],
    ) ≈ OpenEMPIRE._industry_cement_emission_factor(
        params, ccs_plant, 1; captured = true,
    )

    bio_plant = only(filter(
        p -> lowercase(p) == "bf-bof-biocarbon", sets.Industry.ActiveSteelPlant,
    ))
    bio_node = first(sets.Industry.SteelProducer)
    bio_constraint = only(model[:industry_biomass_limit])
    @test JuMP.normalized_coefficient(
        bio_constraint,
        model[:steelProduced][bio_node, bio_plant, operational_period],
    ) ≈ multiple_strat(first(strat_periods(periods)), operational_period) *
         params.Industry.steelBiomassConsumption[(bio_plant, 1)]

    JuMP.optimize!(model)
    @test JuMP.termination_status(model) == JuMP.MOI.OPTIMAL
    @test isfinite(JuMP.objective_value(model))
    components = OpenEMPIRE.objective_component_values(
        model, sets, params, periods, Discounter(0.05, 1, periods),
    )
    @test sum(values(components)) ≈ JuMP.objective_value(model) rtol = 1.0e-12
    @test components.industry_investment >= 0

    mktempdir() do result_dir
        output_dir = OpenEMPIRE.write_solution_tables(result_dir, model, sets, params, periods)
        # The 14 fixed-investment alias assertions and the fix_investments_from_results!
        # round-trip are deliberately absent: they rely on the Industry additions to
        # out_of_sample.jl, and the extended out-of-sample stack is not part of this PR
        # (PRs #18-#29). The Industry module itself is covered by everything above.
        @test read(joinpath(output_dir, "industrySteelOperations.csv"), String) ==
              read(joinpath(output_dir, "results_industry_steel_production.csv"), String)
        @test isfile(joinpath(output_dir, "industryRefineryOperations.csv"))

    end
end

function test_industry_controlled_solution_parity()
    python = get(
        ENV,
        "OPENEMPIRE_PYTHON",
        something(Sys.which("python3"), Sys.which("python"), ""),
    )
    isempty(python) && return @test_skip "Python is unavailable"
    dependency_check = run(
        ignorestatus(`$python -c "import pyomo.environ; import highspy"`),
    )
    success(dependency_check) || return @test_skip "Pyomo/HiGHS is unavailable"

    root = pkgdir(OpenEMPIRE)
    fixture = joinpath(root, "test", "data", "industry_parity")
    julia_script = joinpath(root, "scripts", "industry_parity_julia.jl")
    python_script = joinpath(root, "scripts", "industry_parity_python.py")
    comparator = joinpath(root, "scripts", "compare_industry_parity.py")
    mktempdir() do output_dir
        julia = Base.julia_cmd()
        for (suffix, option) in (("price", nothing), ("cap", "--emission-cap"))
            julia_output = joinpath(output_dir, "julia_$suffix.csv")
            python_output = joinpath(output_dir, "python_$suffix.csv")
            julia_command = isnothing(option) ?
                `$julia --project=$root $julia_script $fixture $julia_output` :
                `$julia --project=$root $julia_script $fixture $julia_output $option`
            python_command = isnothing(option) ?
                `$python $python_script $fixture $python_output` :
                `$python $python_script $fixture $python_output $option`
            @test success(run(ignorestatus(julia_command)))
            @test success(run(ignorestatus(python_command)))
            @test success(run(
                ignorestatus(`$python $comparator $julia_output $python_output`),
            ))
        end
    end
end

function test_industry_sector_volume_certificate()
    python = get(
        ENV,
        "OPENEMPIRE_PYTHON",
        something(Sys.which("python3"), Sys.which("python"), ""),
    )
    isempty(python) && return @test_skip "Python is unavailable"
    script = joinpath(pkgdir(OpenEMPIRE), "test", "test_industry_result_certificate.py")
    @test success(run(ignorestatus(`$python $script`)))
end

function test_industry_verifier_reconciliation_gates()
    python = get(
        ENV,
        "OPENEMPIRE_PYTHON",
        something(Sys.which("python3"), Sys.which("python"), ""),
    )
    isempty(python) && return @test_skip "Python is unavailable"
    script = joinpath(pkgdir(OpenEMPIRE), "test", "test_industry_verifier_gates.py")
    @test success(run(ignorestatus(`$python $script`)))
end
