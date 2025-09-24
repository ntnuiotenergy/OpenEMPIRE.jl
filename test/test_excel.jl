function test_read_excel_sets()

    sets = OpenEMPIRE.read_sets_xlsx("data")

    @test length(sets.Node) == 3
    @test length(sets.Generator) == 27
    @test length(sets.Storage) == 2
    @test length(sets.StoragesOfNode) == 5
    @test length(sets.GeneratorsOfNode) == 65
    @test length(sets.DirectionalLink) == 4
    @test length(sets.Technology) == 18
    @test length(sets.GeneratorsOfTechnology) == 47

    emp = JuMP.Model()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)
    OpenEMPIRE.create_variables(emp, sets, periods)
    @test num_variables(emp) == 750427

end

function test_read_excel_params()

    params = OpenEMPIRE.read_params_xlsx("data")


    sets = OpenEMPIRE.read_sets_xlsx("data")
    periods = OpenEMPIRE.create_timestruct(2, 5, 4, 24, 2, 24, 2)
    params.WACC = 0.05
    params.discountRate = 0.03

    OpenEMPIRE.preprocess_invest_cost(params, sets, periods)
    OpenEMPIRE.preprocess_operational_cost(params, sets, periods)



end
