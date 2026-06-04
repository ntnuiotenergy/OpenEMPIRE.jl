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
