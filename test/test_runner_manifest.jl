include(joinpath(@__DIR__, "..", "scripts", "runner_manifest.jl"))

function test_runner_manifest_helpers()
    @test _read_command(`printf " value \n"`) == "value"
    @test _read_command(`false`) === nothing

    attributes = (("Threads" => 4), ("Method" => 2))
    @test _optimizer_attributes_manifest(attributes) ==
          Dict{String, Any}("Threads" => 4, "Method" => 2)

    mktempdir() do root
        missing = _sampling_key_info(root)
        @test !missing["exists"]
        @test missing["sha256"] === nothing

        scenario_dir = joinpath(root, "ScenarioData")
        mkpath(scenario_dir)
        sampling_key = joinpath(scenario_dir, "sampling_key.csv")
        write(sampling_key, "abc")

        present = _sampling_key_info(root)
        @test present["exists"]
        @test present["path"] == sampling_key
        @test present["sha256"] ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

        manifest_path = joinpath(root, "nested", "run_manifest.yaml")
        manifest = Dict{String, Any}(
            "status" => "started",
            "solver" => Dict("name" => "HiGHS"),
        )
        @test _write_run_manifest(manifest_path, manifest) == manifest_path
        @test YAML.load_file(manifest_path) == manifest
    end

    git = _git_info()
    @test git["branch"] isa String
    @test git["commit"] isa String
    @test git["dirty"] isa Bool

    return nothing
end
