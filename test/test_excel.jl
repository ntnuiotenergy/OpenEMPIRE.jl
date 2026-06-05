function test_read_excel_sets()

    sets = OpenEMPIRE.read_sets_xlsx(joinpath(pkgdir(OpenEMPIRE), "data"))

    @test length(sets.Node) == 3
    @test length(sets.Generator) == 27
    @test length(sets.Storage) == 2
    @test length(sets.StoragesOfNode) == 5
    @test length(sets.GeneratorsOfNode) == 65
    @test length(sets.DirectionalLink) == 4
    @test length(sets.Technology) == 18
    @test length(sets.GeneratorsOfTechnology) == 47

    # Constructor computes and stores index maps; verify consistency with base relation tables.
    for n in sets.Node
        @test Set(OpenEMPIRE.generators(sets, n)) == Set(g for (nn, g) in sets.GeneratorsOfNode if nn == n)
        @test Set(OpenEMPIRE.storages(sets, n)) == Set(s for (nn, s) in sets.StoragesOfNode if nn == n)
        @test Set(OpenEMPIRE.techs(sets, n)) ==
            Set(t for (t, g) in sets.GeneratorsOfTechnology if (n, g) in sets.GeneratorsOfNode)
    end

    for n in sets.Node
        for t in OpenEMPIRE.techs(sets, n)
            @test Set(OpenEMPIRE.generators_tech(sets, n, t)) ==
                Set(g for (tt, g) in sets.GeneratorsOfTechnology if tt == t && (n, g) in sets.GeneratorsOfNode)
        end
    end

    @test OpenEMPIRE.validate!(sets) === sets

    emp = JuMP.Model()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)
    OpenEMPIRE.create_variables(emp, sets, periods)
    @test num_variables(emp) == 777198

end

function test_read_excel_params()

    params = OpenEMPIRE.read_params_xlsx(joinpath(pkgdir(OpenEMPIRE),"data"))

    sets = OpenEMPIRE.read_sets_xlsx(joinpath(pkgdir(OpenEMPIRE), "data"))
    periods = OpenEMPIRE.create_timestruct(2, 5, 4, 24, 2, 24, 2)
    params.WACC = 0.05
    params.discountRate = 0.03

    OpenEMPIRE.preprocess_invest_cost(params, sets, periods)
    OpenEMPIRE.preprocess_operational_cost(params, sets, periods)
    OpenEMPIRE.preprocess_initcap_gen(params, sets, periods)
end

function test_validate_params()
    # Build a small, hand-crafted EmpireSets
    sets = OpenEMPIRE.EmpireSets(;
        Generator = ["gas", "wind"],
        ThermalGenerators = ["gas"],
        Storage = ["battery"],
        Technology = ["thermal", "renewable"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("A", "B", "HVDC"), ("B", "A", "HVDC")],
        GeneratorsOfTechnology = [("thermal", "gas"), ("renewable", "wind")],
        GeneratorsOfNode = [("A", "gas"), ("A", "wind"), ("B", "wind")],
        StoragesOfNode = [("B", "battery")],
    )

    periods = OpenEMPIRE.create_timestruct(2, 5, 2, 24, 1, 24, 1)

    # Minimal valid params: a scalar TimeProfile, a per-generator dict and a
    # per-(node, generator) dict.
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.03,
        CO2price = FixedProfile(10.0),
        genLifetime = Dict("gas" => 30.0, "wind" => 25.0),
        storageLifetime = Dict("battery" => 15.0),
        lineEfficiency = Dict(("A", "B") => 0.95, ("B", "A") => 0.95),
        genCapitalCost = Dict{String, TimeProfile}(
            "gas"  => FixedProfile(100.0),
            "wind" => FixedProfile(200.0),
        ),
        genInitCap = Dict{Tuple{String,String}, TimeProfile}(
            ("A", "gas")  => FixedProfile(50.0),
            ("A", "wind") => FixedProfile(20.0),
        ),
    )

    # All three validation modes should pass and return `params`
    @test OpenEMPIRE.validate(params) === params
    @test OpenEMPIRE.validate(params; sets = sets) === params
    @test OpenEMPIRE.validate(params; sets = sets, periods = periods) === params

    # Non-strict mode returns a (possibly empty) list of issue messages
    issues = OpenEMPIRE.validate(params; sets = sets, periods = periods, strict = false)
    @test issues isa Vector{String}
    @test isempty(issues)

    # Out-of-range scalar values should be detected
    bad = deepcopy(params)
    bad.WACC = 1.5
    @test_throws ArgumentError OpenEMPIRE.validate(bad)

    # Negative lifetime should be detected
    bad = deepcopy(params)
    bad.genLifetime["gas"] = -1.0
    @test_throws ArgumentError OpenEMPIRE.validate(bad)

    # Efficiency outside [0, 1]
    bad = deepcopy(params)
    bad.lineEfficiency[("A", "B")] = 1.5
    @test_throws ArgumentError OpenEMPIRE.validate(bad)

    # Negative profile values are detected only when periods is supplied
    bad = deepcopy(params)
    bad.genCapitalCost["gas"] = FixedProfile(-1.0)
    @test OpenEMPIRE.validate(bad) === bad   # not caught without periods
    @test_throws ArgumentError OpenEMPIRE.validate(bad; periods = periods)

    # Unknown generator id is detected when sets are supplied
    bad = deepcopy(params)
    bad.genLifetime["___unknown_gen___"] = 20.0
    @test OpenEMPIRE.validate(bad) === bad   # not caught without sets
    @test_throws ArgumentError OpenEMPIRE.validate(bad; sets = sets)

    # Invalid (node, generator) pair (gas does not exist at node B)
    bad = deepcopy(params)
    bad.genInitCap[("B", "gas")] = FixedProfile(10.0)
    @test_throws ArgumentError OpenEMPIRE.validate(bad; sets = sets)

    # Unknown arc in transmission dict
    bad = deepcopy(params)
    bad.lineEfficiency[("A", "C")] = 0.9
    @test_throws ArgumentError OpenEMPIRE.validate(bad; sets = sets)
end
