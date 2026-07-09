include(joinpath(@__DIR__, "..", "scripts", "run_out_of_sample_trees.jl"))

function _write_required_scenario_files(tree_path)
    scenario_dir = joinpath(tree_path, "ScenarioData")
    mkpath(scenario_dir)
    for filename in REQUIRED_SCENARIO_FILES
        write(joinpath(scenario_dir, filename), "fixture\n")
    end
    return tree_path
end

function test_discover_and_select_oos_trees()
    mktempdir() do root
        _write_required_scenario_files(joinpath(root, "oos_tree10"))
        _write_required_scenario_files(joinpath(root, "oos_tree2"))
        _write_required_scenario_files(joinpath(root, "oos_tree1"))
        mkpath(joinpath(root, "notes"))

        trees = discover_oos_trees(root)
        @test [tree.index for tree in trees] == [1, 2, 10]
        @test [tree.index for tree in select_oos_trees(trees, 1, 2)] == [1, 2]
        @test_throws ArgumentError select_oos_trees(trees, 1, 3)
        @test validate_oos_tree(first(trees)) == first(trees)
    end
end

function test_validate_oos_tree_files()
    mktempdir() do root
        tree_path = joinpath(root, "oos_tree1")
        mkpath(joinpath(tree_path, "ScenarioData"))
        tree = (index = 1, name = "oos_tree1", path = tree_path)
        @test_throws ArgumentError validate_oos_tree(tree)
    end
end

function test_validate_fixed_investment_files()
    mktempdir() do root
        output_dir = joinpath(root, "output")
        mkpath(output_dir)
        @test_throws ArgumentError validate_fixed_investment_dir(root)

        for alternatives in REQUIRED_FIXED_INVESTMENT_FILES
            write(joinpath(output_dir, first(alternatives)), "fixture\n")
        end
        validated_dir = validate_fixed_investment_dir(root)
        @test lowercase(normpath(validated_dir)) == lowercase(normpath(output_dir))
    end
end

function test_write_multiple_oos_summary()
    mktempdir() do root
        rows = [(
            tree = "oos_tree1",
            seed = "101",
            status = "OPTIMAL",
            objective = "12.5",
            build_seconds = "1.0",
            solve_seconds = "2.0",
            result_directory = joinpath(root, "oos_tree1"),
            error = "",
        )]
        path = write_batch_summary(joinpath(root, "batch_summary.csv"), rows)
        contents = read(path, String)
        @test startswith(contents, "tree,seed,status,objective")
        @test occursin("oos_tree1,101,OPTIMAL,12.5", contents)

        report_path = write_batch_report(joinpath(root, "batch_summary.txt"), rows)
        report = read(report_path, String)
        @test occursin("trees_completed=1", report)
        @test occursin("status_OPTIMAL=1", report)

        run_summary = joinpath(root, "summary.txt")
        write(run_summary, "termination_status=INFEASIBLE\nobjective_value=unavailable\n")
        parsed = _read_run_summary(run_summary)
        @test parsed["termination_status"] == "INFEASIBLE"
        @test parsed["objective_value"] == "unavailable"
    end
end
