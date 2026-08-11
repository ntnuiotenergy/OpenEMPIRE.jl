function test_hydrogen_csv_loading_and_validation()
    @test !OpenEMPIRE.hydrogen_enabled(Dict{String, Any}())
    @test OpenEMPIRE.hydrogen_enabled(Dict("hydrogen" => true))

    mktempdir() do root
        dataset = _write_toy_csv_dataset(root)
        sets, params = OpenEMPIRE.read_data(dataset; format = :csv)
        @test !OpenEMPIRE.has_hydrogen(sets)
        @test isempty(params.Hydrogen.electrolyzerCapitalCost)

        gas_gate_error = try
            OpenEMPIRE.read_data(dataset; format = :csv, hydrogen = true)
            nothing
        catch err
            err
        end
        @test gas_gate_error isa ArgumentError
        @test occursin("hydrogen=true requires natural_gas=true", sprint(showerror, gas_gate_error))

        stochastic_error = try
            OpenEMPIRE.read_data(
                dataset;
                format = :csv,
                natural_gas = true,
                hydrogen = true,
                gas_scenarios = 2,
            )
            nothing
        catch err
            err
        end
        @test stochastic_error isa ArgumentError
        @test occursin("number_of_gas_scenarios=1", sprint(showerror, stochastic_error))
    end

    dataset = joinpath(@__DIR__, "..", "data", "full_model_int")
    isdir(dataset) || return @test_skip "full_model_int dataset is unavailable"
    sets, params = OpenEMPIRE.read_data(
        dataset;
        format = :csv,
        natural_gas = true,
        hydrogen = true,
        weather_scenarios = 1,
        gas_scenarios = 1,
    )
    periods = OpenEMPIRE.create_timestruct(7, 5, 4, 168, 2, 24, 1)
    @test OpenEMPIRE.has_hydrogen(sets)
    @test length(sets.Hydrogen.ProductionNode) == 36
    @test sets.Hydrogen.Generator == Set([
        "HydrogenCCGT",
        "HydrogenOCGT",
        "Hydrogenfuelcell",
    ])
    @test all(from <= to for (from, to) in sets.Hydrogen.Corridor)
    @test params.Hydrogen.hydrogenMWhPerTon == 33.3
    @test params.Hydrogen.storageInitialFraction == 0.5
    @test params.Hydrogen.reformerElectricityUse[("SMR", 1)] == -2 / 3
    @test params.Hydrogen.terminalPrice[("Spain", "PipelineH2Import", 2)] ≈
          2738.8080477634116
    @test isempty(OpenEMPIRE.validate_hydrogen(params, sets, periods))
    reduced_periods = OpenEMPIRE.create_timestruct(2, 5, 1, 24, 2, 24, 1)
    @test isempty(OpenEMPIRE.validate_hydrogen(params, sets, reduced_periods))

    missing = pop!(params.Hydrogen.reformerEfficiency, ("SMR", 1))
    issues = OpenEMPIRE.validate_hydrogen(params, sets, periods)
    @test any(occursin("reformerEfficiency is missing 1 required key", issue) for issue in issues)
    params.Hydrogen.reformerEfficiency[("SMR", 1)] = missing

    missing_storage_cost = pop!(params.Hydrogen.storageCapitalCost, ("SaltCavern", 1))
    issues = OpenEMPIRE.validate_hydrogen(params, sets, periods)
    @test any(occursin("storageCapitalCost is missing 1 required key", issue) for issue in issues)
    params.Hydrogen.storageCapitalCost[("SaltCavern", 1)] = missing_storage_cost

    missing_storage_om = pop!(params.Hydrogen.storageFixedOMCost, ("SteelTank", 1))
    issues = OpenEMPIRE.validate_hydrogen(params, sets, periods)
    @test any(occursin("storageFixedOMCost is missing 1 required key", issue) for issue in issues)
    params.Hydrogen.storageFixedOMCost[("SteelTank", 1)] = missing_storage_om

    params.Hydrogen.reformerElectricityUse[("SMR_CCS", 1)] = -0.1
    issues = OpenEMPIRE.validate_hydrogen(params, sets, periods)
    @test any(occursin("may be negative only", issue) for issue in issues)
end

function test_hydrogen_sparse_variables()
    dataset = joinpath(@__DIR__, "..", "data", "full_model_int")
    isdir(dataset) || return @test_skip "full_model_int dataset is unavailable"
    sets, _ = OpenEMPIRE.read_data(
        dataset;
        format = :csv,
        natural_gas = true,
        hydrogen = true,
    )
    periods = OpenEMPIRE.create_timestruct(
        1, 5, 1, 2, 0, 0, 1; operational_hours_per_year = 2,
    )
    model = JuMP.Model()
    OpenEMPIRE.create_variables(
        model,
        sets,
        periods;
        natural_gas = true,
        hydrogen = true,
    )
    @test length(model[:electrolyzerCapBuilt]) == 36
    @test length(model[:reformerCapBuilt]) == 105
    @test length(model[:hydrogenPipelineFlow]) == 376
    @test length(model[:hydrogenStorageLevel]) == 98
    @test length(model[:co2PipelineFlow]) == 348
    @test length(model[:hydrogenStorageCompressionPower]) == 98
    @test !haskey(JuMP.object_dictionary(JuMP.Model()), :electrolyzerCapBuilt)
end

function test_hydrogen_full_model_smoke()
    dataset = joinpath(@__DIR__, "..", "data", "full_model_int")
    isdir(dataset) || return @test_skip "full_model_int dataset is unavailable"
    sets, params = OpenEMPIRE.read_data(
        dataset;
        format = :csv,
        natural_gas = true,
        hydrogen = true,
    )
    periods = OpenEMPIRE.create_timestruct(
        1, 5, 1, 1, 0, 0, 1; operational_hours_per_year = 1,
    )
    params.WACC = 0.05
    params.discountRate = 0.05
    OpenEMPIRE.preprocess_params(
        params,
        sets,
        periods;
        natural_gas = true,
        hydrogen = true,
    )
    for generator in sets.Hydrogen.Generator
        @test params.genMargCost[generator][first(strat_periods(periods))] ≈
              get(params.genVariableOMCost, generator, 0.0) +
              OpenEMPIRE.co2_price(params, first(strat_periods(periods))) *
              OpenEMPIRE.co2_content(params, generator) * 3.6 /
              params.genEfficiency[generator][first(strat_periods(periods))]
    end
    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(
        model, sets, periods; natural_gas = true, hydrogen = true,
    )
    OpenEMPIRE.create_constraints(
        model, sets, params, periods; natural_gas = true, hydrogen = true,
    )
    OpenEMPIRE.create_objective(
        model,
        sets,
        params,
        periods,
        Discounter(0.05, 1, periods);
        natural_gas = true,
        hydrogen = true,
    )
    @test haskey(JuMP.object_dictionary(model), :hydrogen_flow_balance)
    @test haskey(JuMP.object_dictionary(model), :co2_flow_balance)
    repurposed_arc = first(sets.Hydrogen.RepurposableGasCorridor)
    pipeline_arc = minmax(repurposed_arc...)
    strategic_period = first(strat_periods(periods))
    repurpose_coefficient = JuMP.normalized_coefficient(
        model[:hydrogen_pipeline_installed][pipeline_arc, strategic_period],
        model[:hydrogenRepurposedGasPipelineCapInstalled][repurposed_arc..., strategic_period],
    )
    @test abs(repurpose_coefficient) ≈
          params.Hydrogen.repurposeEnergyFlowFactor *
          params.NaturalGas.mwhPerTon / params.Hydrogen.hydrogenMWhPerTon
    objective = JuMP.objective_function(model)
    @test length(objective.terms) > 2000
    operational_period = first(periods)
    @test JuMP.coefficient(
        objective,
        model[:hydrogenImportTon]["Spain", "PipelineH2Import", operational_period],
    ) > 0
    JuMP.optimize!(model)
    @test JuMP.termination_status(model) == JuMP.MOI.OPTIMAL
    @test isfinite(JuMP.objective_value(model))
    components = OpenEMPIRE.objective_component_values(
        model, sets, params, periods, Discounter(0.05, 1, periods),
    )
    @test sum(values(components)) ≈ JuMP.objective_value(model) atol = 1.0e-6
    @test keys(components) == (
        :generator_investment,
        :storage_investment,
        :transmission_investment,
        :offshore_converter_investment,
        :load_shedding,
        :generator_operation,
        :natural_gas_terminal_import,
        :natural_gas_transport_shedding,
        :hydrogen_investment,
        :hydrogen_terminal_import,
        :hydrogen_reformer_operation,
        :hydrogen_transport_shedding,
    )
    mktempdir() do output_dir
        solution_dir = OpenEMPIRE.write_solution_tables(output_dir, model, sets, params, periods)
        @test read(
            joinpath(solution_dir, "hydrogenProduction.csv"),
            String,
        ) == read(joinpath(solution_dir, "results_hydrogen_production.csv"), String)
        @test isfile(joinpath(solution_dir, "hydrogenCO2OperationalDuals.csv"))
        @test length(CSV.File(joinpath(solution_dir, "hydrogenPipelineFlow.csv"))) == 188
        @test length(CSV.File(joinpath(solution_dir, "co2Operations.csv"))) ==
              length(sets.Hydrogen.CO2DirectionalLink) +
              length(sets.Hydrogen.CO2SequestrationNode)

        # Tables added to match InternalEMPIRE's output set. Each has one row per
        # (node, operational period) family, and each writes both the native name
        # and the Python-style alias.
        operational_periods = length(collect(periods))
        for (native, alias, rows) in (
            ("transportElectricity.csv", "results_transport_electricity_operations.csv",
             length(OpenEMPIRE.natural_gas_onshore_nodes(sets)) * operational_periods),
            ("naturalGasForHydrogen.csv", "results_natural_gas_hydrogen.csv",
             length(sets.Hydrogen.ProductionNode) * length(sets.Hydrogen.ReformerPlant) *
             operational_periods),
            ("hydrogenUse.csv", "results_hydrogen_use.csv",
             length(sets.Hydrogen.ProductionNode) * operational_periods),
        )
            @test length(CSV.File(joinpath(solution_dir, native))) == rows
            @test read(joinpath(solution_dir, native), String) ==
                  read(joinpath(solution_dir, alias), String)
        end

        # hydrogenUse aggregates quantities the module already reports separately;
        # production must agree with the electrolyser + reformer totals.
        use_rows = CSV.File(joinpath(solution_dir, "hydrogenUse.csv"))
        produced = sum(row.Produced_ton for row in use_rows)
        elyzer = sum(
            OpenEMPIRE._solution_value(model[:electrolyzerHydrogen][n, t])
            for n in sets.Hydrogen.ProductionNode, t in periods
        )
        reformed = sum(
            OpenEMPIRE._solution_value(model[:reformerHydrogenTon][n, p, t])
            for n in sets.Hydrogen.ProductionNode, p in sets.Hydrogen.ReformerPlant,
                t in periods
        )
        @test produced ≈ elyzer + reformed atol = 1e-6
        # The out-of-sample tail of this test is deliberately absent. It asserted the
        # 14 Hydrogen/CO2 fixed-investment alias files and round-tripped them through
        # fix_investments_from_results!, which relies on the Hydrogen additions to
        # out_of_sample.jl. Those are not part of this PR: the extended out-of-sample
        # stack is still in review as PRs #18-#29. Everything above covers the
        # Hydrogen module itself; the OOS integration belongs on a branch carrying
        # both.
    end
end

function test_hydrogen_malformed_cell_errors()
    cases = (
        ("Period,Value\n1,alphabetic\n", "expected a number"),
        ("Period,Value\n1,NaN\n", "value must be finite"),
        ("Period,Value\n1,-1\n", "value must be non-negative"),
        ("Period,Value\n1,\n", "empty value"),
        ("Period,Value\n1,1\n1,2\n", "Duplicate Hydrogen key"),
        ("Period,Wrong\n1,1\n", "has headers"),
    )
    mktempdir() do root
        path = joinpath(root, "values.csv")
        for (contents, expected) in cases
            _write_csv(path, contents)
            error = try
                OpenEMPIRE._read_sector_period_values(
                    path,
                    ("Period", "Value"),
                    "Hydrogen",
                )
                nothing
            catch err
                err
            end
            @test error isa ArgumentError
            @test occursin(expected, sprint(showerror, error))
            @test occursin(path, sprint(showerror, error))
        end
    end
end

function test_hydrogen_oos_full_year_integration()
    source_config = Dict{String, Any}(
        "forecast_horizon_year" => 2025,
        "leap_years_investment" => 5,
        "north_sea" => false,
        "natural_gas" => true,
        "hydrogen" => true,
        "use_emission_cap" => false,
        "discount_rate" => 0.05,
        "wacc" => 0.05,
        "load_change_module" => false,
    )
    fixed_metadata = Dict{String, Any}(
        "provenance" => Dict{String, Any}(
            "structural_config" => OpenEMPIRE._oos_structural_config(source_config),
        ),
    )
    compatible = OpenEMPIRE.validate_oos_fixed_investment_compatibility(
        fixed_metadata,
        source_config,
    )
    @test "hydrogen" in compatible["required_equal"]
    @test_throws ArgumentError OpenEMPIRE.validate_oos_fixed_investment_compatibility(
        fixed_metadata,
        merge(source_config, Dict("hydrogen" => false)),
    )

    mktempdir() do root
        summaries = NamedTuple[]
        for tree_index in 1:24
            run_dir = joinpath(root, "tree$tree_index")
            rows = [
                "Source,Node,Technology,Period,Scenario,WeatherScenario,GasScenario,Season,Hour,Hydrogen_ton_per_h",
            ]
            append!(
                rows,
                "Import,A,PipelineH2Import,1,1,1,1,winter,$hour,$tree_index"
                for hour in 1:365
            )
            push!(rows, "Import,A,PipelineH2Import,1,1,1,1,peak1,1,999999")
            output_dir = joinpath(run_dir, "output")
            mkpath(output_dir)
            write(joinpath(output_dir, "hydrogenProduction.csv"), join(rows, '\n') * "\n")
            push!(summaries, (
                Tree = "tree$tree_index",
                Seed = tree_index,
                RunDirectory = run_dir,
                FullYearTreeIndex = tree_index,
            ))
        end
        result = OpenEMPIRE._stream_internalempire_full_year_csv(
            summaries,
            "hydrogenProduction.csv",
            joinpath(root, "combined"),
        )
        @test result.rows == 8760
        @test result.dummy_peak_rows_ignored == 24
        rows = collect(CSV.File(result.path))
        @test Int(first(rows).HourFullYear) == 1
        @test Int(last(rows).HourFullYear) == 8760
        @test all(Float64(row.Hydrogen_ton_per_h) != 999999.0 for row in rows)
    end
end

function test_hydrogen_controlled_solution_parity()
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
    fixture = joinpath(root, "test", "data", "hydrogen_parity")
    julia_script = joinpath(root, "scripts", "hydrogen_parity_julia.jl")
    python_script = joinpath(root, "scripts", "hydrogen_parity_python.py")
    comparator = joinpath(root, "scripts", "compare_hydrogen_parity.py")
    mktempdir() do output_dir
        julia_output = joinpath(output_dir, "julia.csv")
        python_output = joinpath(output_dir, "python.csv")
        julia = Base.julia_cmd()
        @test success(
            run(
                ignorestatus(
                    `$julia --project=$root $julia_script $fixture $julia_output`,
                ),
            ),
        )
        @test success(
            run(ignorestatus(`$python $python_script $fixture $python_output`)),
        )
        @test success(
            run(
                ignorestatus(
                    `$python $comparator $julia_output $python_output`,
                ),
            ),
        )
    end
end

function test_hydrogen_full_result_verifier()
    python = get(
        ENV,
        "OPENEMPIRE_PYTHON",
        something(Sys.which("python3"), Sys.which("python"), ""),
    )
    isempty(python) && return @test_skip "Python is unavailable"
    test_script = joinpath(
        pkgdir(OpenEMPIRE),
        "test",
        "test_hydrogen_result_verifier.py",
    )
    @test success(run(ignorestatus(`$python $test_script`)))
end

function test_hydrogen_oos_capacity_validation()
    cases = (
        ("Node,Period,Value\nA,1,alphabetic\n", "nonnumeric value"),
        ("Node,Period,Value\nA,1,NaN\n", "non-finite value"),
        ("Node,Period,Value\nA,1,Inf\n", "non-finite value"),
        ("Node,Period,Value\nA,1,-1\n", "negative value"),
        ("Node,Period,Value\nA,1.5,1\n", "fractional integer value"),
        ("Node,Period,Value\nA,999999999999999999999,1\n", "overflowing integer value"),
        ("Node,Period,Value\nA,1,\n", "missing value"),
        ("Node,Period,Value\nA,1,1\nA,1,2\n", "duplicate key"),
    )
    mktempdir() do root
        path = joinpath(root, "hydrogen.csv")
        for (contents, expected) in cases
            write(path, contents)
            error = try
                OpenEMPIRE._read_oos_capacity_table(
                    root,
                    "hydrogen.csv",
                    ("Node", "Period"),
                    "Value",
                )
                nothing
            catch err
                err
            end
            @test error isa ArgumentError
            message = sprint(showerror, error)
            @test occursin("Malformed Hydrogen fixed-investment file $path", message)
            @test occursin(expected, lowercase(message))
            @test occursin("data row", message)
        end
        write(path, "Node,Period,Other\nA,1,1\n")
        error = try
            OpenEMPIRE._read_oos_capacity_table(
                root,
                "hydrogen.csv",
                ("Node", "Period"),
                "Value",
            )
            nothing
        catch err
            err
        end
        @test error isa ArgumentError
        @test occursin(path, sprint(showerror, error))
        @test occursin("missing column(s) Value", sprint(showerror, error))
        write(path, "Node,Period,Value\n")
        @test_throws ArgumentError OpenEMPIRE._read_oos_capacity_table(
            root,
            "hydrogen.csv",
            ("Node", "Period"),
            "Value",
        )
    end
end
