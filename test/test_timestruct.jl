
function test_timestruct()

    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    @test length(strat_periods(periods)) == 3
    @test sum(multiple(t) * probability(t) * duration(t) for t in periods) ≈ 8760 * 15
end

function test_variables()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)
    sets = OpenEMPIRE.EmpireSets(
        Node = ["N1", "N2"],
        Generator = ["G1", "G2"],
        Storage = ["S1", "S2"],
        Technology = ["Coal", "Gas"],
        StoragesOfNode = [("N1", "S1"), ("N2", "S2")],
        GeneratorsOfNode = [("N1", "G1"), ("N2", "G2")],
        GeneratorsOfTechnology = [("Coal", "G1"), ("Gas", "G2")],
        DirectionalLink = [("N1", "N2"), ("N2", "N1")],
        TransmissionType = ["AC"],
        TransmissionTypeOfDirectionalLink = [("N1", "N2", "AC"), ("N2", "N1", "AC")],
    )

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @test num_variables(emp) > 0

end

function test_variable_large()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)

    # Create large sets
    nodes = ["N$(i)" for i in 1:10]
    generators = ["G$(i)" for i in 1:10]
    storages = ["S$(i)" for i in 1:5]
    links = [(n1, n2) for n1 in nodes for n2 in nodes if n1 != n2][1:30]
    sets = OpenEMPIRE.EmpireSets(
        Node = nodes,
        Generator = generators,
        Storage = storages,
        Technology = ["Tech$(i)" for i in 1:10],
        StoragesOfNode = [(n, s) for (n, s) in zip(nodes, storages)],
        GeneratorsOfNode = [(n, g) for (n, g) in zip(nodes, generators)],
        GeneratorsOfTechnology = [("Tech$(i)", "G$(i)") for i in 1:10],
        DirectionalLink = links,
        TransmissionType = ["AC"],
        TransmissionTypeOfDirectionalLink = [(m, n, "AC") for (m, n) in links],
    )

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @test num_variables(emp) > 0

end


function test_constraints()
    periods = OpenEMPIRE.create_timestruct(3, 5, 4, 168, 3, 24, 4)
    sets = OpenEMPIRE.EmpireSets(
        Node = ["N1", "N2"],
        Generator = ["G1", "G2"],
        Storage = ["S1", "S2"],
        Technology = ["Coal", "Gas"],
        StoragesOfNode = [("N1", "S1"), ("N2", "S2")],
        GeneratorsOfNode = [("N1", "G1"), ("N2", "G2")],
        GeneratorsOfTechnology = [("Coal", "G1"), ("Gas", "G2")],
        DirectionalLink = [("N1", "N2"), ("N2", "N1")],
        TransmissionType = ["AC"],
        TransmissionTypeOfDirectionalLink = [("N1", "N2", "AC"), ("N2", "N1", "AC")],
    )

    # Example parameters
    par = OpenEMPIRE.EmpireParams()
    par.sload = Dict{String, TimeProfile}()
    par.genCapAvail = Dict{Tuple{String, String}, TimeProfile}()
    par.maxRegHydroGen = Dict{String, TimeProfile}()
    par.genInvCost = Dict{String, TimeProfile}()
    par.storENInvCost = Dict{String, TimeProfile}()
    par.storPWInvCost = Dict{String, TimeProfile}()
    par.transmissionInvCost = Dict{Tuple{String, String}, TimeProfile}()
    par.genMargCost = Dict{String, TimeProfile}()

    par.lineEfficiency = Dict(("N1", "N2") => 0.95, ("N2", "N1") => 0.95)
    par.storageDischargeEff = Dict("S1" => 0.9, "S2" => 0.9)
    par.storageChargeEff = Dict("S1" => 0.9, "S2" => 0.9)
    par.storageBleedEff = Dict("S1" => 0.99, "S2" => 0.99)
    par.storOperationalInit = Dict("S1" => 0.5, "S2" => 0.6)
    par.genCapAvailType = Dict("G1" => 1.0, "G2" => 1.0)
    par.genRampUpCap = Dict("G1" => 20.0, "G2" => 30.0)
    par.storageLifetime = Dict("S1" => 20, "S2" => 20)

    sps = collect(strat_periods(periods))
    par.storENInitCap = Dict(
        ("N1", "S1") => StrategicProfile([50.0 for _ in sps]),
        ("N2", "S2") => StrategicProfile([60.0 for _ in sps]),
    )
    par.storPWInitCap = Dict(
        ("N1", "S1") => StrategicProfile([30.0 for _ in sps]),
        ("N2", "S2") => StrategicProfile([40.0 for _ in sps]),
    )
    par.genInitCap = Dict(
        ("N1", "G1") => StrategicProfile([80.0 for _ in sps]),
        ("N2", "G2") => StrategicProfile([120.0 for _ in sps]),
    )
    par.genMaxBuiltCap = Dict{Tuple{String, String}, StrategicProfile}()
    par.genMaxInstalledCap = Dict{Tuple{String, String}, StrategicProfile}()
    par.genLifetime = Dict("G1" => 25, "G2" => 30)
    par.transmissionInitCap = Dict(
        ("N1", "N2") => StrategicProfile([100.0 for _ in sps]),
        ("N2", "N1") => StrategicProfile([100.0 for _ in sps]),
    )
    par.transmissionLifetime = Dict(("N1", "N2") => 40, ("N2", "N1") => 40)
    par.transmissionMaxBuiltCap = Dict{Tuple{String, String}, StrategicProfile}()
    par.transmissionMaxInstalledCap = Dict{Tuple{String, String}, StrategicProfile}()
    par.nodeLostLoadCost = Dict{String, StrategicProfile}()
    par.maxHydroNode = Dict{String, Float64}()

    emp = JuMP.Model()
    @time OpenEMPIRE.create_variables(emp, sets, periods)
    @time OpenEMPIRE.create_constraints(emp, sets, par,periods)
    @time OpenEMPIRE.create_objective(emp, sets, par, periods, Discounter(0.03, 1, periods))

    @test num_variables(emp) > 0

end
