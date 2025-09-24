
function test_timestruct()

    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    @test length(strat_periods(periods)) == 3
    @test sum(multiple(t) * probability(t) * duration(t) for t in periods) ≈ 8760 * 15
end

function test_variables()

    sets = OpenEMPIRE.EmpireSets()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    sets.Node = ["N1", "N2"]
    sets.Generator = ["G1", "G2"]
    sets.Storage = ["S1", "S2"]
    sets.StoragesOfNode = [("N1", "S1"), ("N2", "S2")]
    sets.GeneratorsOfNode = [("N1", "G1"), ("N2", "G2")]
    sets.BidirectionalArc = [("N1", "N2"), ("N2", "N1")]

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @test num_variables(emp) == 89329

end

function test_variable_large()

    sets = OpenEMPIRE.EmpireSets()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    # Create large sets
    sets.Node = ["N$(i)" for i in 1:20]
    sets.Generator = ["G$(i)" for i in 1:40]
    sets.Storage = ["S$(i)" for i in 1:20]
    sets.StoragesOfNode = [(n, s) for (n,s) in zip(sets.Node, sets.Storage)]
    sets.GeneratorsOfNode = [(n, g) for (n, g) in zip(sets.Node, sets.Generator)]
    sets.DirectionalLink = [(n1, n2) for n1 in sets.Node for n2 in sets.Node if n1 != n2][1:100]

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)

end


function test_constraints()
    sets = OpenEMPIRE.EmpireSets()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    sets.Node = ["N1", "N2"]
    sets.Generator = ["G1", "G2"]
    sets.Storage = ["S1", "S2"]
    sets.StoragesOfNode = [("N1", "S1"), ("N2", "S2")]
    sets.GeneratorsOfNode = [("N1", "G1"), ("N2", "G2")]
    sets.DirectionalLink = [("N1", "N2"), ("N2", "N1")]
    sets.Technology = ["Coal", "Gas"]
    sets.GeneratorsOfTechnology = [("Coal", "G1"), ("Gas", "G2")]

    # Example parameters
    par = OpenEMPIRE.EmpireParams()
    par.lineEfficiency = Dict(("N1", "N2") => 0.95, ("N2", "N1") => 0.95)
    par.storageDischargeEff = Dict("S1" => 0.9, "S2" => 0.9)
    par.storageChargeEff = Dict("S1" => 0.9, "S2" => 0.9)
    par.storageBleedEff = Dict("S1" => 0.99, "S2" => 0.99)
    par.storOperationalInit = Dict("S1" => 0.5, "S2" => 0.6)
    par.genCapAvail = Dict( ("N1", "G1", t) => 100.0 for t in periods)
    par.genCapAvail = merge(par.genCapAvail, Dict( ("N2", "G2", t) => 150.0 for t in periods))
    par.genRampUpCap = Dict("G1" => 20.0, "G2" => 30.0)
    par.storageLifetime = Dict("S1" => 20, "S2" => 20)
    par.storENInitCap = Dict( ("S1", sp) => 50.0 for sp in periods)
    par.storENInitCap = merge(par.storENInitCap, Dict( ("S2", sp) => 60.0 for sp in periods))
    par.storPWInitCap = Dict( ("S1", sp) => 30.0 for sp in periods)
    par.storPWInitCap = merge(par.storPWInitCap, Dict( ("S2", sp) => 40.0 for sp in periods))
    par.genInitCap = Dict( ("N1", "G1", sp) => 80.0 for sp in periods)
    par.genInitCap = merge(par.genInitCap, Dict( ("N2", "G2", sp) => 120.0 for sp in periods))
    par.genMaxBuiltCap = Dict( ("N1", "G1") => 200.0, ("N2", "G2") => 250.0)
    par.genMaxInstalledCap = Dict( ("N1", "G1") => 300.0, ("N2", "G2") => 350.0)
    par.genLifetime = Dict("G1" => 25, "G2" => 30)
    par.transmissionInitCap = Dict( ("N1", "N2") => 100.0, ("N2", "N1") => 100.0)

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @time OpenEMPIRE.create_constraints(emp, sets, par,periods)
    @time OpenEMPIRE.create_objective(emp, sets, par, periods)

end
