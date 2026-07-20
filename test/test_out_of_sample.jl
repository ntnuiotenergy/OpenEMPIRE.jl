function _oos_test_sets_and_periods()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [
            ("A", "B", "HVDC"),
            ("B", "A", "HVDC"),
        ],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    return sets, periods
end

function _write_oos_csv(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
end

function _oos_source_snapshot(root)
    snapshot = Dict{String, String}()
    for (directory, _, filenames) in walkdir(root)
        for filename in filenames
            path = joinpath(directory, filename)
            snapshot[relpath(path, root)] = OpenEMPIRE._oos_sha256_file(path)
        end
    end
    return snapshot
end

function test_generate_single_oos_scenario_tree()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        source_before = _oos_source_snapshot(source_data)

        tree_dir = joinpath(root, "trees", "oos_tree1")
        generated_tree = OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            tree_dir;
            input_format = :csv,
            seed = 23,
        )

        @test generated_tree == abspath(tree_dir)
        @test _oos_source_snapshot(source_data) == source_before
        scenario_dir = joinpath(generated_tree, "ScenarioData")
        @test all(
            isfile(joinpath(scenario_dir, filename)) for
            filename in OpenEMPIRE._OOS_TREE_FILENAMES
        )

        metadata = YAML.load_file(joinpath(generated_tree, "metadata.yaml"))
        @test metadata["schema_version"] == 1
        @test metadata["generator"] == "OpenEMPIRE.generate_oos_scenario_tree"
        @test metadata["tree"] == "oos_tree1"
        @test metadata["seed"] == 23
        @test metadata["input_format"] == "csv"
        @test metadata["source_data_folder"] == abspath(source_data)
        @test metadata["source_data_sha256"] == OpenEMPIRE._oos_directory_sha256(source_data)
        @test metadata["source_config_sha256"] == OpenEMPIRE._oos_sha256_file(config_file)
        @test metadata["config"]["number_of_scenarios"] == 3
        for filename in OpenEMPIRE._OOS_TREE_FILENAMES
            file_metadata = metadata["files"][filename]
            generated_file = joinpath(scenario_dir, filename)
            @test file_metadata["bytes"] == filesize(generated_file)
            @test file_metadata["sha256"] == OpenEMPIRE._oos_sha256_file(generated_file)
        end

        second_tree = OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            joinpath(root, "trees", "oos_tree2");
            input_format = :csv,
            seed = 23,
        )
        for filename in OpenEMPIRE._OOS_TREE_FILENAMES
            @test OpenEMPIRE._oos_sha256_file(joinpath(second_tree, "ScenarioData", filename)) ==
                  OpenEMPIRE._oos_sha256_file(joinpath(scenario_dir, filename))
        end
        @test _oos_source_snapshot(source_data) == source_before

        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            tree_dir;
            input_format = :csv,
            seed = 24,
        )
        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            joinpath(source_data, "oos_tree");
            input_format = :csv,
            seed = 24,
        )

        disabled_config = joinpath(root, "disabled.yaml")
        config = YAML.load_file(config_file)
        config["use_scenario_generation"] = false
        YAML.write_file(disabled_config, config)
        disabled_tree = joinpath(root, "trees", "disabled")
        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            disabled_config,
            source_data,
            disabled_tree;
            input_format = :csv,
            seed = 24,
        )
        @test !ispath(disabled_tree)
    end
end

function _write_investment_csvs(output_dir; include_installed = true, extra_generator = false)
    generator_rows = extra_generator ?
                     "A,Solar,1,3.5\nB,Solar,1,1.0\n" :
                     "A,Solar,1,3.5\n"
    _write_oos_csv(
        joinpath(output_dir, "genInvCap.csv"),
        "Node,Generator,Period,genInvCap\n$generator_rows",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmisionInvCap.csv"),
        "FromNode,ToNode,Period,transmisionInvCap\nA,B,1,4.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInvCap.csv"),
        "Node,Storage,Period,storPWInvCap\nA,battery,1,5.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInvCap.csv"),
        "Node,Storage,Period,storENInvCap\nA,battery,1,6.5\n",
    )

    include_installed || return output_dir

    _write_oos_csv(
        joinpath(output_dir, "genInstalledCap.csv"),
        "Node,Generator,Period,genInstalledCap\nA,Solar,1,7.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmissionInstalledCap.csv"),
        "FromNode,ToNode,Period,transmissionInstalledCap\nA,B,1,8.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInstalledCap.csv"),
        "Node,Storage,Period,storPWInstalledCap\nA,battery,1,9.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInstalledCap.csv"),
        "Node,Storage,Period,storENInstalledCap\nA,battery,1,10.5\n",
    )
    return output_dir
end

function test_fix_investments_from_results()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "output"))
        @test OpenEMPIRE.fix_investments_from_results!(model, sets, periods, result_dir) === model
    end

    expected = (
        (:genInvCap, ("A", "Solar", strategic_period), 3.5),
        (:transmissionInvCap, ("A", "B", strategic_period), 4.5),
        (:storPWInvCap, ("A", "battery", strategic_period), 5.5),
        (:storENInvCap, ("A", "battery", strategic_period), 6.5),
        (:genInstalledCap, ("A", "Solar", strategic_period), 7.5),
        (:transmissionInstalledCap, ("A", "B", strategic_period), 8.5),
        (:storPWInstalledCap, ("A", "battery", strategic_period), 9.5),
        (:storENInstalledCap, ("A", "battery", strategic_period), 10.5),
    )
    for (name, index, value) in expected
        variable = model[name][index...]
        @test JuMP.is_fixed(variable)
        @test JuMP.fix_value(variable) == value
    end
end

function test_fix_only_investment_capacities()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "Output"); include_installed = false)
        OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    @test JuMP.is_fixed(model[:genInvCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(model[:genInstalledCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(model[:transmissionInstalledCap]["A", "B", strategic_period])
    @test !JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", strategic_period])
    @test !JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", strategic_period])
end

function test_fixed_investment_key_validation()
    sets, periods = _oos_test_sets_and_periods()

    mktempdir() do result_dir
        output_dir = joinpath(result_dir, "output")
        _write_investment_csvs(output_dir; include_installed = false, extra_generator = true)
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    mktempdir() do result_dir
        output_dir = joinpath(result_dir, "output")
        _write_investment_csvs(output_dir; include_installed = false)
        write(
            joinpath(output_dir, "genInvCap.csv"),
            "Node,Generator,Period,genInvCap\n",
        )
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end
end
