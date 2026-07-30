include(joinpath(@__DIR__, "..", "scripts", "runner_performance.jl"))

function test_runner_performance_helpers()
    @test !_perf_enabled()
    withenv("EMPIRE_PERF" => "yes") do
        @test _perf_enabled()
    end
    withenv("EMPIRE_PERF" => "false") do
        @test !_perf_enabled()
    end

    object = JObj([
        "text" => "a\n\"b\"",
        "integer" => 2,
        "finite" => 1.5,
        "nonfinite" => Inf,
        "missing" => nothing,
        "values" => Any[true, :symbol],
    ])
    @test _json(object) ==
          "{\"text\":\"a\\n\\\"b\\\"\",\"integer\":2,\"finite\":1.5," *
          "\"nonfinite\":null,\"missing\":null,\"values\":[true,\"symbol\"]}"

    mktempdir() do root
        path = joinpath(root, "perf.json")
        @test _write_perf_json(path, object) == path
        @test read(path, String) == _json(object) * "\n"
    end

    phase = _perf_phase("build", 1.2349; alloc_bytes = 12, gc_seconds = 0.0019)
    phase_values = Dict(phase.pairs)
    @test phase_values["name"] == "build"
    @test phase_values["wall_seconds"] == 1.235
    @test phase_values["alloc_bytes"] == 12
    @test phase_values["gc_seconds"] == 0.002
    @test phase_values["rss_peak_bytes"] isa Int
    @test phase_values["live_bytes"] isa Int

    model = JuMP.Model()
    @variable(model, x[1:2] >= 0)
    @constraint(model, lower_bound[i in 1:2], x[i] >= i)
    @constraint(model, total, sum(x) <= 10)

    @test _family_cref_count(model[:x]) == 0
    @test _family_cref_count(model[:lower_bound]) == 2
    @test _family_cref_count(model[:total]) == 1
    @test report_constraint_family_counts(model) ==
          [("lower_bound", 2), ("total", 1)]

    return nothing
end
