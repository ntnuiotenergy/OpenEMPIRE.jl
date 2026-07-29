include(joinpath(@__DIR__, "..", "scripts", "runner_staging.jl"))

function test_stage_run_inputs_copies_without_mutating_source()
    mktempdir() do root
        source = joinpath(root, "source")
        scenario_dir = joinpath(source, "ScenarioData")
        sets_dir = joinpath(source, "Sets")
        mkpath(scenario_dir)
        mkpath(sets_dir)

        source_key = joinpath(scenario_dir, "sampling_key.csv")
        source_set = joinpath(sets_dir, "Node.csv")
        config_file = joinpath(root, "run.yaml")
        write(source_key, "Period,Scenario,Season,Year,Month,Hour\n1,1,winter,2020,1,4\n")
        write(source_set, "Node\nA\n")
        write(config_file, "use_scenario_generation: true\n")

        result_dir = joinpath(root, "result")
        staged_data, staged_config, staged_fixed_investments =
            _stage_run_inputs(result_dir, source, config_file)

        @test staged_data == joinpath(result_dir, "Input", "csv")
        @test staged_config == joinpath(result_dir, "Input", "config.yaml")
        @test isempty(staged_fixed_investments)
        @test read(joinpath(staged_data, "ScenarioData", "sampling_key.csv"), String) == read(source_key, String)
        @test read(staged_config, String) == read(config_file, String)

        write(joinpath(staged_data, "ScenarioData", "sampling_key.csv"), "changed\n")
        write(joinpath(staged_data, "ScenarioData", "sloadRaw.csv"), "generated\n")
        write(staged_config, "use_scenario_generation: false\n")

        @test read(source_key, String) == "Period,Scenario,Season,Year,Month,Hour\n1,1,winter,2020,1,4\n"
        @test !isfile(joinpath(source, "ScenarioData", "sloadRaw.csv"))
        @test read(config_file, String) == "use_scenario_generation: true\n"
    end
end
