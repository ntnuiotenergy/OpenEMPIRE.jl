include(joinpath(@__DIR__, "..", "scripts", "aggregate_out_of_sample_results.jl"))

function _write_batch_summary(path)
    mkpath(dirname(path))
    write(
        path,
        join([
            "tree,seed,status,objective,build_seconds,solve_seconds,result_directory,error",
            "oos_tree1,101,OPTIMAL,10.0,1.0,2.0,$(dirname(path))/oos_tree1,",
            "oos_tree2,102,INFEASIBLE,unavailable,1.1,0.5,$(dirname(path))/oos_tree2,",
            "oos_tree3,103,OPTIMAL,12.0,1.2,2.4,$(dirname(path))/oos_tree3,",
        ], "\n") * "\n",
    )
end

function _write_tree_output(batch_dir, tree_name, filename, rows)
    output_dir = joinpath(batch_dir, tree_name, "output")
    mkpath(output_dir)
    write(joinpath(output_dir, filename), rows)
end

function test_aggregate_oos_result_file()
    mktempdir() do batch_dir
        _write_batch_summary(joinpath(batch_dir, "batch_summary.csv"))
        rows = join([
            "Node,Generator,Period,Scenario,Season,Hour,genOperational",
            "N1,G1,1,1,winter,1,5.0",
        ], "\n") * "\n"
        _write_tree_output(batch_dir, "oos_tree1", "genOperational.csv", rows)
        _write_tree_output(batch_dir, "oos_tree3", "genOperational.csv", replace(rows, "5.0" => "7.0"))

        result = aggregate_oos_results(
            batch_dir;
            files = ["genOperational.csv"],
            run_name = "fixture_run",
        )

        aggregated = read(joinpath(result.output_dir, "genOperational.csv"), String)
        @test startswith(aggregated, "Tree,TreeIndex,Run,Node,Generator,Period,Scenario,Season,Hour,genOperational")
        @test occursin("oos_tree1,1,fixture_run,N1,G1,1,1,winter,1,5.0", aggregated)
        @test occursin("oos_tree3,3,fixture_run,N1,G1,1,1,winter,1,7.0", aggregated)
        @test !occursin("oos_tree2", aggregated)

        summary = read(joinpath(result.output_dir, "oos_summary.csv"), String)
        @test occursin("oos_tree2,2,fixture_run,102,INFEASIBLE,unavailable", summary)

        report = read(joinpath(result.output_dir, "aggregation_summary.txt"), String)
        @test occursin("total_trees=3", report)
        @test occursin("selected_trees=2", report)
        @test occursin("genOperational_rows=2", report)
    end
end

function test_aggregate_oos_missing_file_modes()
    mktempdir() do batch_dir
        _write_batch_summary(joinpath(batch_dir, "batch_summary.csv"))
        _write_tree_output(
            batch_dir,
            "oos_tree1",
            "loadShed.csv",
            "Node,Period,Scenario,Season,Hour,loadShed\nN1,1,1,winter,1,0.0\n",
        )

        result = aggregate_oos_results(
            batch_dir;
            files = ["loadShed.csv", "storCharge.csv"],
            run_name = "fixture_run",
            skip_missing = true,
        )
        @test isfile(joinpath(result.output_dir, "loadShed.csv"))
        @test !isfile(joinpath(result.output_dir, "storCharge.csv"))

        @test_throws ArgumentError aggregate_oos_results(
            batch_dir;
            files = ["loadShed.csv", "storCharge.csv"],
            run_name = "fixture_run",
            skip_missing = false,
        )
    end
end

function test_aggregate_oos_status_filter()
    mktempdir() do batch_dir
        _write_batch_summary(joinpath(batch_dir, "batch_summary.csv"))
        @test_throws ArgumentError aggregate_oos_results(
            batch_dir;
            files = ["genOperational.csv"],
            status_filter = "TIME_LIMIT",
        )
    end
end
